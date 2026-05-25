variable "organization_name" {
  type = string
}

variable "environment_name" {
  type = string
}

variable "platform_name" {
  type = string
}

variable "eks_cluster_name" {
  type = string
}

variable "argocd_git_repository_url" {
  type = string
}

variable "argocd_git_revision" {
  type = string
}

variable "argocd_application_path" {
  type = string
}

variable "argocd_enable_automated_sync" {
  type = bool
}

variable "argocd_namespace" {
  type    = string
  default = "argocd"
}

variable "argocd_chart_version" {
  type    = string
  default = "9.5.15"
}
