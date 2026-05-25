module "prod_argocd_gitops_boundary" {
  source = "../../../modules/argocd_gitops_boundary"
  count  = var.enable_argocd_gitops_boundary ? 1 : 0

  organization_name = var.organization_name
  environment_name  = var.environment_name
  platform_name     = var.platform_name

  eks_cluster_name             = data.aws_eks_cluster.target_cluster.name
  argocd_git_repository_url    = var.argocd_git_repository_url
  argocd_git_revision          = var.argocd_git_revision
  argocd_application_path      = var.argocd_application_path
  argocd_enable_automated_sync = var.argocd_enable_automated_sync
}
