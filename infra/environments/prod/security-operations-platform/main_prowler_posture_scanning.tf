module "prod_prowler_posture_scanning" {
  source = "../../../modules/prowler_posture_scanning"
  count  = var.enable_prowler_posture_scanning ? 1 : 0

  organization_name = var.organization_name
  environment_name  = var.environment_name
  platform_name     = var.platform_name
  aws_region        = var.aws_region
  aws_account_id    = data.aws_caller_identity.current.account_id

  eks_oidc_provider_arn           = var.existing_eks_oidc_provider_arn
  eks_oidc_provider_url           = var.existing_eks_oidc_provider_url
  findings_event_bus_name         = module.prod_normalized_findings_pipeline.security_findings_bus_name
  findings_event_bus_arn          = module.prod_normalized_findings_pipeline.security_findings_bus_arn
  normalized_findings_table_name  = module.prod_normalized_findings_pipeline.normalized_findings_table_name
  normalized_findings_table_arn   = module.prod_normalized_findings_pipeline.normalized_findings_table_arn
  raw_findings_archive_bucket     = module.prod_normalized_findings_pipeline.raw_findings_archive_bucket_name
  s3_access_logs_bucket           = module.prod_normalized_findings_pipeline.security_findings_access_logs_bucket_name
  findings_kms_key_arn            = module.prod_normalized_findings_pipeline.security_findings_kms_key_arn
  lambda_package_path             = coalesce(var.lambda_package_path_prowler_normalizer, data.archive_file.security_operations_lambda_handlers.output_path)
  lambda_package_source_code_hash = data.archive_file.security_operations_lambda_handlers.output_base64sha256
  defectdojo_api_url              = var.defectdojo_api_url
  defectdojo_api_token_secret_arn = aws_secretsmanager_secret.defectdojo_api_token.arn
  defectdojo_engagement_id        = var.defectdojo_engagement_id
  defectdojo_lead_id              = var.defectdojo_lead_id
}
