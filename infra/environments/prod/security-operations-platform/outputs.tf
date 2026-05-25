output "security_findings_event_bus_name" {
  value = module.prod_normalized_findings_pipeline.security_findings_bus_name
}

output "normalized_findings_table_name" {
  value = module.prod_normalized_findings_pipeline.normalized_findings_table_name
}

output "agentcore_gateway_url" {
  value = try(module.prod_agentcore_reasoning_layer[0].agentcore_gateway_url, null)
}

output "agentcore_reasoner_endpoint_arn" {
  value = try(module.prod_agentcore_reasoning_layer[0].agentcore_reasoner_endpoint_arn, null)
}

output "dashboard_api_endpoint" {
  value = try(module.prod_defectdojo_security_dashboard[0].defectdojo_local_url, null)
}

output "defectdojo_local_url" {
  value = try(module.prod_defectdojo_security_dashboard[0].defectdojo_local_url, null)
}

output "defectdojo_port_forward_command" {
  value = try(module.prod_defectdojo_security_dashboard[0].defectdojo_port_forward_command, null)
}

output "defectdojo_admin_username" {
  value = try(module.prod_defectdojo_security_dashboard[0].defectdojo_admin_username, null)
}

output "defectdojo_admin_password" {
  value     = try(module.prod_defectdojo_security_dashboard[0].defectdojo_admin_password, null)
  sensitive = true
}

output "argocd_namespace" {
  value = try(module.prod_argocd_gitops_boundary[0].argocd_namespace, null)
}

output "security_operations_alert_topic_arn" {
  value = aws_sns_topic.security_operations_alerts.arn
}
