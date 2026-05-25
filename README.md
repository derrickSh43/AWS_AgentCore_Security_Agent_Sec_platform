# EKS Security Operations Platform

Standalone Terraform project for deploying a layered security and operations platform around an existing EKS cluster.

Start with [infra/README.md](infra/README.md) for the architecture and module layout, then use [infra/environments/prod/security-operations-platform/README.md](infra/environments/prod/security-operations-platform/README.md) for environment-specific setup.

## Local Setup

```bash
cd infra/environments/prod/security-operations-platform
terraform init
terraform validate
terraform plan
```

Keep real values in environment variables, a local `terraform.tfvars`, or backend-specific secret handling. Do not commit local state, `.terraform`, generated zip packages, Python caches, or real token values.
