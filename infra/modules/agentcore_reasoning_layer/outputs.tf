output "agentcore_gateway_id" {
  value = aws_bedrockagentcore_gateway.security_tools_gateway.gateway_id
}

output "agentcore_gateway_url" {
  value = aws_bedrockagentcore_gateway.security_tools_gateway.gateway_url
}

output "agentcore_reasoner_runtime_arn" {
  value = aws_bedrockagentcore_agent_runtime.security_reasoner_runtime.agent_runtime_arn
}

output "agentcore_reasoner_endpoint_arn" {
  value = aws_bedrockagentcore_agent_runtime_endpoint.security_reasoner_endpoint.agent_runtime_endpoint_arn
}

output "agentcore_invoker_function_name" {
  value = aws_lambda_function.invoke_agentcore_reasoner.function_name
}
