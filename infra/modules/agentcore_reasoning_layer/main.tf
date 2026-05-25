data "aws_iam_policy_document" "agentcore_service_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "agentcore_gateway_role" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-gateway"
  assume_role_policy = data.aws_iam_policy_document.agentcore_service_assume_role.json
}

data "aws_iam_policy_document" "agentcore_gateway_policy_document" {
  statement {
    sid    = "InvokeSecurityToolLambdas"
    effect = "Allow"

    actions = ["lambda:InvokeFunction"]

    resources = [
      aws_lambda_function.query_falco_findings_tool.arn,
      aws_lambda_function.query_prowler_findings_tool.arn,
      aws_lambda_function.query_snyk_findings_tool.arn,
      aws_lambda_function.query_security_agent_findings_tool.arn,
      aws_lambda_function.query_devops_incidents_tool.arn,
      aws_lambda_function.create_daily_digest_tool.arn,
      aws_lambda_function.open_remediation_pull_request_tool.arn
    ]
  }
}

resource "aws_iam_policy" "agentcore_gateway_policy" {
  name   = "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-gateway"
  policy = data.aws_iam_policy_document.agentcore_gateway_policy_document.json
}

resource "aws_iam_role_policy_attachment" "agentcore_gateway_policy_attachment" {
  role       = aws_iam_role.agentcore_gateway_role.name
  policy_arn = aws_iam_policy.agentcore_gateway_policy.arn
}

resource "aws_bedrockagentcore_gateway" "security_tools_gateway" {
  name            = "${var.organization_name}-${var.environment_name}-${var.platform_name}-security-tools-gateway"
  description     = "MCP gateway exposing security and operations tools to the AgentCore reasoner."
  role_arn        = aws_iam_role.agentcore_gateway_role.arn
  authorizer_type = "AWS_IAM"
  protocol_type   = "MCP"

  depends_on = [
    aws_iam_role_policy_attachment.agentcore_gateway_policy_attachment
  ]
}

data "aws_iam_policy_document" "agentcore_runtime_policy_document" {
  statement {
    sid    = "PullReasonerContainerImage"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "ReadFindingsForReasoning"
    effect = "Allow"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]

    resources = [
      var.normalized_findings_table_arn,
      "${var.normalized_findings_table_arn}/index/*",
      var.correlation_state_table_arn,
      "${var.correlation_state_table_arn}/index/*"
    ]
  }

  statement {
    sid       = "PublishAgentEvents"
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = [var.findings_event_bus_arn]
  }

  statement {
    sid    = "UseFindingsKmsKey"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]

    resources = [var.findings_kms_key_arn]
  }
}

resource "aws_iam_role" "agentcore_reasoner_runtime_role" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-reasoner-runtime"
  assume_role_policy = data.aws_iam_policy_document.agentcore_service_assume_role.json
}

resource "aws_iam_policy" "agentcore_reasoner_runtime_policy" {
  name   = "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-reasoner-runtime"
  policy = data.aws_iam_policy_document.agentcore_runtime_policy_document.json
}

resource "aws_iam_role_policy_attachment" "agentcore_reasoner_runtime_policy_attachment" {
  role       = aws_iam_role.agentcore_reasoner_runtime_role.name
  policy_arn = aws_iam_policy.agentcore_reasoner_runtime_policy.arn
}

resource "aws_bedrockagentcore_agent_runtime" "security_reasoner_runtime" {
  agent_runtime_name = "${var.organization_name}_${var.environment_name}_${var.platform_name}_security_reasoner"
  description        = "Security reasoning agent that correlates Falco, Prowler, Snyk, Security Agent, and DevOps Agent output."
  role_arn           = aws_iam_role.agentcore_reasoner_runtime_role.arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = var.agentcore_reasoner_container_uri
    }
  }

  environment_variables = {
    AGENTCORE_GATEWAY_URL     = aws_bedrockagentcore_gateway.security_tools_gateway.gateway_url
    FINDINGS_EVENT_BUS_NAME   = var.findings_event_bus_name
    NORMALIZED_FINDINGS_TABLE = var.normalized_findings_table_name
    CORRELATION_STATE_TABLE   = var.correlation_state_table_name
    DASHBOARD_API_ENDPOINT    = var.dashboard_api_endpoint
  }

  network_configuration {
    network_mode = "PUBLIC"
  }

  protocol_configuration {
    server_protocol = "HTTP"
  }

  depends_on = [
    aws_iam_role_policy_attachment.agentcore_reasoner_runtime_policy_attachment
  ]
}

