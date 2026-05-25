module "prod_snyk_pull_request_scanning" {
  source = "../../../modules/snyk_pull_request_scanning"
  count  = var.enable_snyk_pull_request_scanning ? 1 : 0

  organization_name = var.organization_name
  environment_name  = var.environment_name
  platform_name     = var.platform_name
  aws_region        = var.aws_region

  github_repository_full_name     = var.github_repository_full_name
  github_repository_name          = var.github_repository_name
  github_default_branch           = var.github_default_branch
  github_webhook_secret           = var.github_webhook_secret
  snyk_token                      = var.snyk_token
  findings_event_bus_name         = module.prod_normalized_findings_pipeline.security_findings_bus_name
  findings_event_bus_arn          = module.prod_normalized_findings_pipeline.security_findings_bus_arn
  normalized_findings_table_name  = module.prod_normalized_findings_pipeline.normalized_findings_table_name
  normalized_findings_table_arn   = module.prod_normalized_findings_pipeline.normalized_findings_table_arn
  raw_findings_archive_bucket     = module.prod_normalized_findings_pipeline.raw_findings_archive_bucket_name
  findings_kms_key_arn            = module.prod_normalized_findings_pipeline.security_findings_kms_key_arn
  lambda_package_path             = coalesce(var.lambda_package_path_snyk_normalizer, data.archive_file.security_operations_lambda_handlers.output_path)
  lambda_package_source_code_hash = data.archive_file.security_operations_lambda_handlers.output_base64sha256
  defectdojo_api_url              = var.defectdojo_api_url
  defectdojo_api_token_secret_arn = aws_secretsmanager_secret.defectdojo_api_token.arn
  defectdojo_engagement_id        = var.defectdojo_engagement_id
  defectdojo_lead_id              = var.defectdojo_lead_id
}
