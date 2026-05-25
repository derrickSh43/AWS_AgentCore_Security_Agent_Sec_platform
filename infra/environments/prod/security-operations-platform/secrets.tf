resource "aws_secretsmanager_secret" "defectdojo_api_token" {
  name        = "${var.organization_name}-${var.environment_name}-${var.platform_name}-defectdojo-api-token"
  description = "Optional DefectDojo API token for security findings imports."
  kms_key_id  = module.prod_normalized_findings_pipeline.security_findings_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "defectdojo_api_token" {
  secret_id     = aws_secretsmanager_secret.defectdojo_api_token.id
  secret_string = var.defectdojo_api_token != "" ? var.defectdojo_api_token : "__UNCONFIGURED__"
}