resource "aws_bedrockagentcore_agent_runtime_endpoint" "security_reasoner_endpoint" {
  name             = "${var.organization_name}-${var.environment_name}-${var.platform_name}-security-reasoner"
  description      = "Endpoint used by scheduled and critical finding triggers."
  agent_runtime_id = aws_bedrockagentcore_agent_runtime.security_reasoner_runtime.agent_runtime_id
}

data "aws_iam_policy_document" "agentcore_tool_lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "agentcore_tool_lambda_role" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-tools"
  assume_role_policy = data.aws_iam_policy_document.agentcore_tool_lambda_assume_role.json
}

data "aws_iam_policy_document" "agentcore_tool_lambda_policy_document" {
  statement {
    sid    = "WriteToolLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-*:*"]
  }

  statement {
    sid    = "ReadAndCorrelateFindings"
    effect = "Allow"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem"
    ]

    resources = [
      var.normalized_findings_table_arn,
      "${var.normalized_findings_table_arn}/index/*",
      var.correlation_state_table_arn,
      "${var.correlation_state_table_arn}/index/*"
    ]
  }

  statement {
    sid       = "PublishReasoningEvents"
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = [var.findings_event_bus_arn]
  }

  statement {
    sid       = "ReadGitHubRemediationSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.organization_name}-${var.environment_name}-${var.platform_name}-github-remediation-*"]
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

resource "aws_iam_policy" "agentcore_tool_lambda_policy" {
  name   = "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-tools"
  policy = data.aws_iam_policy_document.agentcore_tool_lambda_policy_document.json
}

resource "aws_iam_role_policy_attachment" "agentcore_tool_lambda_policy_attachment" {
  role       = aws_iam_role.agentcore_tool_lambda_role.name
  policy_arn = aws_iam_policy.agentcore_tool_lambda_policy.arn
}

resource "aws_lambda_function" "query_falco_findings_tool" {
  function_name    = "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-query-falco"
  role             = aws_iam_role.agentcore_tool_lambda_role.arn
  filename         = var.lambda_package_path_tools
  source_code_hash = var.lambda_package_tools_source_code_hash
  handler          = "agentcore_tools.query_falco"
  runtime          = "python3.13"
  timeout          = 60
  memory_size      = 256
  kms_key_arn      = var.findings_kms_key_arn

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      NORMALIZED_FINDINGS_TABLE = var.normalized_findings_table_name
      FINDING_SOURCE            = "falco"
    }
  }
}

resource "aws_lambda_function" "query_prowler_findings_tool" {
  function_name    = "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-query-prowler"
  role             = aws_iam_role.agentcore_tool_lambda_role.arn
  filename         = var.lambda_package_path_tools
  source_code_hash = var.lambda_package_tools_source_code_hash
  handler          = "agentcore_tools.query_prowler"
  runtime          = "python3.13"
  timeout          = 60
  memory_size      = 256
  kms_key_arn      = var.findings_kms_key_arn

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      NORMALIZED_FINDINGS_TABLE = var.normalized_findings_table_name
      FINDING_SOURCE            = "prowler"
    }
  }
}

resource "aws_lambda_function" "query_snyk_findings_tool" {
  function_name    = "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-query-snyk"
  role             = aws_iam_role.agentcore_tool_lambda_role.arn
  filename         = var.lambda_package_path_tools
  source_code_hash = var.lambda_package_tools_source_code_hash
  handler          = "agentcore_tools.query_snyk"
  runtime          = "python3.13"
  timeout          = 60
  memory_size      = 256
  kms_key_arn      = var.findings_kms_key_arn

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      NORMALIZED_FINDINGS_TABLE = var.normalized_findings_table_name
      FINDING_SOURCE            = "snyk"
    }
  }
}

resource "aws_lambda_function" "query_security_agent_findings_tool" {
  function_name    = "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-query-security-agent"
  role             = aws_iam_role.agentcore_tool_lambda_role.arn
  filename         = var.lambda_package_path_tools
  source_code_hash = var.lambda_package_tools_source_code_hash
  handler          = "agentcore_tools.query_security_agent"
  runtime          = "python3.13"
  timeout          = 60
  memory_size      = 256
  kms_key_arn      = var.findings_kms_key_arn

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      NORMALIZED_FINDINGS_TABLE = var.normalized_findings_table_name
      FINDING_SOURCE            = "security-agent"
    }
  }
}

