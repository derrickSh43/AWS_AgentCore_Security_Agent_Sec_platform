data "archive_file" "security_operations_lambda_handlers" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_src/security_operations_handlers"
  output_path = "${path.module}/.terraform/security-operations-lambda-handlers.zip"
  excludes = [
    "__pycache__",
    "*.pyc"
  ]
}
