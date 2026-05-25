data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  security_findings_kms_role_names = [
    "${var.organization_name}-${var.environment_name}-${var.platform_name}-falco-cloudwatch-writer",
    "${var.organization_name}-${var.environment_name}-${var.platform_name}-falco-finding-normalizer",
    "${var.organization_name}-${var.environment_name}-${var.platform_name}-prowler-scan-pod",
    "${var.organization_name}-${var.environment_name}-${var.platform_name}-prowler-finding-normalizer",
    "${var.organization_name}-${var.environment_name}-${var.platform_name}-snyk-finding-normalizer",
    "${var.organization_name}-${var.environment_name}-${var.platform_name}-security-agent-orchestrator",
    "${var.organization_name}-${var.environment_name}-${var.platform_name}-devops-agent-ingestor",
    "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-tools",
    "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-invoker",
    "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-reasoner-runtime"
  ]

  security_findings_kms_role_arns = flatten([
    for role_name in local.security_findings_kms_role_names : [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${role_name}",
      "arn:${data.aws_partition.current.partition}:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${role_name}/*"
    ]
  ])

  security_findings_kms_via_services = [
    "dynamodb.${var.aws_region}.amazonaws.com",
    "lambda.${var.aws_region}.amazonaws.com",
    "logs.${var.aws_region}.amazonaws.com",
    "s3.${var.aws_region}.amazonaws.com",
    "secretsmanager.${var.aws_region}.amazonaws.com",
    "sqs.${var.aws_region}.amazonaws.com"
  ]
}

data "aws_iam_policy_document" "security_findings_kms_key_policy" {
  statement {
    sid    = "AllowAccountKeyAdministration"
    effect = "Allow"

    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion"
    ]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    resources = ["*"]
  }

  statement {
    sid    = "AllowSecurityFindingsWorkloadKeyUse"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = local.security_findings_kms_role_arns
    }
  }

  statement {
    sid    = "AllowSecurityFindingsServiceKeyUse"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "kms:ViaService"
      values   = local.security_findings_kms_via_services
    }
  }
}

resource "aws_kms_key" "security_findings_encryption_key" {
  description             = "${var.organization_name}-${var.environment_name}-${var.platform_name} findings encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.security_findings_kms_key_policy.json
}

resource "aws_kms_alias" "security_findings_encryption_key_alias" {
  name          = "alias/${var.organization_name}-${var.environment_name}-${var.platform_name}-findings"
  target_key_id = aws_kms_key.security_findings_encryption_key.key_id
}

resource "aws_s3_bucket" "raw_security_findings_archive" {
  bucket = "${var.organization_name}-${var.environment_name}-${var.platform_name}-raw-security-findings"
}

resource "aws_s3_bucket_versioning" "raw_security_findings_archive_versioning" {
  bucket = aws_s3_bucket.raw_security_findings_archive.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_security_findings_archive_encryption" {
  bucket = aws_s3_bucket.raw_security_findings_archive.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.security_findings_encryption_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "raw_security_findings_archive_public_access_block" {
  bucket = aws_s3_bucket.raw_security_findings_archive.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "raw_security_findings_archive_lifecycle" {
  bucket = aws_s3_bucket.raw_security_findings_archive.id

  rule {
    id     = "retain-raw-findings-for-one-year"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_dynamodb_table" "normalized_security_findings" {
  name         = "${var.organization_name}-${var.environment_name}-${var.platform_name}-normalized-findings"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "finding_id"
  range_key    = "source"

  attribute {
    name = "finding_id"
    type = "S"
  }

  attribute {
    name = "source"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "severity"
    type = "S"
  }

  attribute {
    name = "last_seen_epoch"
    type = "N"
  }

  global_secondary_index {
    name            = "status-severity-last-seen-index"
    projection_type = "ALL"

    key_schema {
      attribute_name = "status"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "severity"
      key_type       = "RANGE"
    }
  }

  global_secondary_index {
    name            = "source-last-seen-index"
    projection_type = "ALL"

    key_schema {
      attribute_name = "source"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "last_seen_epoch"
      key_type       = "RANGE"
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.security_findings_encryption_key.arn
  }
}

resource "aws_dynamodb_table" "finding_correlation_state" {
  name         = "${var.organization_name}-${var.environment_name}-${var.platform_name}-finding-correlation-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "correlation_id"

  attribute {
    name = "correlation_id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "updated_epoch"
    type = "N"
  }

  global_secondary_index {
    name            = "status-updated-index"
    projection_type = "ALL"

    key_schema {
      attribute_name = "status"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "updated_epoch"
      key_type       = "RANGE"
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.security_findings_encryption_key.arn
  }
}

resource "aws_cloudwatch_event_bus" "security_findings" {
  name = "${var.organization_name}-${var.environment_name}-${var.platform_name}-security-findings-bus"
}

resource "aws_cloudwatch_event_archive" "security_findings_archive" {
  name             = "${var.organization_name}-${var.environment_name}-${var.platform_name}-security-findings-archive"
  event_source_arn = aws_cloudwatch_event_bus.security_findings.arn
  retention_days   = 90
}

resource "aws_sqs_queue" "normalized_findings_dlq" {
  name                      = "${var.organization_name}-${var.environment_name}-${var.platform_name}-normalized-findings-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = aws_kms_key.security_findings_encryption_key.arn
}

resource "aws_cloudwatch_log_group" "findings_pipeline_logs" {
  name              = "/aws/${var.organization_name}/${var.environment_name}/${var.platform_name}/findings-pipeline"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.security_findings_encryption_key.arn
}
