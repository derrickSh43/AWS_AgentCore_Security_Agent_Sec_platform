data "aws_iam_policy_document" "devops_agent_service_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["aidevops.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "devops_agent_monitor_role" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-devops-agent-monitor"
  assume_role_policy = data.aws_iam_policy_document.devops_agent_service_assume_role.json
}

resource "aws_iam_role_policy_attachment" "devops_agent_access_policy_attachment" {
  role       = aws_iam_role.devops_agent_monitor_role.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsAgentAccessPolicy"
}

data "aws_iam_policy_document" "devops_agent_resource_explorer_policy_document" {
  statement {
    sid    = "AllowResourceExplorerServiceLinkedRole"
    effect = "Allow"

    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::*:role/aws-service-role/resource-explorer-2.amazonaws.com/AWSServiceRoleForResourceExplorer"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["resource-explorer-2.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "devops_agent_resource_explorer_policy" {
  name   = "${var.organization_name}-${var.environment_name}-${var.platform_name}-devops-agent-resource-explorer"
  policy = data.aws_iam_policy_document.devops_agent_resource_explorer_policy_document.json
}

resource "aws_iam_role_policy_attachment" "devops_agent_resource_explorer_policy_attachment" {
  role       = aws_iam_role.devops_agent_monitor_role.name
  policy_arn = aws_iam_policy.devops_agent_resource_explorer_policy.arn
}

resource "aws_iam_role" "devops_agent_operator_role" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-devops-agent-operator"
  assume_role_policy = data.aws_iam_policy_document.devops_agent_service_assume_role.json
}

resource "aws_iam_role_policy_attachment" "devops_agent_operator_access_policy_attachment" {
  role       = aws_iam_role.devops_agent_operator_role.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsOperatorAppAccessPolicy"
}

resource "time_sleep" "wait_for_devops_agent_iam_propagation" {
  create_duration = "30s"

  depends_on = [
    aws_iam_role_policy_attachment.devops_agent_access_policy_attachment,
    aws_iam_role_policy_attachment.devops_agent_resource_explorer_policy_attachment,
    aws_iam_role_policy_attachment.devops_agent_operator_access_policy_attachment
  ]
}

resource "awscc_devopsagent_agent_space" "eks_operations_agent_space" {
  name        = "${var.organization_name}-${var.environment_name}-${var.platform_name}-operations-agent"
  description = "AWS DevOps Agent space for EKS operations context, incident correlation, and mitigation planning."

  operator_app = {
    iam = {
      operator_app_role_arn = aws_iam_role.devops_agent_operator_role.arn
    }
  }

  depends_on = [
    time_sleep.wait_for_devops_agent_iam_propagation
  ]
}

resource "awscc_devopsagent_association" "monitoring_account_association" {
  agent_space_id = awscc_devopsagent_agent_space.eks_operations_agent_space.agent_space_id
  service_id     = "aws"

  configuration = {
    aws = {
      assumable_role_arn = aws_iam_role.devops_agent_monitor_role.arn
      account_id         = var.aws_account_id
      account_type       = "monitor"
      resources          = []
    }
  }
}

resource "aws_cloudwatch_log_group" "devops_agent_logs" {
  name              = "/aws/${var.organization_name}/${var.environment_name}/${var.platform_name}/devops-agent"
  retention_in_days = 90
  kms_key_id        = var.findings_kms_key_arn
}

data "aws_iam_policy_document" "devops_agent_ingestor_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "devops_agent_ingestor_role" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-devops-agent-ingestor"
  assume_role_policy = data.aws_iam_policy_document.devops_agent_ingestor_assume_role.json
}

data "aws_iam_policy_document" "devops_agent_ingestor_policy_document" {
  statement {
    sid    = "WriteDevOpsAgentIngestorLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.organization_name}-${var.environment_name}-${var.platform_name}-devops-agent-ingestor:*"]
  }

  statement {
    sid    = "WriteOperationalContextFinding"
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:GetItem"
    ]

    resources = [var.normalized_findings_table_arn]
  }

  statement {
    sid       = "PublishOperationalContextEvent"
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = [var.findings_event_bus_arn]
  }

  statement {
    sid    = "ReadImportSecrets"
    effect = "Allow"

    actions = ["secretsmanager:GetSecretValue"]

    resources = compact([
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

resource "aws_iam_policy" "devops_agent_ingestor_policy" {
  name   = "${var.organization_name}-${var.environment_name}-${var.platform_name}-devops-agent-ingestor"
  policy = data.aws_iam_policy_document.devops_agent_ingestor_policy_document.json
}

resource "aws_iam_role_policy_attachment" "devops_agent_ingestor_policy_attachment" {
  role       = aws_iam_role.devops_agent_ingestor_role.name
  policy_arn = aws_iam_policy.devops_agent_ingestor_policy.arn
}

resource "aws_lambda_function" "ingest_devops_agent_insights" {
  function_name    = "${var.organization_name}-${var.environment_name}-${var.platform_name}-devops-agent-ingestor"
  role             = aws_iam_role.devops_agent_ingestor_role.arn
  filename         = var.lambda_package_path
  source_code_hash = var.lambda_package_source_code_hash
  handler          = "devops_agent_ingestor.handler"
  runtime          = "python3.13"
  timeout          = 120
  memory_size      = 512
  kms_key_arn      = var.findings_kms_key_arn

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DEVOPS_AGENT_SPACE_ID           = awscc_devopsagent_agent_space.eks_operations_agent_space.agent_space_id
      NORMALIZED_FINDINGS_TABLE       = var.normalized_findings_table_name
      FINDINGS_EVENT_BUS_NAME         = var.findings_event_bus_name
      DEVOPS_AGENT_LOG_GROUP          = aws_cloudwatch_log_group.devops_agent_logs.name
      DEFECTDOJO_URL                  = var.defectdojo_api_url
      DEFECTDOJO_API_TOKEN_SECRET_ARN = coalesce(var.defectdojo_api_token_secret_arn, "")
      DEFECTDOJO_ENGAGEMENT_ID        = var.defectdojo_engagement_id
      DEFECTDOJO_LEAD_ID              = var.defectdojo_lead_id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.devops_agent_ingestor_policy_attachment
  ]
}

resource "aws_cloudwatch_event_rule" "devops_agent_insight_event" {
  name           = "${var.organization_name}-${var.environment_name}-${var.platform_name}-devops-agent-insight-event"
  event_bus_name = "default"

  event_pattern = jsonencode({
    source        = ["aws.devops-agent"]
    "detail-type" = ["DevOps Agent Insight", "DevOps Agent Investigation Completed"]
  })
}

resource "aws_cloudwatch_event_target" "devops_agent_insight_ingestor_target" {
  rule      = aws_cloudwatch_event_rule.devops_agent_insight_event.name
  target_id = "ingest-devops-agent-insights"
  arn       = aws_lambda_function.ingest_devops_agent_insights.arn
}

resource "aws_lambda_permission" "allow_eventbridge_to_invoke_devops_agent_ingestor" {
  statement_id  = "AllowEventBridgeInvokeDevOpsAgentIngestor"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest_devops_agent_insights.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.devops_agent_insight_event.arn
}
