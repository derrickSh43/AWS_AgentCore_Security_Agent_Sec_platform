import hashlib
import hmac

from shared import json_response, parse_body, raw_event_body, save_normalized_finding, secret_config_value


def _header(event, name):
    wanted = name.lower()
    for key, value in (event.get("headers") or {}).items():
        if key.lower() == wanted:
            return value
    return ""


def _verify_github_signature(event):
    secret = secret_config_value("GITHUB_WEBHOOK_SECRET").encode("utf-8")
    if not secret:
        return
    provided = _header(event, "x-hub-signature-256")
    body = raw_event_body(event)
    expected = "sha256=" + hmac.new(secret, body, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, provided):
        raise PermissionError("Invalid webhook signature")


def handler(event, context):
    try:
        _verify_github_signature(event)
    except PermissionError:
        return json_response(401, {"error": "invalid webhook signature"})
    payload = parse_body(event)
    finding = save_normalized_finding(
        "snyk",
        payload,
        severity=payload.get("severity", "medium"),
        confidence="medium",
        title=payload.get("title") or payload.get("issueTitle") or "Snyk pull request finding",
        resource=payload.get("project") or payload.get("repository") or payload.get("targetFile"),
    )
    return json_response(202, {"finding_id": finding["finding_id"], "status": "accepted"})
