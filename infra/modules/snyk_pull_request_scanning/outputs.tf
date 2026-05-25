output "snyk_webhook_url" {
  value = "${aws_apigatewayv2_stage.snyk_webhook_stage.invoke_url}/snyk-findings"
}

output "snyk_normalizer_function_name" {
  value = aws_lambda_function.snyk_finding_normalizer.function_name
}

output "protected_branch" {
  value = github_branch_protection.production_branch_protection.pattern
}
