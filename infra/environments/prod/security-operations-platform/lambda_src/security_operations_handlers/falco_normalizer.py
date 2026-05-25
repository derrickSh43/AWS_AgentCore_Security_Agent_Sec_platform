import json

from shared import cloudwatch_logs_payload, save_normalized_finding


def handler(event, context):
    payload = cloudwatch_logs_payload(event)
    records = []
    for log_event in payload.get("logEvents", []):
        message = log_event.get("message", "")
        try:
            finding = json.loads(message)
        except json.JSONDecodeError:
            finding = {"message": message}
        records.append(
            save_normalized_finding(
                "falco",
                finding,
                severity=finding.get("priority", "medium"),
                confidence="high",
                title=finding.get("rule", "Falco runtime alert"),
                resource=finding.get("hostname") or finding.get("output_fields", {}).get("k8s.pod.name"),
            )
        )
    return {"normalized": len(records)}
