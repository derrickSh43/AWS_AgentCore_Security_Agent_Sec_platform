output "falco_namespace" {
  value = kubernetes_namespace_v1.falco.metadata[0].name
}

output "falco_log_group_name" {
  value = aws_cloudwatch_log_group.falco_runtime_alerts.name
}

output "falco_normalizer_function_name" {
  value = aws_lambda_function.falco_finding_normalizer.function_name
}

output "falco_irsa_role_arn" {
  value = aws_iam_role.falco_cloudwatch_writer_role.arn
}
