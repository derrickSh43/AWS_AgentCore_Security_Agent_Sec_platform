variable "organization_name" {
  description = "Short organization name used in resource names."
  type        = string
}

variable "environment_name" {
  description = "Environment name used in resource names."
  type        = string
  default     = "prod"
}

variable "platform_name" {
  description = "Platform name used in resource names."
  type        = string
  default     = "eks-secops"
}

variable "aws_region" {
  description = "AWS Region for the security operations platform."
  type        = string
}

variable "configuration_repository_name" {
  description = "Name of the repository that owns this Terraform configuration."
  type        = string
}

variable "enable_falco_runtime_detection" {
  description = "Enable Falco Helm install and Falco normalizer Lambda."
  type        = bool
  default     = true
}

variable "enable_prowler_posture_scanning" {
  description = "Enable scheduled Prowler Kubernetes CronJob pod and Prowler normalizer Lambda."
  type        = bool
  default     = true
}

variable "enable_snyk_pull_request_scanning" {
  description = "Enable GitHub/Snyk PR integration and Snyk normalizer Lambda. Requires GitHub and Snyk secrets."
  type        = bool
  default     = false
}

variable "enable_engineer_security_dashboard" {
  description = "Enable DefectDojo OSS in the existing EKS cluster as the engineer review dashboard."
  type        = bool
  default     = true
}

variable "enable_agentcore_reasoning_layer" {
  description = "Enable AgentCore Runtime/Gateway and MCP tool Lambdas. Requires AgentCore container image and Lambda packages."
  type        = bool
  default     = false
}

variable "enable_security_agent_pentesting" {
  description = "Enable AWS Security Agent orchestration Lambdas and weekly pentest schedule."
  type        = bool
  default     = false
}

variable "enable_devops_agent_operations_context" {
  description = "Enable AWS DevOps Agent association and insights ingestion Lambda."
  type        = bool
  default     = true
}

variable "enable_argocd_gitops_boundary" {
  description = "Enable ArgoCD Helm install and ArgoCD Application bootstrap. This touches the existing EKS cluster."
  type        = bool
  default     = true
}

variable "existing_eks_cluster_name" {
  description = "Name of the existing EKS cluster. Terraform only reads it."
  type        = string
}

variable "existing_eks_oidc_provider_arn" {
  description = "IAM OIDC provider ARN for the existing EKS cluster."
  type        = string
}

variable "existing_eks_oidc_provider_url" {
  description = "OIDC issuer URL for the existing EKS cluster, without the https:// prefix."
  type        = string
}

variable "private_subnet_ids_for_security_tasks" {
  description = "Deprecated. Prowler now runs in-cluster as a Kubernetes CronJob and does not use ECS subnet inputs."
  type        = list(string)
  default     = []
}

variable "security_task_security_group_ids" {
  description = "Deprecated. Prowler now runs in-cluster as a Kubernetes CronJob and does not use ECS security group inputs."
  type        = list(string)
  default     = []
}

variable "github_owner" {
  description = "GitHub organization or user that owns the manifest/application repository."
  type        = string
  default     = null
}

variable "github_token" {
  description = "GitHub token used by the Terraform GitHub provider."
  type        = string
  sensitive   = true
  default     = null
}

variable "github_repository_full_name" {
  description = "GitHub repository full name, for example acme/application-manifests."
  type        = string
  default     = null
}

variable "github_repository_name" {
  description = "GitHub repository short name."
  type        = string
  default     = null
}

variable "github_default_branch" {
  description = "Protected branch that ArgoCD follows."
  type        = string
  default     = "main"
}

variable "github_webhook_secret" {
  description = "Shared secret for GitHub webhooks into the Snyk normalizer API."
  type        = string
  sensitive   = true
  default     = null
}

variable "snyk_token" {
  description = "Snyk API token stored as a GitHub Actions secret."
  type        = string
  sensitive   = true
  default     = null
}

variable "agentcore_reasoner_container_uri" {
  description = "ECR image URI for the AgentCore Runtime reasoning agent."
  type        = string
  default     = null
}

variable "dashboard_domain_name" {
  description = "Optional custom domain name for the security dashboard."
  type        = string
  default     = null
}

variable "dashboard_certificate_arn" {
  description = "Optional ACM certificate ARN for the dashboard custom domain."
  type        = string
  default     = null
}

variable "defectdojo_api_url" {
  description = "Optional reachable DefectDojo URL for automatic finding imports. Leave empty for manual DefectDojo review/import."
  type        = string
  default     = ""
}

variable "defectdojo_api_token" {
  description = "Optional DefectDojo API token used by normalizer Lambdas for automatic imports."
  type        = string
  sensitive   = true
  default     = ""
}

variable "defectdojo_engagement_id" {
  description = "Optional DefectDojo engagement ID used by normalizer Lambdas for automatic imports."
  type        = string
  default     = ""
}

variable "defectdojo_lead_id" {
  description = "Optional DefectDojo lead user ID used by normalizer Lambdas for automatic imports."
  type        = string
  default     = ""
}

variable "alarm_notification_email" {
  description = "Optional email address subscribed to security operations CloudWatch alarms."
  type        = string
  default     = null
}

variable "security_agent_verified_target_domains" {
  description = "Domains already verified for AWS Security Agent penetration testing."
  type        = list(string)
  default     = []
}

variable "argocd_git_repository_url" {
  description = "Git repository URL watched by ArgoCD for desired cluster state."
  type        = string
  default     = null
}

variable "argocd_git_revision" {
  description = "Git revision ArgoCD should track."
  type        = string
  default     = "main"
}

variable "argocd_application_path" {
  description = "Path in the Git repository containing application manifests."
  type        = string
  default     = null
}

variable "argocd_enable_automated_sync" {
  description = "When false, merge updates desired state but an engineer must manually sync in ArgoCD."
  type        = bool
  default     = false
}

variable "lambda_package_path_falco_normalizer" {
  description = "Zip package path for the Falco finding normalizer Lambda."
  type        = string
  default     = null
}

variable "lambda_package_path_prowler_normalizer" {
  description = "Zip package path for the Prowler finding normalizer Lambda."
  type        = string
  default     = null
}

variable "lambda_package_path_snyk_normalizer" {
  description = "Zip package path for the Snyk finding normalizer Lambda."
  type        = string
  default     = null
}

variable "lambda_package_path_agentcore_tools" {
  description = "Zip package path reused by AgentCore MCP tool Lambdas."
  type        = string
  default     = null
}

variable "lambda_package_path_agentcore_invoker" {
  description = "Zip package path for the Lambda that invokes the AgentCore Runtime."
  type        = string
  default     = null
}

variable "lambda_package_path_security_agent_orchestrator" {
  description = "Zip package path for AWS Security Agent pentest orchestration Lambdas."
  type        = string
  default     = null
}

variable "lambda_package_path_devops_agent_ingestor" {
  description = "Zip package path for the AWS DevOps Agent insights ingestion Lambda."
  type        = string
  default     = null
}