resource "aws_lambda_function" "query_devops_incidents_tool" {
  function_name    = "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-query-devops-incidents"
  role             = aws_iam_role.agentcore_tool_lambda_role.arn
  filename         = var.lambda_package_path_tools
  source_code_hash = var.lambda_package_tools_source_code_hash
  handler          = "agentcore_tools.query_devops_incidents"
  runtime          = "python3.13"
  timeout          = 60
  memory_size      = 256
  kms_key_arn      = var.findings_kms_key_arn

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      NORMALIZED_FINDINGS_TABLE = var.normalized_findings_table_name
      CORRELATION_STATE_TABLE   = var.correlation_state_table_name
    }
  }
}

resource "aws_lambda_function" "create_daily_digest_tool" {
  function_name    = "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-create-daily-digest"
  role             = aws_iam_role.agentcore_tool_lambda_role.arn
  filename         = var.lambda_package_path_tools
  source_code_hash = var.lambda_package_tools_source_code_hash
  handler          = "agentcore_tools.create_daily_digest"
  runtime          = "python3.13"
  timeout          = 120
  memory_size      = 512
  kms_key_arn      = var.findings_kms_key_arn

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      NORMALIZED_FINDINGS_TABLE = var.normalized_findings_table_name
      CORRELATION_STATE_TABLE   = var.correlation_state_table_name
      DASHBOARD_API_ENDPOINT    = var.dashboard_api_endpoint
    }
  }
}

resource "aws_lambda_function" "open_remediation_pull_request_tool" {
  function_name    = "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-open-remediation-pr"
  role             = aws_iam_role.agentcore_tool_lambda_role.arn
  filename         = var.lambda_package_path_tools
  source_code_hash = var.lambda_package_tools_source_code_hash
  handler          = "agentcore_tools.open_remediation_pull_request"
  runtime          = "python3.13"
  timeout          = 120
  memory_size      = 512
  kms_key_arn      = var.findings_kms_key_arn

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      NORMALIZED_FINDINGS_TABLE = var.normalized_findings_table_name
      CORRELATION_STATE_TABLE   = var.correlation_state_table_name
    }
  }
}

resource "aws_bedrockagentcore_gateway_target" "falco_findings_tool" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-falco-findings"
  gateway_identifier = aws_bedrockagentcore_gateway.security_tools_gateway.gateway_id
  description        = "Read normalized Falco runtime findings."

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.query_falco_findings_tool.arn

        tool_schema {
          inline_payload {
            name        = "query_falco_findings"
            description = "Query normalized Falco runtime findings by severity, resource, namespace, and status."

            input_schema {
              type = "object"

              property {
                name        = "status"
                type        = "string"
                description = "Finding status such as open, resolved, or suppressed."
              }

              property {
                name        = "severity"
                type        = "string"
                description = "Minimum severity to return."
              }
            }
          }
        }
      }
    }
  }
}

resource "aws_bedrockagentcore_gateway_target" "prowler_findings_tool" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-prowler-findings"
  gateway_identifier = aws_bedrockagentcore_gateway.security_tools_gateway.gateway_id
  description        = "Read normalized Prowler posture findings."

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.query_prowler_findings_tool.arn

        tool_schema {
          inline_payload {
            name        = "query_prowler_findings"
            description = "Query normalized Prowler cloud posture, RBAC, and cluster configuration findings."

            input_schema {
              type = "object"

              property {
                name        = "status"
                type        = "string"
                description = "Finding status such as open, resolved, or suppressed."
              }

              property {
                name        = "resource"
                type        = "string"
                description = "Cloud resource identifier to filter on."
              }
            }
          }
        }
      }
    }
  }
}

resource "aws_bedrockagentcore_gateway_target" "snyk_findings_tool" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-snyk-findings"
  gateway_identifier = aws_bedrockagentcore_gateway.security_tools_gateway.gateway_id
  description        = "Read normalized Snyk pull request findings."

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.query_snyk_findings_tool.arn

        tool_schema {
          inline_payload {
            name        = "query_snyk_findings"
            description = "Query normalized Snyk IaC and manifest findings by repository, pull request, and commit."

            input_schema {
              type = "object"

              property {
                name        = "repository"
                type        = "string"
                description = "Repository full name."
              }

              property {
                name        = "pull_request"
                type        = "string"
                description = "Pull request number or URL."
              }
            }
          }
        }
      }
    }
  }
}

