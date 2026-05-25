# AWS AgentCore Security Operations Platform for EKS

Terraform for a layered security operations platform around an existing Amazon EKS cluster. The project connects runtime detection, posture scanning, code scanning, security findings normalization, DefectDojo review workflows, AgentCore reasoning, and an ArgoCD GitOps boundary.

This is not an EKS cluster provisioner. It assumes the cluster already exists and adds the security and operations plane around it.

![Platform architecture](Screenshot%202026-05-24%20173604.png)

Dashed green blocks in the diagram represent planned extensions. The current Terraform focuses on the deployable core platform and keeps optional higher-risk layers gated behind explicit variables.

## What This Deploys

Default enabled layers:

- Shared security findings pipeline: S3 raw archive, DynamoDB normalized findings table, DynamoDB correlation state, EventBridge bus, SQS DLQ, KMS key, and CloudWatch log group.
- Falco runtime detection: Helm install, CloudWatch log delivery, and Lambda normalization.
- Prowler posture scanning: in-cluster Kubernetes CronJob, KMS-encrypted raw findings bucket, and Lambda normalization.
- DefectDojo: OSS Helm release for engineer triage, deduplication, and resolution workflow.
- AWS DevOps Agent integration: operations context association and insights ingestor.
- ArgoCD GitOps boundary: ArgoCD install and an application that follows reviewed Git state.
- Observability: Lambda error, throttle, and duration alarms plus DLQ depth alarms.

Optional gated layers:

- Snyk pull request scanning and GitHub webhook ingestion.
- AgentCore Runtime, AgentCore Gateway, and MCP tool Lambdas.
- AWS Security Agent weekly penetration-test orchestration and finding ingestion.

## Safety Model

The platform is designed around a human approval boundary:

```text
Scanners and agents can read, reason, alert, and open pull requests.
Only reviewed Git changes are eligible for cluster deployment.
ArgoCD is the only component that applies desired state to the cluster.
```

By default, ArgoCD automated sync is disabled. A merged pull request updates desired state, but an engineer still manually syncs production.

Security hardening included in this version:

- Snyk webhook HMAC signature validation.
- Secrets Manager-backed webhook and DefectDojo tokens.
- Project CMK encryption for Lambda environment variables and sensitive storage.
- Lambda `source_code_hash` for reliable redeploys.
- API Gateway throttling and WAF rate limiting for the Snyk webhook.
- Prowler finding deduplication across repeated runs.
- AgentCore invocation cooldown and reserved concurrency.
- Pinned Helm chart and container image versions.

## Repository Layout

```text
.
|-- .github/workflows/terraform-plan.yml
|-- infra/
|   |-- environments/prod/security-operations-platform/
|   |-- modules/
|   |   |-- normalized_findings_pipeline/
|   |   |-- falco_runtime_detection/
|   |   |-- prowler_posture_scanning/
|   |   |-- snyk_pull_request_scanning/
|   |   |-- agentcore_reasoning_layer/
|   |   |-- security_agent_pentesting/
|   |   |-- devops_agent_operations_context/
|   |   |-- defectdojo_security_dashboard/
|   |   `-- argocd_gitops_boundary/
`-- scripts/
    `-- build-agentcore-reasoner-image.sh
```

Start with:

- [infra/README.md](infra/README.md) for the architecture and module layout.
- [infra/PLATFORM.md](infra/PLATFORM.md) for the full platform design and roadmap.
- [prod environment README](infra/environments/prod/security-operations-platform/README.md) for deployment details.
- [TFVARS lookup commands](infra/environments/prod/security-operations-platform/TFVARS_LOOKUP_COMMANDS.md) for finding the values needed in `terraform.tfvars`.

## Quick Start

Create a local `terraform.tfvars` from the example and fill in values for your existing EKS cluster, GitHub repository, and optional integrations.

```bash
cd infra/environments/prod/security-operations-platform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform validate
terraform plan
```

For a shared environment, configure the S3 backend first:

```bash
terraform init -backend-config=backend.s3.example.hcl
```

Do not commit local state, `.terraform`, generated zip packages, Python caches, real token values, or real `terraform.tfvars` files.

## AgentCore Container

The Lambda handlers are packaged by Terraform. The AgentCore Runtime container must be built and pushed before enabling `enable_agentcore_reasoning_layer`.

```bash
AWS_REGION=us-east-1 \
REPOSITORY_NAME=acme-prod-eks-secops-agentcore-reasoner \
IMAGE_TAG=20260525 \
../../../../scripts/build-agentcore-reasoner-image.sh
```

Use the printed image URI for:

```hcl
agentcore_reasoner_container_uri = "<printed-image-uri>"
```

## CI

The GitHub Actions workflow runs Terraform format, init without backend, and validate on pull requests that touch infra files. It runs `terraform plan` when the repository has an `AWS_ROLE_TO_ASSUME` GitHub variable configured for OIDC.

## Current Status

This repo is ready for review and environment-specific planning. Before production apply, confirm remote state, least-privilege IAM scopes, notification routing, chart compatibility in a staging cluster, and the real AgentCore reasoner image URI.
