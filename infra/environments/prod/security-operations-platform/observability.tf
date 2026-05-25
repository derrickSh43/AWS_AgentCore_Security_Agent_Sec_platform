locals {
  lambda_alarm_specs = merge(
    var.enable_falco_runtime_detection ? {
      "${var.organization_name}-${var.environment_name}-${var.platform_name}-falco-finding-normalizer" = {
        duration_threshold_ms = 45000
      }
    } : {},
    var.enable_prowler_posture_scanning ? {
      "${var.organization_name}-${var.environment_name}-${var.platform_name}-prowler-finding-normalizer" = {
        duration_threshold_ms = 240000
      }
    } : {},
    var.enable_snyk_pull_request_scanning ? {
      "${var.organization_name}-${var.environment_name}-${var.platform_name}-snyk-finding-normalizer" = {
        duration_threshold_ms = 45000
      }
    } : {},
    var.enable_security_agent_pentesting ? {
      "${var.organization_name}-${var.environment_name}-${var.platform_name}-security-agent-weekly-pentest" = {
        duration_threshold_ms = 240000
      }
      "${var.organization_name}-${var.environment_name}-${var.platform_name}-security-agent-findings-ingestor" = {
        duration_threshold_ms = 240000
      }
    } : {},
    var.enable_devops_agent_operations_context ? {
      "${var.organization_name}-${var.environment_name}-${var.platform_name}-devops-agent-ingestor" = {
        duration_threshold_ms = 90000
      }
    } : {},
    var.enable_agentcore_reasoning_layer ? {
      "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-query-falco" = {
        duration_threshold_ms = 45000
      }
      "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-query-prowler" = {
        duration_threshold_ms = 45000
      }
      "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-query-snyk" = {
        duration_threshold_ms = 45000
      }
      "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-query-security-agent" = {
        duration_threshold_ms = 45000
      }
      "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-query-devops-incidents" = {
        duration_threshold_ms = 45000
      }
      "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-create-daily-digest" = {
        duration_threshold_ms = 90000
      }
      "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-open-remediation-pr" = {
        duration_threshold_ms = 90000
      }
      "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-invoker" = {
        duration_threshold_ms = 90000
      }
    } : {}
  )

  alarm_actions = [aws_sns_topic.security_operations_alerts.arn]
}

resource "aws_sns_topic" "security_operations_alerts" {
  name              = "${var.organization_name}-${var.environment_name}-${var.platform_name}-security-operations-alerts"
  kms_master_key_id = module.prod_normalized_findings_pipeline.security_findings_kms_key_arn
}

resource "aws_sns_topic_subscription" "security_operations_email" {
  count     = var.alarm_notification_email == null || var.alarm_notification_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.security_operations_alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_notification_email
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = local.lambda_alarm_specs

  alarm_name          = "${each.key}-errors"
  alarm_description   = "Lambda reported one or more errors in a five-minute window."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    FunctionName = each.key
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each = local.lambda_alarm_specs

  alarm_name          = "${each.key}-throttles"
  alarm_description   = "Lambda was throttled in a five-minute window."
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    FunctionName = each.key
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  for_each = local.lambda_alarm_specs

  alarm_name          = "${each.key}-duration"
  alarm_description   = "Lambda average duration exceeded the configured threshold."
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = each.value.duration_threshold_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    FunctionName = each.key
  }
}

resource "aws_cloudwatch_metric_alarm" "normalized_findings_dlq_depth" {
  alarm_name          = "${var.organization_name}-${var.environment_name}-${var.platform_name}-normalized-findings-dlq-depth"
  alarm_description   = "The normalized findings dead-letter queue contains failed messages."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    QueueName = "${var.organization_name}-${var.environment_name}-${var.platform_name}-normalized-findings-dlq"
  }
}