resource "aws_bedrockagentcore_gateway_target" "security_agent_findings_tool" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-security-agent-findings"
  gateway_identifier = aws_bedrockagentcore_gateway.security_tools_gateway.gateway_id
  description        = "Read normalized AWS Security Agent penetration test findings."

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.query_security_agent_findings_tool.arn

        tool_schema {
          inline_payload {
            name        = "query_security_agent_findings"
            description = "Query normalized AWS Security Agent pentest findings and retest results."

            input_schema {
              type = "object"

              property {
                name        = "target_domain"
                type        = "string"
                description = "Verified application domain tested by AWS Security Agent."
              }
            }
          }
        }
      }
    }
  }
}

resource "aws_bedrockagentcore_gateway_target" "devops_incidents_tool" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-devops-incidents"
  gateway_identifier = aws_bedrockagentcore_gateway.security_tools_gateway.gateway_id
  description        = "Read AWS DevOps Agent operational incident context."

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.query_devops_incidents_tool.arn

        tool_schema {
          inline_payload {
            name        = "query_devops_incidents"
            description = "Query operational incidents and mitigation plans correlated by AWS DevOps Agent."

            input_schema {
              type = "object"

              property {
                name        = "resource"
                type        = "string"
                description = "Application or infrastructure resource involved in the incident."
              }
            }
          }
        }
      }
    }
  }
}

resource "aws_bedrockagentcore_gateway_target" "daily_digest_tool" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-daily-digest"
  gateway_identifier = aws_bedrockagentcore_gateway.security_tools_gateway.gateway_id
  description        = "Create dashboard-ready daily security digest output."

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.create_daily_digest_tool.arn

        tool_schema {
          inline_payload {
            name        = "create_daily_digest"
            description = "Create a prioritized plain-language digest excluding resolved findings."

            input_schema {
              type = "object"

              property {
                name        = "digest_date"
                type        = "string"
                description = "ISO-8601 date for the digest."
              }
            }
          }
        }
      }
    }
  }
}

resource "aws_bedrockagentcore_gateway_target" "remediation_pull_request_tool" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-remediation-pr"
  gateway_identifier = aws_bedrockagentcore_gateway.security_tools_gateway.gateway_id
  description        = "Open remediation pull requests. This tool never applies cluster changes."

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.open_remediation_pull_request_tool.arn

        tool_schema {
          inline_payload {
            name        = "open_remediation_pull_request"
            description = "Open one remediation pull request for a validated finding."

            input_schema {
              type = "object"

              property {
                name        = "finding_id"
                type        = "string"
                description = "Normalized finding ID to remediate."
                required    = true
              }

              property {
                name        = "target_repository"
                type        = "string"
                description = "Repository that should receive the pull request."
                required    = true
              }

              property {
                name        = "patch"
                type        = "string"
                description = "Unified diff or generated branch contents."
                required    = true
              }
            }
          }
        }
      }
    }
  }
}

data "aws_iam_policy_document" "agentcore_invoker_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "agentcore_invoker_role" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-invoker"
  assume_role_policy = data.aws_iam_policy_document.agentcore_invoker_assume_role.json
}

data "aws_iam_policy_document" "agentcore_invoker_policy_document" {
  statement {
    sid    = "WriteInvokerLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-invoker:*"]
  }

  statement {
    sid    = "InvokeAgentCoreReasoner"
    effect = "Allow"

    actions = [
      "bedrock-agentcore:InvokeAgentRuntime",
      "bedrock-agentcore:GetAgentRuntime"
    ]

    resources = [aws_bedrockagentcore_agent_runtime.security_reasoner_runtime.agent_runtime_arn]
  }

  statement {
    sid    = "TrackAgentCoreInvocationCooldown"
    effect = "Allow"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem"
    ]

    resources = [var.correlation_state_table_arn]
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

resource "aws_iam_policy" "agentcore_invoker_policy" {
  name   = "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-invoker"
  policy = data.aws_iam_policy_document.agentcore_invoker_policy_document.json
}

resource "aws_iam_role_policy_attachment" "agentcore_invoker_policy_attachment" {
  role       = aws_iam_role.agentcore_invoker_role.name
  policy_arn = aws_iam_policy.agentcore_invoker_policy.arn
}

