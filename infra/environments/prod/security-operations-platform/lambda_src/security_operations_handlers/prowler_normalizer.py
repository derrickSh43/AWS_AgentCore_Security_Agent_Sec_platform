import json

import boto3

from shared import save_normalized_finding


s3 = boto3.client("s3")


def _records(payload):
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        for key in ("Findings", "findings", "Resources", "resources"):
            if isinstance(payload.get(key), list):
                return payload[key]
        return [payload]
    return [{"raw": payload}]


def handler(event, context):
    normalized = 0
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]
        body = s3.get_object(Bucket=bucket, Key=key)["Body"].read().decode("utf-8")
        payload = json.loads(body)
        for finding in _records(payload):
            save_normalized_finding(
                "prowler",
                finding,
                severity=finding.get("Severity", finding.get("severity", "medium")),
                confidence="medium",
                title=finding.get("Title") or finding.get("CheckTitle") or finding.get("check_id") or "Prowler posture finding",
                resource=finding.get("ResourceId") or finding.get("resource_uid") or finding.get("resource_id"),
            )
            normalized += 1
    return {"normalized": normalized}
