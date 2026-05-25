from shared import json_response, parse_body, query_findings


def query_falco(event, context):
    payload = parse_body(event)
    return json_response(200, {"findings": query_findings("falco", payload.get("status", "open"))})


def query_prowler(event, context):
    payload = parse_body(event)
    return json_response(200, {"findings": query_findings("prowler", payload.get("status", "open"))})


def query_snyk(event, context):
    payload = parse_body(event)
    return json_response(200, {"findings": query_findings("snyk", payload.get("status", "open"))})


def query_security_agent(event, context):
    payload = parse_body(event)
    return json_response(200, {"findings": query_findings("security-agent", payload.get("status", "open"))})


def query_devops_incidents(event, context):
    payload = parse_body(event)
    return json_response(200, {"findings": query_findings("devops-agent", payload.get("status", "open"))})


def create_daily_digest(event, context):
    findings = query_findings(status="open", limit=500)
    severity_order = {"critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4}
    findings.sort(key=lambda item: severity_order.get(item.get("severity", "medium"), 2))
    digest = {
        "open_count": len(findings),
        "top_findings": findings[:25],
        "message": "Open findings are sorted by severity. Resolved findings are excluded.",
    }
    return json_response(200, digest)


def open_remediation_pull_request(event, context):
    payload = parse_body(event)
    return json_response(
        202,
        {
            "finding_id": payload.get("finding_id"),
            "status": "proposal_recorded",
            "message": "PR creation hook is present. Add GitHub App credentials before allowing automated PR creation.",
        },
    )
