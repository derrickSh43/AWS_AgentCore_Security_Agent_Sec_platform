# Setup Guide

This guide walks through installing the EKS Security Operations Platform into an existing Amazon EKS cluster.

The platform creates AWS resources and installs in-cluster components with Helm and the Kubernetes provider. It does not create the EKS cluster.

## 1. Prerequisites

Install these locally or in your CI runner:

- Terraform `>= 1.8.0`
- AWS CLI authenticated to the target AWS account
- `kubectl` with access to the target EKS cluster
- Helm CLI, for post-install checks
- Docker, only if you will build the optional AgentCore reasoner image
- Git

Your AWS identity needs permissions to manage the services used by the selected layers. The default install creates or updates IAM, KMS, S3, DynamoDB, EventBridge, SQS, CloudWatch Logs and Alarms, SNS, Lambda, Secrets Manager, EKS Kubernetes resources, Helm releases, DefectDojo resources, ArgoCD resources, and AWSCC-backed DevOps Agent resources.

Your Kubernetes identity needs enough RBAC to create namespaces, service accounts, Helm releases, Kubernetes CronJobs, and ArgoCD custom resources in the existing EKS cluster.

## 2. Clone and Enter the Environment

```bash
git clone https://github.com/derrickSh43/AWS_AgentCore_Security_Agent_Sec_platform.git
cd AWS_AgentCore_Security_Agent_Sec_platform/infra/environments/prod/security-operations-platform
```

Confirm Terraform and AWS are available:

```bash
terraform version
aws sts get-caller-identity
```

Update local kubeconfig for the existing cluster:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name acme-prod-eks
```

Replace the region and cluster name with your real values.

## 3. Create Remote Terraform State

For anything shared, use remote state before the first apply. Create one S3 bucket and one DynamoDB lock table.

Example:

```bash
aws s3api create-bucket \
  --bucket acme-prod-eks-secops-tfstate \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket acme-prod-eks-secops-tfstate \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket acme-prod-eks-secops-tfstate \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws dynamodb create-table \
  --table-name acme-prod-eks-secops-tflock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

Edit `backend.s3.example.hcl`:

```hcl
bucket         = "acme-prod-eks-secops-tfstate"
key            = "eks/security-operations-platform/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "acme-prod-eks-secops-tflock"
encrypt        = true
```

Initialize with the backend:

```bash
terraform init -backend-config=backend.s3.example.hcl
```

For a local-only dry run, use:

```bash
terraform init -backend=false
```

## 4. Create `terraform.tfvars`

Copy the example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Set the required base values:

```hcl
organization_name = "acme"
environment_name  = "prod"
platform_name     = "eks-secops"
aws_region        = "us-east-1"

configuration_repository_name = "AWS_AgentCore_Security_Agent_Sec_platform"

existing_eks_cluster_name      = "acme-prod-eks"
existing_eks_oidc_provider_arn = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
existing_eks_oidc_provider_url = "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
```

Find the EKS OIDC values:

```bash
aws eks describe-cluster \
  --region us-east-1 \
  --name acme-prod-eks \
  --query 'cluster.identity.oidc.issuer' \
  --output text

aws iam list-open-id-connect-providers
```

The Terraform variable `existing_eks_oidc_provider_url` must not include `https://`.

## 5. Choose the Layers to Install

The default install enables the deployable operating stack:

```hcl
enable_falco_runtime_detection         = true
enable_prowler_posture_scanning        = true
enable_engineer_security_dashboard     = true
enable_devops_agent_operations_context = true
enable_argocd_gitops_boundary          = true
```

ArgoCD requires a Git source:

```hcl
argocd_git_repository_url    = "https://github.com/acme/application-manifests.git"
argocd_git_revision          = "main"
argocd_application_path      = "clusters/prod"
argocd_enable_automated_sync = false
```

Keep automated sync disabled unless protected-branch approval and merge are your production deployment approval.

Optional layers should stay disabled until their inputs are ready:

```hcl
enable_snyk_pull_request_scanning = false
enable_agentcore_reasoning_layer  = false
enable_security_agent_pentesting  = false
```

For alarm emails, set:

```hcl
alarm_notification_email = "security-team@example.com"
```

AWS sends a confirmation email after apply. The subscription is not active until confirmed.

## 6. Optional: Enable Snyk Pull Request Scanning

Enable this only after you have a GitHub token, webhook secret, and Snyk token.

```hcl
enable_snyk_pull_request_scanning = true

github_owner                = "acme"
github_repository_full_name = "acme/application-manifests"
github_repository_name      = "application-manifests"
github_default_branch       = "main"
```

Put secrets in environment variables instead of committing them:

```bash
export TF_VAR_github_token="<github-token>"
export TF_VAR_github_webhook_secret="<random-webhook-secret>"
export TF_VAR_snyk_token="<snyk-token>"
```

