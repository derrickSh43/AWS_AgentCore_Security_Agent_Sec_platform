resource "aws_cloudwatch_log_group" "prowler_scan_logs" {
  name              = "/aws/${var.organization_name}/${var.environment_name}/${var.platform_name}/prowler-scans"
  retention_in_days = 30
}

resource "aws_s3_bucket" "prowler_raw_findings" {
  bucket = "${var.organization_name}-${var.environment_name}-${var.platform_name}-prowler-raw-findings"
}

resource "aws_s3_bucket_versioning" "prowler_raw_findings_versioning" {
  bucket = aws_s3_bucket.prowler_raw_findings.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "prowler_raw_findings_encryption" {
  bucket = aws_s3_bucket.prowler_raw_findings.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.findings_kms_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "prowler_raw_findings_public_access_block" {
  bucket = aws_s3_bucket.prowler_raw_findings.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "kubernetes_namespace_v1" "prowler" {
  metadata {
    name = var.prowler_namespace
  }
}

data "aws_iam_policy_document" "prowler_irsa_assume_role" {
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
      values   = ["system:serviceaccount:${var.prowler_namespace}:${var.prowler_service_account_name}"]
    }
  }
}

resource "aws_iam_role" "prowler_scan_pod_role" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-prowler-scan-pod"
  assume_role_policy = data.aws_iam_policy_document.prowler_irsa_assume_role.json
}

resource "aws_iam_role_policy_attachment" "prowler_security_audit_policy" {
  role       = aws_iam_role.prowler_scan_pod_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}

resource "aws_iam_role_policy_attachment" "prowler_view_only_policy" {
  role       = aws_iam_role.prowler_scan_pod_role.name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

data "aws_iam_policy_document" "prowler_scan_pod_write_policy_document" {
  statement {
    sid    = "WriteProwlerRawFindings"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.prowler_raw_findings.arn,
      "${aws_s3_bucket.prowler_raw_findings.arn}/*"
    ]
  }

  statement {
    sid    = "UseFindingsKmsKeyForProwlerOutput"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]

    resources = [var.findings_kms_key_arn]
  }
}

resource "aws_iam_policy" "prowler_scan_pod_write_policy" {
  name   = "${var.organization_name}-${var.environment_name}-${var.platform_name}-prowler-write-findings"
  policy = data.aws_iam_policy_document.prowler_scan_pod_write_policy_document.json
}

resource "aws_iam_role_policy_attachment" "prowler_scan_pod_write_policy_attachment" {
  role       = aws_iam_role.prowler_scan_pod_role.name
  policy_arn = aws_iam_policy.prowler_scan_pod_write_policy.arn
}

resource "kubernetes_service_account_v1" "prowler" {
  metadata {
    name      = var.prowler_service_account_name
    namespace = kubernetes_namespace_v1.prowler.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.prowler_scan_pod_role.arn
    }
  }
}

