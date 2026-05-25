data "github_repository" "manifest_repository" {
  full_name = var.github_repository_full_name
}

resource "github_actions_secret" "snyk_token" {
  repository      = var.github_repository_name
  secret_name     = "SNYK_TOKEN"
  plaintext_value = var.snyk_token
}

resource "aws_secretsmanager_secret" "github_webhook_secret" {
  name        = "${var.organization_name}-${var.environment_name}-${var.platform_name}-snyk-github-webhook"
  description = "GitHub webhook signing secret for the Snyk normalizer."
  kms_key_id  = var.findings_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "github_webhook_secret" {
  secret_id     = aws_secretsmanager_secret.github_webhook_secret.id
  secret_string = var.github_webhook_secret
}

resource "github_branch_protection" "production_branch_protection" {
  repository_id  = data.github_repository.manifest_repository.node_id
  pattern        = var.github_default_branch
  enforce_admins = true

  required_status_checks {
    strict   = true
    contexts = var.required_status_check_contexts
  }

  required_pull_request_reviews {
    dismiss_stale_reviews           = true
    require_code_owner_reviews      = true
    required_approving_review_count = 1
  }
}

data "aws_iam_policy_document" "snyk_normalizer_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "snyk_finding_normalizer_role" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-snyk-finding-normalizer"
  assume_role_policy = data.aws_iam_policy_document.snyk_normalizer_assume_role.json
}

data "aws_iam_policy_document" "snyk_finding_normalizer_policy_document" {
  statement {
    sid    = "WriteNormalizerLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.organization_name}-${var.environment_name}-${var.platform_name}-snyk-finding-normalizer:*"]
  }

  statement {
    sid    = "WriteNormalizedFinding"
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:GetItem"
    ]

    resources = [var.normalized_findings_table_arn]
  }

  statement {
    sid       = "PublishNormalizedFindingEvent"
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = [var.findings_event_bus_arn]
  }

  statement {
    sid    = "ArchiveRawSnykPayload"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:PutObjectTagging"
    ]

    resources = ["arn:aws:s3:::${var.raw_findings_archive_bucket}/snyk/*"]
  }

  statement {
    sid    = "ReadWebhookAndImportSecrets"
    effect = "Allow"

    actions = ["secretsmanager:GetSecretValue"]

    resources = compact([
      aws_secretsmanager_secret.github_webhook_secret.arn,
      var.defectdojo_api_token_secret_arn
    ])
  }

  statement {
    sid    = "UseFindingsKmsKey"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]

    resources = [var.findings_kms_key_arn]
  }

  statement {
    sid    = "WriteXRayTraceData"
    effect = "Allow"

    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "snyk_finding_normalizer_policy" {
  name   = "${var.organization_name}-${var.environment_name}-${var.platform_name}-snyk-finding-normalizer"
  policy = data.aws_iam_policy_document.snyk_finding_normalizer_policy_document.json
}

resource "aws_iam_role_policy_attachment" "snyk_finding_normalizer_policy_attachment" {
  role       = aws_iam_role.snyk_finding_normalizer_role.name
  policy_arn = aws_iam_policy.snyk_finding_normalizer_policy.arn
}

resource "aws_lambda_function" "snyk_finding_normalizer" {
  function_name    = "${var.organization_name}-${var.environment_name}-${var.platform_name}-snyk-finding-normalizer"
  role             = aws_iam_role.snyk_finding_normalizer_role.arn
  filename         = var.lambda_package_path
  source_code_hash = var.lambda_package_source_code_hash
  handler          = "snyk_normalizer.handler"
  runtime          = "python3.13"
  timeout          = 60
  memory_size      = 256
  kms_key_arn      = var.findings_kms_key_arn

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      FINDINGS_EVENT_BUS_NAME          = var.findings_event_bus_name
      NORMALIZED_FINDINGS_TABLE        = var.normalized_findings_table_name
      RAW_FINDINGS_ARCHIVE_BUCKET      = var.raw_findings_archive_bucket
      FINDING_SOURCE                   = "snyk"
      GITHUB_WEBHOOK_SECRET_SECRET_ARN = aws_secretsmanager_secret.github_webhook_secret.arn
      DEFECTDOJO_URL                   = var.defectdojo_api_url
      DEFECTDOJO_API_TOKEN_SECRET_ARN  = coalesce(var.defectdojo_api_token_secret_arn, "")
      DEFECTDOJO_ENGAGEMENT_ID         = var.defectdojo_engagement_id
      DEFECTDOJO_LEAD_ID               = var.defectdojo_lead_id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.snyk_finding_normalizer_policy_attachment
  ]
}

resource "aws_apigatewayv2_api" "snyk_webhook_api" {
  name          = "${var.organization_name}-${var.environment_name}-${var.platform_name}-snyk-webhook-api"
  protocol_type = "HTTP"
}

resource "aws_cloudwatch_log_group" "snyk_webhook_api_access_logs" {
  name              = "/aws/apigateway/${var.organization_name}-${var.environment_name}-${var.platform_name}-snyk-webhook"
  retention_in_days = 90
  kms_key_id        = var.findings_kms_key_arn
}

resource "aws_apigatewayv2_integration" "snyk_webhook_lambda_integration" {
  api_id                 = aws_apigatewayv2_api.snyk_webhook_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.snyk_finding_normalizer.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "snyk_webhook_route" {
  api_id    = aws_apigatewayv2_api.snyk_webhook_api.id
  route_key = "POST /snyk-findings"
  target    = "integrations/${aws_apigatewayv2_integration.snyk_webhook_lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "snyk_webhook_stage" {
  api_id      = aws_apigatewayv2_api.snyk_webhook_api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.snyk_webhook_api_access_logs.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      protocol         = "$context.protocol"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }

  default_route_settings {
    throttling_burst_limit = var.webhook_throttling_burst_limit
    throttling_rate_limit  = var.webhook_throttling_rate_limit
  }
}

resource "aws_wafv2_web_acl" "snyk_webhook_api" {
  name        = "${var.organization_name}-${var.environment_name}-${var.platform_name}-snyk-webhook"
  description = "Rate limits public Snyk webhook API traffic."
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "source-ip-rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        aggregate_key_type = "IP"
        limit              = var.webhook_waf_rate_limit
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.organization_name}-${var.environment_name}-${var.platform_name}-snyk-webhook-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.organization_name}-${var.environment_name}-${var.platform_name}-snyk-webhook"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "snyk_webhook_api" {
  resource_arn = aws_apigatewayv2_stage.snyk_webhook_stage.arn
  web_acl_arn  = aws_wafv2_web_acl.snyk_webhook_api.arn
}

resource "aws_lambda_permission" "allow_apigateway_to_invoke_snyk_normalizer" {
  statement_id  = "AllowApiGatewayInvokeSnykNormalizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.snyk_finding_normalizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.snyk_webhook_api.execution_arn}/*/*"
}

resource "github_repository_webhook" "snyk_scan_webhook" {
  repository = var.github_repository_name

  configuration {
    url          = "${aws_apigatewayv2_stage.snyk_webhook_stage.invoke_url}/snyk-findings"
    content_type = "json"
    insecure_ssl = false
    secret       = var.github_webhook_secret
  }

  events = [
    "check_run",
    "check_suite",
    "code_scanning_alert",
    "pull_request"
  ]

  active = true
}
