variable "organization_name" {
  type = string
}

variable "environment_name" {
  type = string
}

variable "platform_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "aws_account_id" {
  type = string
}

variable "findings_event_bus_name" {
  type = string
}

variable "findings_event_bus_arn" {
  type = string
}

variable "normalized_findings_table_name" {
  type = string
}

variable "normalized_findings_table_arn" {
  type = string
}

variable "lambda_package_path" {
  type = string
}

variable "lambda_package_source_code_hash" {
  type    = string
  default = null
}

variable "findings_kms_key_arn" {
  type = string
}

variable "defectdojo_api_url" {
  type    = string
  default = ""
}

variable "defectdojo_api_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "defectdojo_api_token_secret_arn" {
  type    = string
  default = null
}

variable "defectdojo_engagement_id" {
  type    = string
  default = ""
}

variable "defectdojo_lead_id" {
  type    = string
  default = ""
}
