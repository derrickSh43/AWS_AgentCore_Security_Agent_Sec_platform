module "prod_normalized_findings_pipeline" {
  source = "../../../modules/normalized_findings_pipeline"

  organization_name = var.organization_name
  environment_name  = var.environment_name
  platform_name     = var.platform_name
  aws_region        = var.aws_region
}