Terraform stores the webhook secret in Secrets Manager and stores the Snyk token as a GitHub Actions secret.

## 7. Optional: Enable DefectDojo Automatic Imports

DefectDojo is installed by default for engineer review. Automatic imports from normalizer Lambdas are optional.

After DefectDojo is running and you create an API token, set:

```hcl
defectdojo_api_url       = "https://defectdojo.example.com"
defectdojo_engagement_id = "1"
defectdojo_lead_id       = "1"
```

Set the token as an environment variable:

```bash
export TF_VAR_defectdojo_api_token="<defectdojo-token>"
```

Terraform stores the token in Secrets Manager and passes only the secret ARN to Lambda environment variables.

## 8. Optional: Build and Enable AgentCore

AgentCore requires a pushed reasoner container image before enabling the layer.

From the repository root:

```bash
AWS_REGION=us-east-1 \
REPOSITORY_NAME=acme-prod-eks-secops-agentcore-reasoner \
IMAGE_TAG=20260525 \
./scripts/build-agentcore-reasoner-image.sh
```

The script prints the image URI. Add it to `terraform.tfvars`:

```hcl
enable_agentcore_reasoning_layer = true
agentcore_reasoner_container_uri = "111122223333.dkr.ecr.us-east-1.amazonaws.com/acme-prod-eks-secops-agentcore-reasoner:20260525"
```

AgentCore also requires:

```hcl
enable_engineer_security_dashboard = true
```

## 9. Optional: Enable AWS Security Agent Pentesting

Enable this only for domains you are authorized to test:

```hcl
enable_security_agent_pentesting = true

security_agent_verified_target_domains = [
  "app.example.com"
]
```

Do not add domains unless they are approved targets for your organization.

## 10. Validate and Plan

Run formatting and validation:

```bash
terraform fmt -check -recursive ../../../
terraform validate
```

Create a plan:

```bash
terraform plan -out=tfplan
```

Review the plan before applying. Pay special attention to IAM roles and policies, Kubernetes namespaces, Helm releases, GitHub branch protection, and any optional agent layers.

## 11. Apply

Apply the reviewed plan:

```bash
terraform apply tfplan
```

Save the outputs:

```bash
terraform output
```

## 12. Verify the Install

Check the AWS-side resources:

```bash
aws dynamodb list-tables --region us-east-1
aws events list-event-buses --region us-east-1
aws sqs list-queues --region us-east-1
aws lambda list-functions --region us-east-1
```

Check in-cluster components:

```bash
kubectl get ns falco prowler defectdojo argocd
helm list -A
kubectl -n prowler get cronjob
kubectl -n falco get pods
kubectl -n defectdojo get pods
kubectl -n argocd get pods
```

Port-forward DefectDojo for local access:

```bash
terraform output defectdojo_port_forward_command
```

Run the printed `kubectl port-forward` command, then open:

```text
http://localhost:8080
```

Get the generated admin password:

```bash
terraform output defectdojo_admin_password
```

## 13. CI Setup

The repository includes `.github/workflows/terraform-plan.yml`.

By default it runs:

- `terraform fmt -check`
- `terraform init -backend=false`
- `terraform validate`

To enable pull request plans, configure GitHub repository variables:

```text
AWS_ROLE_TO_ASSUME = arn:aws:iam::<account-id>:role/<github-actions-terraform-role>
AWS_REGION         = us-east-1
```

The AWS role should trust GitHub OIDC and have read/plan permissions for the platform resources. Keep apply as a separate reviewed human action unless your team has a stronger automation gate.

## 14. Updating the Platform

Use this sequence for changes:

```bash
git pull
cd infra/environments/prod/security-operations-platform
terraform init -backend-config=backend.s3.example.hcl
terraform fmt -check -recursive ../../../
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

For AgentCore image changes, build a new immutable tag and update `agentcore_reasoner_container_uri`. Do not use `latest`.

## 15. Uninstall

Review the destroy plan first:

```bash
terraform plan -destroy -out=destroy.tfplan
```

Destroy only when you are sure the platform state and findings can be removed:

```bash
terraform apply destroy.tfplan
```

Some resources may require manual cleanup if Kubernetes finalizers, GitHub branch protection, or retained S3 objects block deletion.

## Troubleshooting

If Terraform cannot connect to Kubernetes, refresh kubeconfig:

```bash
aws eks update-kubeconfig --region us-east-1 --name acme-prod-eks
kubectl cluster-info
```

If Helm releases fail, check the namespace events:

```bash
kubectl get events -A --sort-by=.lastTimestamp
```

If Snyk webhooks return `401`, confirm GitHub is using the same webhook secret stored in Terraform.

If Lambda code changes do not appear live, confirm `source_code_hash` changed in the plan and that Terraform is using the generated archive from `.terraform/security-operations-lambda-handlers.zip`.

If alarms do not send email, confirm the SNS subscription email was accepted.
