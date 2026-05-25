import os

from shared import json_response, parse_body, save_normalized_finding, start_security_agent_pentest


def start_weekly_pentest(event, context):
    agent_space_id = os.environ["SECURITY_AGENT_SPACE_ID"]
    pentest_id = os.environ["SECURITY_AGENT_PENTEST_ID"]
    response = start_security_agent_pentest(
        agent_space_id,
        pentest_id,
        os.environ.get("AWS_REGION", "us-east-1"),
    )
    return json_response(
        202,
        {
            "status": response.get("status", "STARTED"),
            "pentest_id": response.get("pentestId", pentest_id),
            "pentest_job_id": response.get("pentestJobId"),
        },
    )


def ingest_findings(event, context):
    payload = parse_body(event)
    finding = save_normalized_finding(
        "security-agent",
        payload,
        severity=payload.get("severity", "high"),
        confidence=payload.get("confidence", "high"),
        title=payload.get("title", "AWS Security Agent finding"),
        resource=payload.get("target") or payload.get("resource"),
    )
    return json_response(202, {"finding_id": finding["finding_id"]})
