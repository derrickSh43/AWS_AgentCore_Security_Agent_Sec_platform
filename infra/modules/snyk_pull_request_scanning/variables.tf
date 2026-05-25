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

variable "github_repository_full_name" {
  type = string
}

variable "github_repository_name" {
  type = string
}

variable "github_default_branch" {
  type = string
}

variable "github_webhook_secret" {
  type      = string
  sensitive = true
}

variable "snyk_token" {
  type      = string
  sensitive = true
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

variable "raw_findings_archive_bucket" {
  type = string
}

variable "findings_kms_key_arn" {
  type = string
}

variable "lambda_package_path" {
  type = string
}

variable "lambda_package_source_code_hash" {
  type    = string
  default = null
}

variable "required_status_check_contexts" {
  type = list(string)
  default = [
    "Snyk Infrastructure as Code",
    "terraform validate",
    "terraform plan"
  ]
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

variable "webhook_throttling_burst_limit" {
  type    = number
  default = 20
}

variable "webhook_throttling_rate_limit" {
  type    = number
  default = 10
}

variable "webhook_waf_rate_limit" {
  type        = number
  description = "Maximum Snyk webhook requests per source IP over the WAF five-minute rate window."
  default     = 1000
}
