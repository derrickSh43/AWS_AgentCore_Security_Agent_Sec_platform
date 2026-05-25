# Production Security Operations Platform

This environment wires an existing EKS cluster into a security and operations pipeline.

The default configuration now deploys the deployable operating stack: shared findings storage, Falco, Prowler, DefectDojo, AWS DevOps Agent integration, and ArgoCD. Terraform packages the included Lambda handlers locally, so Falco, Prowler, Snyk, Security Agent ingestion, and DevOps Agent ingestion do not require separate zip artifacts.

It intentionally uses explicit module calls:

```text
prod_normalized_findings_pipeline
prod_falco_runtime_detection
prod_prowler_posture_scanning
prod_snyk_pull_request_scanning
prod_defectdojo_security_dashboard
prod_agentcore_reasoning_layer
prod_security_agent_pentesting
prod_devops_agent_operations_context
prod_argocd_gitops_boundary
```

There is no generic scanner module and no scanner map.

## Runtime Flow

This is the intended full flow after all optional layers are enabled:

```text
Falco -> CloudWatch Logs -> Falco Lambda normalizer
Prowler -> S3 raw output -> Prowler Lambda normalizer
Snyk -> GitHub checks/webhook -> Snyk Lambda normalizer
Security Agent -> weekly pentest -> Security Agent findings ingestor
DevOps Agent -> ops context -> DevOps Agent insights ingestor

Normalizers -> EventBridge security findings bus
Normalizers -> DynamoDB normalized findings table
AgentCore Gateway -> Lambda MCP tools
AgentCore Runtime -> daily digest and critical-event reasoning
DefectDojo -> engineer review, triage, deduplication, and resolution workflow
Security Agent / AgentCore -> pull requests only
ArgoCD -> cluster apply from reviewed Git state
```

## Default Apply Scope

With the default flags, Terraform deploys:

```text
S3 raw findings archive
DynamoDB normalized findings table
DynamoDB correlation state table
EventBridge security findings bus
EventBridge archive
SQS dead-letter queue
CloudWatch findings pipeline log group
KMS key and alias
Falco Helm release and normalizer Lambda
Prowler Kubernetes CronJob pod and normalizer Lambda
DefectDojo OSS Helm release
AWS DevOps Agent space, association, and ingestor Lambda
ArgoCD Helm release and GitOps Application
```

This default touches the existing EKS cluster because Falco, Prowler, DefectDojo, and ArgoCD are in-cluster tools.

## Optional Layers

These layers remain gated until their required inputs exist:

```hcl
enable_snyk_pull_request_scanning      = true
enable_agentcore_reasoning_layer       = true
enable_security_agent_pentesting       = true
```

## Human Approval Boundary

The default ArgoCD setting is:

```hcl
argocd_enable_automated_sync = false
```

That means a merged PR updates desired state, but an engineer still manually syncs in ArgoCD before production changes apply.

Set it to `true` only if your governance model treats protected-branch approval and merge as the human deployment approval.

## AgentCore Container Boundary

The Lambda handlers are included in this repository and packaged by Terraform with the `archive` provider.

The remaining artifact that Terraform cannot honestly invent is the AgentCore Runtime container image:

```text
agentcore_reasoner_container_uri
```

Do not enable `enable_agentcore_reasoning_layer` until that image has been built and pushed to ECR.

A minimal reasoner container is included at [agentcore_reasoner_container](agentcore_reasoner_container). Build and push it with:

```bash
AWS_REGION=us-east-1 REPOSITORY_NAME=acme-prod-eks-secops-agentcore-reasoner ../../../../scripts/build-agentcore-reasoner-image.sh
```

Use the printed image URI for:

```hcl
agentcore_reasoner_container_uri = "<printed-image-uri>"
```

## Looking Up `terraform.tfvars` Values

Use [TFVARS_LOOKUP_COMMANDS.md](TFVARS_LOOKUP_COMMANDS.md) for CLI commands that discover or confirm the real values that replace placeholders in `terraform.tfvars.example`.

## Remote State

Local state is not appropriate for a shared production workflow. Create an S3 state bucket and DynamoDB lock table, then initialize with:

```bash
terraform init -backend-config=backend.s3.example.hcl
```

Replace the placeholder values in [backend.s3.example.hcl](backend.s3.example.hcl) first.

## Provider Notes

The DynamoDB global secondary indexes use `key_schema` blocks to avoid the AWS provider deprecation warnings for GSI `hash_key` and `range_key`.
