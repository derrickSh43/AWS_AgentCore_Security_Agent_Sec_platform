from shared import json_response, parse_body, save_normalized_finding


def handler(event, context):
    payload = parse_body(event)
    finding = save_normalized_finding(
        "devops-agent",
        payload,
        severity=payload.get("severity", "medium"),
        confidence=payload.get("confidence", "medium"),
        title=payload.get("title", "AWS DevOps Agent operational context"),
        resource=payload.get("resource") or payload.get("service"),
    )
    return json_response(202, {"finding_id": finding["finding_id"]})
