import base64
import gzip
import hashlib
import json
import os
import time
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from urllib import request
from urllib.parse import quote

import boto3
from boto3.dynamodb.conditions import Attr
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest


dynamodb = boto3.resource("dynamodb")
events = boto3.client("events")
s3 = boto3.client("s3")
secretsmanager = boto3.client("secretsmanager")
session = boto3.Session()
_secret_cache = {}


def _json_default(value):
    if isinstance(value, Decimal):
        if value % 1 == 0:
            return int(value)
        return float(value)
    return str(value)


def json_response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body, default=_json_default),
    }


def parse_body(event):
    body = event.get("body")
    if body is None:
        return event
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode("utf-8")
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        return {"raw_body": body}


def raw_event_body(event):
    body = event.get("body") or ""
    if event.get("isBase64Encoded"):
        return base64.b64decode(body)
    return body.encode("utf-8")


def secret_config_value(name, default=""):
    secret_id = os.environ.get(f"{name}_SECRET_ARN")
    if not secret_id:
        return os.environ.get(name, default)
    if secret_id not in _secret_cache:
        response = secretsmanager.get_secret_value(SecretId=secret_id)
        if "SecretString" in response:
            _secret_cache[secret_id] = response["SecretString"]
        else:
            _secret_cache[secret_id] = base64.b64decode(response["SecretBinary"]).decode("utf-8")
    value = _secret_cache[secret_id]
    if value == "__UNCONFIGURED__":
        return default
    return value


def cloudwatch_logs_payload(event):
    compressed = base64.b64decode(event["awslogs"]["data"])
    return json.loads(gzip.decompress(compressed).decode("utf-8"))


def _first_payload_value(payload, keys):
    for key in keys:
        value = payload.get(key)
        if value not in (None, ""):
            return value
    return None


def _stable_identity_payload(source, payload):
    if source != "prowler":
        return payload

    identity = {
        "check_id": _first_payload_value(payload, ("CheckID", "CheckId", "check_id", "check_uid", "ControlId")),
        "resource": _first_payload_value(payload, ("ResourceId", "ResourceUid", "resource_uid", "resource_id", "resource")),
        "account": _first_payload_value(payload, ("AwsAccountId", "AccountId", "account_id", "account")),
        "region": _first_payload_value(payload, ("Region", "region")),
    }
    if identity["check_id"] and identity["resource"]:
        return identity
    return payload


def stable_finding_id(source, payload):
    key = json.dumps(_stable_identity_payload(source, payload), sort_keys=True, default=str)
    digest = hashlib.sha256(f"{source}:{key}".encode("utf-8")).hexdigest()
    return f"{source}-{digest[:24]}"


def now_epoch():
    return int(time.time())


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def normalize_record(source, payload, severity="medium", confidence="medium", title=None, resource=None):
    finding_id = payload.get("finding_id") or payload.get("id") or stable_finding_id(source, payload)
    return {
        "finding_id": str(finding_id),
        "source": source,
        "status": "open",
        "severity": str(severity).lower(),
        "confidence": str(payload.get("confidence", confidence)).lower(),
        "title": str(title or payload.get("title") or payload.get("rule") or payload.get("check_id") or "Security finding"),
        "resource": str(resource or payload.get("resource") or payload.get("resource_id") or payload.get("hostname") or "unknown"),
        "first_seen_epoch": int(payload.get("first_seen_epoch", now_epoch())),
        "last_seen_epoch": int(payload.get("last_seen_epoch", now_epoch())),
        "raw": payload,
    }


def put_finding(record):
    table_name = os.environ["NORMALIZED_FINDINGS_TABLE"]
    table = dynamodb.Table(table_name)
    table.put_item(Item=record)
    return record


def publish_finding(record):
    bus_name = os.environ.get("FINDINGS_EVENT_BUS_NAME")
    if not bus_name:
        return
    events.put_events(
        Entries=[
            {
                "Source": f"eks-secops.{record['source']}",
                "DetailType": "Normalized Security Finding",
                "EventBusName": bus_name,
                "Detail": json.dumps(record, default=_json_default),
            }
        ]
    )


def archive_payload(source, payload):
    bucket = os.environ.get("RAW_FINDINGS_ARCHIVE_BUCKET")
    if not bucket:
        return None
    key = f"{source}/{datetime.now(timezone.utc).strftime('%Y/%m/%d/%H%M%S')}-{stable_finding_id(source, payload)}.json"
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(payload, default=_json_default).encode("utf-8"),
        ContentType="application/json",
    )
    return key


def save_normalized_finding(source, payload, severity="medium", confidence="medium", title=None, resource=None):
    archive_payload(source, payload)
    record = normalize_record(source, payload, severity=severity, confidence=confidence, title=title, resource=resource)
    put_finding(record)
    publish_finding(record)
    post_defectdojo_import(source, record["title"], record)
    return record


