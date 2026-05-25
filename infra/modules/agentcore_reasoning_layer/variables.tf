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

variable "agentcore_reasoner_container_uri" {
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

variable "correlation_state_table_name" {
  type = string
}

variable "correlation_state_table_arn" {
  type = string
}

variable "dashboard_api_endpoint" {
  type = string
}

variable "lambda_package_path_tools" {
  type = string
}

variable "lambda_package_tools_source_code_hash" {
  type    = string
  default = null
}

variable "lambda_package_path_invoker" {
  type = string
}

variable "lambda_package_invoker_source_code_hash" {
  type    = string
  default = null
}

variable "findings_kms_key_arn" {
  type = string
}

variable "daily_digest_schedule_expression" {
  type    = string
  default = "cron(0 13 * * ? *)"
}

variable "agentcore_invocation_cooldown_seconds" {
  type    = number
  default = 300
}

variable "agentcore_invoker_reserved_concurrency" {
  type    = number
  default = 1
}
