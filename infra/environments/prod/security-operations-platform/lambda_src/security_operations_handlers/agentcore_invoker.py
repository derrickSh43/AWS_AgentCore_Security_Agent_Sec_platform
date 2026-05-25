import os

from botocore.exceptions import ClientError

from shared import dynamodb, invoke_agentcore_runtime, json_response, now_epoch, query_findings


def _cooldown_key(event):
    detail = event.get("detail") or {}
    finding_id = detail.get("finding_id") or detail.get("id")
    source = detail.get("source") or event.get("source") or "unknown"
    if finding_id:
        return f"agentcore-invocation:{source}:{finding_id}"
    reason = event.get("reason")
    if reason:
        return f"agentcore-invocation:reason:{reason}"
    return None


def _claim_invocation_window(event):
    if event.get("reason") == "daily_digest":
        return True
    table_name = os.environ.get("CORRELATION_STATE_TABLE")
    correlation_id = _cooldown_key(event)
    if not table_name or not correlation_id:
        return True

    now = now_epoch()
    cooldown = int(os.environ.get("AGENTCORE_INVOCATION_COOLDOWN_SECONDS", "300"))
    table = dynamodb.Table(table_name)
    try:
        table.update_item(
            Key={"correlation_id": correlation_id},
            UpdateExpression="SET updated_epoch = :now, #status = :status",
            ConditionExpression="attribute_not_exists(updated_epoch) OR updated_epoch < :cutoff",
            ExpressionAttributeNames={"#status": "status"},
            ExpressionAttributeValues={
                ":now": now,
                ":cutoff": now - cooldown,
                ":status": "agentcore_invocation_claimed",
            },
        )
        return True
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
            return False
        raise


def handler(event, context):
    if not _claim_invocation_window(event):
        return json_response(202, {"invoked_agentcore": False, "reason": "cooldown_active"})

    critical = [
        item for item in query_findings(status="open", limit=500)
        if item.get("severity") in ("critical", "high")
    ]
    payload = {
        "reason": event.get("reason", "event"),
        "event": event,
        "critical_or_high_open_findings": len(critical),
        "findings": critical[:25],
    }
    agent_response = invoke_agentcore_runtime(
        os.environ["AGENT_RUNTIME_ARN"],
        payload,
        os.environ.get("AWS_REGION", "us-east-1"),
    )
    return json_response(
        200,
        {
            "invoked_agentcore": True,
            "agent_response": agent_response,
            "input_summary": {
                "reason": payload["reason"],
                "critical_or_high_open_findings": payload["critical_or_high_open_findings"],
            },
        },
    )