def query_findings(source=None, status="open", limit=100):
    table = dynamodb.Table(os.environ["NORMALIZED_FINDINGS_TABLE"])
    items = []
    scan_kwargs = {}
    filters = []
    if source:
        filters.append(Attr("source").eq(source))
    if status:
        filters.append(Attr("status").eq(status))
    if filters:
        expression = filters[0]
        for filter_expression in filters[1:]:
            expression = expression & filter_expression
        scan_kwargs["FilterExpression"] = expression
    while True:
        response = table.scan(**scan_kwargs)
        items.extend(response.get("Items", []))
        if len(items) >= limit:
            return items[:limit]
        last_key = response.get("LastEvaluatedKey")
        if not last_key:
            return items
        scan_kwargs["ExclusiveStartKey"] = last_key
    return items


def post_defectdojo_import(scan_type, title, payload):
    defectdojo_url = os.environ.get("DEFECTDOJO_URL")
    defectdojo_token = secret_config_value("DEFECTDOJO_API_TOKEN")
    if not defectdojo_url or not defectdojo_token:
        return None
    boundary = f"----eks-secops-{uuid.uuid4().hex}"
    fields = {
        "scan_type": "Generic Findings Import",
        "minimum_severity": "Info",
        "active": "true",
        "verified": "false",
        "scan_date": now_iso().split("T")[0],
        "engagement": os.environ.get("DEFECTDOJO_ENGAGEMENT_ID", ""),
        "lead": os.environ.get("DEFECTDOJO_LEAD_ID", ""),
        "tags": "eks-secops",
        "title": title,
    }
    body_parts = []
    for name, value in fields.items():
        if value:
            sanitized_value = str(value).replace("\r", " ").replace("\n", " ")
            body_parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{sanitized_value}\r\n")
    finding_json = json.dumps(payload, default=_json_default)
    body_parts.append(
        f"--{boundary}\r\n"
        "Content-Disposition: form-data; name=\"file\"; filename=\"finding.json\"\r\n"
        "Content-Type: application/json\r\n\r\n"
        f"{finding_json}\r\n"
        f"--{boundary}--\r\n"
    )
    data = "".join(body_parts).encode("utf-8")
    req = request.Request(
        f"{defectdojo_url.rstrip('/')}/api/v2/import-scan/",
        data=data,
        headers={
            "Authorization": f"Token {defectdojo_token}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
        method="POST",
    )
    try:
        with request.urlopen(req, timeout=10) as response:
            return response.status
    except Exception as exc:
        print(f"DefectDojo import failed: {type(exc).__name__}")
        return None


def signed_json_request(service, region, method, url, payload, headers=None):
    credentials = session.get_credentials()
    if credentials is None:
        raise RuntimeError("No AWS credentials available for SigV4 request")
    body = json.dumps(payload, default=_json_default).encode("utf-8")
    request_headers = {"content-type": "application/json", "accept": "application/json"}
    request_headers.update(headers or {})
    aws_request = AWSRequest(method=method, url=url, data=body, headers=request_headers)
    SigV4Auth(credentials, service, region).add_auth(aws_request)
    signed_headers = dict(aws_request.headers.items())
    http_request = request.Request(url, data=body, headers=signed_headers, method=method)
    with request.urlopen(http_request, timeout=60) as response:
        raw_body = response.read().decode("utf-8")
        if not raw_body:
            return {"statusCode": response.status}
        try:
            return json.loads(raw_body)
        except json.JSONDecodeError:
            return {"statusCode": response.status, "body": raw_body}


def invoke_agentcore_runtime(agent_runtime_arn, payload, region, qualifier=None):
    encoded_arn = quote(agent_runtime_arn, safe="")
    url = f"https://bedrock-agentcore.{region}.amazonaws.com/runtimes/{encoded_arn}/invocations"
    if qualifier:
        url = f"{url}?qualifier={quote(qualifier, safe='')}"
    runtime_session_id = f"session-{uuid.uuid4().hex}"
    headers = {
        "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id": runtime_session_id,
        "content-type": "application/json",
        "accept": "application/json",
    }
    try:
        client = boto3.client("bedrock-agentcore", region_name=region)
        response = client.invoke_agent_runtime(
            agentRuntimeArn=agent_runtime_arn,
            runtimeSessionId=runtime_session_id,
            payload=json.dumps(payload, default=_json_default).encode("utf-8"),
        )
        response_body = response.get("response")
        if hasattr(response_body, "read"):
            raw_body = response_body.read().decode("utf-8")
            try:
                return json.loads(raw_body)
            except json.JSONDecodeError:
                return {"body": raw_body}
        return response
    except Exception as exc:
        print(f"SDK AgentCore invocation unavailable, falling back to signed HTTPS: {type(exc).__name__}")
        return signed_json_request("bedrock-agentcore", region, "POST", url, payload, headers=headers)


def start_security_agent_pentest(agent_space_id, pentest_id, region):
    payload = {"agentSpaceId": agent_space_id, "pentestId": pentest_id}
    try:
        client = boto3.client("securityagent", region_name=region)
        return client.start_pentest_job(**payload)
    except Exception as exc:
        print(f"SDK Security Agent invocation unavailable, falling back to signed HTTPS: {type(exc).__name__}")
        url = f"https://securityagent.{region}.amazonaws.com/StartPentestJob"
        return signed_json_request("securityagent", region, "POST", url, payload)
