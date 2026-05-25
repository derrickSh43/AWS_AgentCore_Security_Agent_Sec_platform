# EKS Security Operations Terraform

This tree is a scaffold for a layered security and operations pipeline around an existing EKS cluster.

See **[PLATFORM.md](PLATFORM.md)** for full architecture, data flow, future additions, and Wiz/Tenable comparison.

The Terraform is intentionally explicit. It does not use a generic scanner module, scanner maps, or `for_each` loops to hide major platform components. Each layer has its own module because Falco, Prowler, Snyk, AgentCore, AWS Security Agent, AWS DevOps Agent, the dashboard, and ArgoCD all have different trust boundaries and failure modes.

## Layout

```text
infra/
  environments/
    prod/
      security-operations-platform/
  modules/
    normalized_findings_pipeline/
    falco_runtime_detection/
    prowler_posture_scanning/
    snyk_pull_request_scanning/
    agentcore_reasoning_layer/
    security_agent_pentesting/
    devops_agent_operations_context/
    defectdojo_security_dashboard/
    argocd_gitops_boundary/
```

## Boundary

Terraform creates the supporting infrastructure and bootstraps cluster add-ons. It does not create the EKS cluster.

The runtime safety rule is:

```text
Scanners and agents can read, reason, alert, and open pull requests.
Only reviewed Git changes are eligible for cluster deployment.
ArgoCD is the only component that applies desired state to the cluster.
```

By default the ArgoCD module is configured for manual production sync. Change `argocd_enable_automated_sync` only if your team treats protected-branch merge approval as the deployment approval.

## Next Steps

1. Fill in `terraform.tfvars.example` values and rename it to `terraform.tfvars`.
2. Enable the layers you want in `terraform.tfvars`. Terraform packages the included Lambda handlers automatically.
3. Run `terraform init`, `terraform validate`, and `terraform plan`.
4. Build and push the AgentCore reasoner container before enabling the AgentCore Runtime layer.
5. Replace placeholder IAM scopes with organization-specific least privilege before applying in production.
