# Terraform Tfvars Lookup Commands

Use this file to replace placeholder values in `terraform.tfvars.example`.

## Core Values

These are naming choices, not values AWS can discover:

```hcl
organization_name = "acme"
environment_name  = "prod"
platform_name     = "eks-secops"
```

Get the active AWS region:

```bash
aws configure get region
```

Get the Terraform repository name:

```bash
gh repo view --json name --jq '.name'
```

## Existing EKS Cluster

List EKS clusters:

```bash
aws eks list-clusters --region us-east-1 --query 'clusters[]' --output table
```

Get the OIDC provider URL without `https://`:

```bash
aws eks describe-cluster \
  --name <cluster-name> \
  --region us-east-1 \
  --query 'cluster.identity.oidc.issuer' \
  --output text | sed 's#^https://##'
```

Get the OIDC provider ARN:

```bash
aws iam list-open-id-connect-providers \
  --query 'OpenIDConnectProviderList[].Arn' \
  --output text | tr '\t' '\n' | grep "$(aws eks describe-cluster --name <cluster-name> --region us-east-1 --query 'cluster.identity.oidc.issuer' --output text | sed 's#^https://##')"
```

## Prowler Pod Networking

Prowler now runs as a Kubernetes CronJob pod in its own namespace with IRSA. It does not need `security_task_security_group_ids`.

Confirm the CronJob after apply:

```bash
kubectl get cronjob,pods -n prowler
```

Run the scan immediately instead of waiting for the schedule:

```bash
kubectl create job -n prowler --from=cronjob/<prowler-cronjob-name> prowler-manual-$(date +%s)
```

## GitHub And Snyk

Get GitHub repository values:

```bash
gh repo view \
  --json owner,name,nameWithOwner,defaultBranchRef,url \
  --jq '{github_owner: .owner.login, github_repository_name: .name, github_repository_full_name: .nameWithOwner, github_default_branch: .defaultBranchRef.name, url: .url}'
```

Check GitHub authentication:

```bash
gh auth status
```

Generate a webhook secret:

```bash
aws secretsmanager get-random-password \
  --password-length 48 \
  --exclude-punctuation \
  --query RandomPassword \
  --output text
```

Check Snyk authentication:

```bash
snyk config get api
```

Do not put real tokens into committed files. Use environment variables:

```bash
export TF_VAR_github_token="<github-token>"
export TF_VAR_github_webhook_secret="<generated-secret>"
export TF_VAR_snyk_token="<snyk-token>"
```

## AgentCore Container

This value cannot exist until the AgentCore reasoner container has been built and pushed.

List ECR repositories:

```bash
aws ecr describe-repositories \
  --region us-east-1 \
  --query 'repositories[].{Name:repositoryName,Uri:repositoryUri}' \
  --output table
```

Get the current image detail from the selected repository:

```bash
aws ecr describe-images \
  --region us-east-1 \
  --repository-name <reasoner-repository-name> \
  --query 'sort_by(imageDetails,& imagePushedAt)[-1].{Digest:imageDigest,Tags:imageTags,PushedAt:imagePushedAt}' \
  --output json
```

## Lambda Package Paths

Terraform packages the included Lambda handlers automatically. These variables are optional overrides only:

```hcl
lambda_package_path_falco_normalizer            = null
lambda_package_path_prowler_normalizer          = null
lambda_package_path_snyk_normalizer             = null
lambda_package_path_agentcore_tools             = null
lambda_package_path_agentcore_invoker           = null
lambda_package_path_security_agent_orchestrator = null
lambda_package_path_devops_agent_ingestor       = null
```

## Dashboard Domain

The current plug-and-play dashboard is DefectDojo OSS inside the cluster. Use port-forward by default:

```bash
terraform output defectdojo_port_forward_command
```

The `dashboard_domain_name` and `dashboard_certificate_arn` values are reserved for a later ingress/custom-domain pass.

Automatic imports into DefectDojo are optional. After creating a DefectDojo API token and engagement, set:

```bash
export TF_VAR_defectdojo_api_url="https://<reachable-defectdojo-url>"
export TF_VAR_defectdojo_api_token="<defectdojo-token>"
export TF_VAR_defectdojo_engagement_id="<engagement-id>"
```

If these are empty, findings still go to S3, DynamoDB, and EventBridge, and engineers can use DefectDojo manually.

List ACM certificates for CloudFront:

```bash
aws acm list-certificates \
  --region us-east-1 \
  --query 'CertificateSummaryList[].{DomainName:DomainName,CertificateArn:CertificateArn,Status:Status}' \
  --output table
```

List Route 53 hosted zones:

```bash
aws route53 list-hosted-zones-by-name \
  --query 'HostedZones[].{Name:Name,Id:Id,PrivateZone:Config.PrivateZone}' \
  --output table
```

## Security Agent Target Domains

List public Route 53 app records:

```bash
aws route53 list-hosted-zones-by-name \
  --query 'HostedZones[].{Name:Name,Id:Id,PrivateZone:Config.PrivateZone}' \
  --output table
```

List load balancer DNS names:

```bash
aws elbv2 describe-load-balancers \
  --region us-east-1 \
  --query 'LoadBalancers[].{Name:LoadBalancerName,DNSName:DNSName,Scheme:Scheme,Type:Type,State:State.Code}' \
  --output table
```

Only use domains your organization owns and has approved for testing.

## ArgoCD GitOps Values

Get the repository URL:

```bash
gh repo view --json url --jq '.url'
```

Get the default branch:

```bash
gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'
```

Find manifest paths in a local repo checkout:

```bash
find . -maxdepth 3 -type f \( -name 'kustomization.yaml' -o -name 'Chart.yaml' -o -name '*.yaml' \) \
  | sed 's#/[^/]*$##' \
  | sort -u
```

Use this for strict production gating:

```hcl
argocd_enable_automated_sync = false
```
