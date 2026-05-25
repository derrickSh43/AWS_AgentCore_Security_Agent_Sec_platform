variable "organization_name" {
  type = string
}

variable "environment_name" {
  type = string
}

variable "platform_name" {
  type = string
}

variable "defectdojo_namespace" {
  type    = string
  default = "defectdojo"
}

variable "defectdojo_chart_version" {
  type    = string
  default = "1.9.28"
}

variable "defectdojo_host" {
  type    = string
  default = "defectdojo.local"
}

variable "defectdojo_service_type" {
  type    = string
  default = "ClusterIP"
}
