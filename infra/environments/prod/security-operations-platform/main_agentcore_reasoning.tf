module "prod_agentcore_reasoning_layer" {
  source = "../../../modules/agentcore_reasoning_layer"
  count  = var.enable_agentcore_reasoning_layer ? 1 : 0

  organization_name = var.organization_name
  environment_name  = var.environment_name
  platform_name     = var.platform_name
  aws_region        = var.aws_region

  agentcore_reasoner_container_uri        = var.agentcore_reasoner_container_uri
  findings_event_bus_name                 = module.prod_normalized_findings_pipeline.security_findings_bus_name
  findings_event_bus_arn                  = module.prod_normalized_findings_pipeline.security_findings_bus_arn
  normalized_findings_table_name          = module.prod_normalized_findings_pipeline.normalized_findings_table_name
  normalized_findings_table_arn           = module.prod_normalized_findings_pipeline.normalized_findings_table_arn
  correlation_state_table_name            = module.prod_normalized_findings_pipeline.finding_correlation_state_table_name
  correlation_state_table_arn             = module.prod_normalized_findings_pipeline.finding_correlation_state_table_arn
  dashboard_api_endpoint                  = try(module.prod_defectdojo_security_dashboard[0].defectdojo_local_url, null)
  findings_kms_key_arn                    = module.prod_normalized_findings_pipeline.security_findings_kms_key_arn
  lambda_package_path_tools               = coalesce(var.lambda_package_path_agentcore_tools, data.archive_file.security_operations_lambda_handlers.output_path)
  lambda_package_tools_source_code_hash   = data.archive_file.security_operations_lambda_handlers.output_base64sha256
  lambda_package_path_invoker             = coalesce(var.lambda_package_path_agentcore_invoker, data.archive_file.security_operations_lambda_handlers.output_path)
  lambda_package_invoker_source_code_hash = data.archive_file.security_operations_lambda_handlers.output_base64sha256
}