resource "kubernetes_cron_job_v1" "prowler_posture_scan" {
  metadata {
    name      = "${var.organization_name}-${var.environment_name}-${var.platform_name}-prowler"
    namespace = kubernetes_namespace_v1.prowler.metadata[0].name
  }

  spec {
    schedule                      = var.prowler_cron_schedule
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {}

      spec {
        backoff_limit = 1

        template {
          metadata {
            labels = {
              "app.kubernetes.io/name" = "prowler"
            }
          }

          spec {
            service_account_name = kubernetes_service_account_v1.prowler.metadata[0].name
            restart_policy       = "Never"

            container {
              name              = "prowler"
              image             = var.prowler_container_image
              image_pull_policy = "Always"

              command = ["/bin/sh", "-c"]
              args = [
                <<-SCRIPT
                set -eu
                mkdir -p /tmp/prowler-output
                prowler aws -M json-asff json-ocsf -o /tmp/prowler-output
                python - <<'PY'
                import boto3
                import os
                import pathlib
                import time

                bucket = os.environ["PROWLER_RAW_FINDINGS_BUCKET"]
                account_id = os.environ["AWS_ACCOUNT_ID"]
                prefix = f"account={account_id}/run={time.strftime('%Y%m%d%H%M%S')}"
                s3 = boto3.client("s3")

                for path in pathlib.Path("/tmp/prowler-output").rglob("*"):
                    if path.is_file():
                        key = f"{prefix}/{path.relative_to('/tmp/prowler-output')}"
                        s3.upload_file(str(path), bucket, key)
                PY
                SCRIPT
              ]

              env {
                name  = "AWS_REGION"
                value = var.aws_region
              }

              env {
                name  = "AWS_ACCOUNT_ID"
                value = var.aws_account_id
              }

              env {
                name  = "PROWLER_RAW_FINDINGS_BUCKET"
                value = aws_s3_bucket.prowler_raw_findings.bucket
              }

              resources {
                requests = {
                  cpu    = "500m"
                  memory = "1Gi"
                }
                limits = {
                  cpu    = "2"
                  memory = "3Gi"
                }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.prowler_security_audit_policy,
    aws_iam_role_policy_attachment.prowler_view_only_policy,
    aws_iam_role_policy_attachment.prowler_scan_pod_write_policy_attachment
  ]
}

data "aws_iam_policy_document" "prowler_normalizer_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "prowler_finding_normalizer_role" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-prowler-finding-normalizer"
  assume_role_policy = data.aws_iam_policy_document.prowler_normalizer_assume_role.json
}

data "aws_iam_policy_document" "prowler_finding_normalizer_policy_document" {
  statement {
    sid    = "WriteNormalizerLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.organization_name}-${var.environment_name}-${var.platform_name}-prowler-finding-normalizer:*"]
  }

  statement {
    sid    = "ReadProwlerRawFindings"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion"
    ]

    resources = ["${aws_s3_bucket.prowler_raw_findings.arn}/*"]
  }

  statement {
    sid    = "ArchiveNormalizedProwlerRawPayload"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:PutObjectTagging"
    ]

    resources = ["arn:aws:s3:::${var.raw_findings_archive_bucket}/prowler/*"]
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
}

resource "aws_iam_policy" "prowler_finding_normalizer_policy" {
  name   = "${var.organization_name}-${var.environment_name}-${var.platform_name}-prowler-finding-normalizer"
  policy = data.aws_iam_policy_document.prowler_finding_normalizer_policy_document.json
}

resource "aws_iam_role_policy_attachment" "prowler_finding_normalizer_policy_attachment" {
  role       = aws_iam_role.prowler_finding_normalizer_role.name
  policy_arn = aws_iam_policy.prowler_finding_normalizer_policy.arn
}

resource "aws_lambda_function" "prowler_finding_normalizer" {
  function_name    = "${var.organization_name}-${var.environment_name}-${var.platform_name}-prowler-finding-normalizer"
  role             = aws_iam_role.prowler_finding_normalizer_role.arn
  filename         = var.lambda_package_path
  source_code_hash = var.lambda_package_source_code_hash
  handler          = "prowler_normalizer.handler"
  runtime          = "python3.13"
  timeout          = 300
  memory_size      = 512
  kms_key_arn      = var.findings_kms_key_arn

  environment {
    variables = {
      FINDINGS_EVENT_BUS_NAME         = var.findings_event_bus_name
      NORMALIZED_FINDINGS_TABLE       = var.normalized_findings_table_name
      RAW_FINDINGS_ARCHIVE_BUCKET     = var.raw_findings_archive_bucket
      FINDING_SOURCE                  = "prowler"
      DEFECTDOJO_URL                  = var.defectdojo_api_url
      DEFECTDOJO_API_TOKEN_SECRET_ARN = coalesce(var.defectdojo_api_token_secret_arn, "")
      DEFECTDOJO_ENGAGEMENT_ID        = var.defectdojo_engagement_id
      DEFECTDOJO_LEAD_ID              = var.defectdojo_lead_id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.prowler_finding_normalizer_policy_attachment
  ]
}

resource "aws_lambda_permission" "allow_s3_to_invoke_prowler_normalizer" {
  statement_id  = "AllowS3InvokeProwlerNormalizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.prowler_finding_normalizer.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.prowler_raw_findings.arn
}

resource "aws_s3_bucket_notification" "prowler_raw_findings_created" {
  bucket = aws_s3_bucket.prowler_raw_findings.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.prowler_finding_normalizer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".json"
  }

  depends_on = [
    aws_lambda_permission.allow_s3_to_invoke_prowler_normalizer
  ]
}