resource "aws_lambda_function" "invoke_agentcore_reasoner" {
  function_name                  = "${var.organization_name}-${var.environment_name}-${var.platform_name}-agentcore-invoker"
  role                           = aws_iam_role.agentcore_invoker_role.arn
  filename                       = var.lambda_package_path_invoker
  source_code_hash               = var.lambda_package_invoker_source_code_hash
  handler                        = "agentcore_invoker.handler"
  runtime                        = "python3.13"
  timeout                        = 120
  memory_size                    = 512
  kms_key_arn                    = var.findings_kms_key_arn
  reserved_concurrent_executions = var.agentcore_invoker_reserved_concurrency

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      AGENT_RUNTIME_ARN                     = aws_bedrockagentcore_agent_runtime.security_reasoner_runtime.agent_runtime_arn
      AGENT_RUNTIME_ENDPOINT                = aws_bedrockagentcore_agent_runtime_endpoint.security_reasoner_endpoint.agent_runtime_endpoint_arn
      GATEWAY_URL                           = aws_bedrockagentcore_gateway.security_tools_gateway.gateway_url
      CORRELATION_STATE_TABLE               = var.correlation_state_table_name
      AGENTCORE_INVOCATION_COOLDOWN_SECONDS = tostring(var.agentcore_invocation_cooldown_seconds)
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.agentcore_invoker_policy_attachment
  ]
}

data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "daily_digest_scheduler_role" {
  name               = "${var.organization_name}-${var.environment_name}-${var.platform_name}-daily-digest-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json
}

data "aws_iam_policy_document" "daily_digest_scheduler_policy_document" {
  statement {
    sid       = "InvokeAgentCoreDailyDigest"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.invoke_agentcore_reasoner.arn]
  }
}

resource "aws_iam_policy" "daily_digest_scheduler_policy" {
  name   = "${var.organization_name}-${var.environment_name}-${var.platform_name}-daily-digest-scheduler"
  policy = data.aws_iam_policy_document.daily_digest_scheduler_policy_document.json
}

resource "aws_iam_role_policy_attachment" "daily_digest_scheduler_policy_attachment" {
  role       = aws_iam_role.daily_digest_scheduler_role.name
  policy_arn = aws_iam_policy.daily_digest_scheduler_policy.arn
}

resource "aws_scheduler_schedule" "daily_security_digest" {
  name                         = "${var.organization_name}-${var.environment_name}-${var.platform_name}-daily-security-digest"
  description                  = "Invokes AgentCore every morning for a plain-language security digest."
  schedule_expression          = var.daily_digest_schedule_expression
  schedule_expression_timezone = "America/Guatemala"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.invoke_agentcore_reasoner.arn
    role_arn = aws_iam_role.daily_digest_scheduler_role.arn
    input = jsonencode({
      reason = "daily_digest"
    })
  }
}

resource "aws_cloudwatch_event_rule" "invoke_reasoner_on_critical_finding" {
  name           = "${var.organization_name}-${var.environment_name}-${var.platform_name}-critical-finding-reasoner"
  event_bus_name = var.findings_event_bus_name

  event_pattern = jsonencode({
    "detail-type" = ["Normalized Security Finding"]
    detail = {
      severity = ["critical", "CRITICAL"]
      status   = ["open", "OPEN"]
    }
  })
}

resource "aws_cloudwatch_event_target" "critical_finding_reasoner_target" {
  rule           = aws_cloudwatch_event_rule.invoke_reasoner_on_critical_finding.name
  event_bus_name = var.findings_event_bus_name
  target_id      = "invoke-agentcore-reasoner-critical"
  arn            = aws_lambda_function.invoke_agentcore_reasoner.arn
}

resource "aws_cloudwatch_event_rule" "invoke_reasoner_on_high_confidence_finding" {
  name           = "${var.organization_name}-${var.environment_name}-${var.platform_name}-high-confidence-finding-reasoner"
  event_bus_name = var.findings_event_bus_name

  event_pattern = jsonencode({
    "detail-type" = ["Normalized Security Finding"]
    detail = {
      confidence = ["high", "HIGH"]
      status     = ["open", "OPEN"]
    }
  })
}

resource "aws_cloudwatch_event_target" "high_confidence_finding_reasoner_target" {
  rule           = aws_cloudwatch_event_rule.invoke_reasoner_on_high_confidence_finding.name
  event_bus_name = var.findings_event_bus_name
  target_id      = "invoke-agentcore-reasoner-high-confidence"
  arn            = aws_lambda_function.invoke_agentcore_reasoner.arn
}

resource "aws_lambda_permission" "allow_eventbridge_critical_finding_to_invoke_reasoner" {
  statement_id  = "AllowEventBridgeCriticalFindingInvokeReasoner"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.invoke_agentcore_reasoner.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.invoke_reasoner_on_critical_finding.arn
}

resource "aws_lambda_permission" "allow_eventbridge_high_confidence_finding_to_invoke_reasoner" {
  statement_id  = "AllowEventBridgeHighConfidenceFindingInvokeReasoner"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.invoke_agentcore_reasoner.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.invoke_reasoner_on_high_confidence_finding.arn
}
