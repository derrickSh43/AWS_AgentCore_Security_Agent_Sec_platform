output "devops_agent_space_id" {
  value = awscc_devopsagent_agent_space.eks_operations_agent_space.agent_space_id
}

output "devops_agent_monitor_role_arn" {
  value = aws_iam_role.devops_agent_monitor_role.arn
}

output "devops_agent_operator_role_arn" {
  value = aws_iam_role.devops_agent_operator_role.arn
}

output "devops_agent_ingestor_function_name" {
  value = aws_lambda_function.ingest_devops_agent_insights.function_name
}
