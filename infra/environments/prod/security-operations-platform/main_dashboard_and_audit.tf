module "prod_defectdojo_security_dashboard" {
  source = "../../../modules/defectdojo_security_dashboard"
  count  = var.enable_engineer_security_dashboard ? 1 : 0

  organization_name = var.organization_name
  environment_name  = var.environment_name
  platform_name     = var.platform_name
}
