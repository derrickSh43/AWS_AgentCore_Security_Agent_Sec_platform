resource "aws_cloudwatch_log_group" "falco_runtime_alerts" {
  name              = "/aws/eks/${var.eks_cluster_name}/${var.platform_name}/falco-runtime-alerts"
  retention_in_days = 30
  kms_key_id        = var.findings_kms_key_arn
}

data "aws_iam_policy_document" "falco_irsa_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.falco_namespace}:${var.falco_service_account_name}"]
    }
  }
}

resource "aws_iam_role" "falco_cloudwatch_writer_role" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-falco-cloudwatch-writer"
  assume_role_policy = data.aws_iam_policy_document.falco_irsa_assume_role.json
}

data "aws_iam_policy_document" "falco_cloudwatch_write_policy_document" {
  statement {
    sid    = "WriteFalcoRuntimeAlerts"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]

    resources = [
      aws_cloudwatch_log_group.falco_runtime_alerts.arn,
      "${aws_cloudwatch_log_group.falco_runtime_alerts.arn}:*"
    ]
  }
}

resource "aws_iam_policy" "falco_cloudwatch_write_policy" {
  name   = "${var.organization_name}-${var.environment_name}-${var.platform_name}-falco-cloudwatch-write"
  policy = data.aws_iam_policy_document.falco_cloudwatch_write_policy_document.json
}

resource "aws_iam_role_policy_attachment" "falco_cloudwatch_write_policy_attachment" {
  role       = aws_iam_role.falco_cloudwatch_writer_role.name
  policy_arn = aws_iam_policy.falco_cloudwatch_write_policy.arn
}

resource "kubernetes_namespace_v1" "falco" {
  metadata {
    name = var.falco_namespace
  }
}

resource "helm_release" "falco_runtime_detection" {
  name       = "${var.organization_name}-${var.environment_name}-${var.platform_name}-falco"
  namespace  = kubernetes_namespace_v1.falco.metadata[0].name
  repository = "https://falcosecurity.github.io/charts"
  chart      = "falco"
  version    = var.falco_chart_version

  values = [
    yamlencode({
      serviceAccount = {
        create = true
        name   = var.falco_service_account_name
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.falco_cloudwatch_writer_role.arn
        }
      }

      driver = {
        kind = "modern_ebpf"
      }

      falcosidekick = {
        enabled = true
        config = {
          cloudwatchlogs = {
            region          = var.aws_region
            loggroup        = aws_cloudwatch_log_group.falco_runtime_alerts.name
            logstream       = "falco-runtime-alerts"
            minimumpriority = "warning"
          }
        }
      }

      collectors = {
        kubernetes = {
          enabled = true
        }
      }
    })
  ]

  depends_on = [
    aws_iam_role_policy_attachment.falco_cloudwatch_write_policy_attachment
  ]
}

data "aws_iam_policy_document" "falco_normalizer_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "falco_finding_normalizer_role" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-falco-finding-normalizer"
  assume_role_policy = data.aws_iam_policy_document.falco_normalizer_assume_role.json
}

data "aws_iam_policy_document" "falco_finding_normalizer_policy_document" {
  statement {
    sid    = "WriteNormalizerLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.organization_name}-${var.environment_name}-${var.platform_name}-falco-finding-normalizer:*"]
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
    sid    = "ArchiveRawFalcoAlert"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:PutObjectTagging"
    ]

    resources = ["arn:aws:s3:::${var.raw_findings_archive_bucket}/falco/*"]
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

resource "aws_iam_policy" "falco_finding_normalizer_policy" {
  name   = "${var.organization_name}-${var.environment_name}-${var.platform_name}-falco-finding-normalizer"
  policy = data.aws_iam_policy_document.falco_finding_normalizer_policy_document.json
}

resource "aws_iam_role_policy_attachment" "falco_finding_normalizer_policy_attachment" {
  role       = aws_iam_role.falco_finding_normalizer_role.name
  policy_arn = aws_iam_policy.falco_finding_normalizer_policy.arn
}

resource "aws_lambda_function" "falco_finding_normalizer" {
  function_name    = "${var.organization_name}-${var.environment_name}-${var.platform_name}-falco-finding-normalizer"
  role             = aws_iam_role.falco_finding_normalizer_role.arn
  filename         = var.lambda_package_path
  source_code_hash = var.lambda_package_source_code_hash
  handler          = "falco_normalizer.handler"
  runtime          = "python3.13"
  timeout          = 60
  memory_size      = 256
  kms_key_arn      = var.findings_kms_key_arn

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      FINDINGS_EVENT_BUS_NAME         = var.findings_event_bus_name
      NORMALIZED_FINDINGS_TABLE       = var.normalized_findings_table
      RAW_FINDINGS_ARCHIVE_BUCKET     = var.raw_findings_archive_bucket
      FINDING_SOURCE                  = "falco"
      DEFECTDOJO_URL                  = var.defectdojo_api_url
      DEFECTDOJO_API_TOKEN_SECRET_ARN = coalesce(var.defectdojo_api_token_secret_arn, "")
      DEFECTDOJO_ENGAGEMENT_ID        = var.defectdojo_engagement_id
      DEFECTDOJO_LEAD_ID              = var.defectdojo_lead_id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.falco_finding_normalizer_policy_attachment
  ]
}

resource "aws_lambda_permission" "allow_cloudwatch_logs_to_invoke_falco_normalizer" {
  statement_id  = "AllowCloudWatchLogsInvokeFalcoNormalizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.falco_finding_normalizer.function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "${aws_cloudwatch_log_group.falco_runtime_alerts.arn}:*"
}

resource "aws_cloudwatch_log_subscription_filter" "falco_alerts_to_normalizer" {
  name            = "${var.organization_name}-${var.environment_name}-${var.platform_name}-falco-alerts-to-normalizer"
  log_group_name  = aws_cloudwatch_log_group.falco_runtime_alerts.name
  filter_pattern  = ""
  destination_arn = aws_lambda_function.falco_finding_normalizer.arn

  depends_on = [
    aws_lambda_permission.allow_cloudwatch_logs_to_invoke_falco_normalizer
  ]
}
