import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

import boto3


dynamodb = boto3.resource("dynamodb")
MAX_BODY_SIZE_BYTES = 1 * 1024 * 1024


def scan_open_findings():
    table_name = os.environ["NORMALIZED_FINDINGS_TABLE"]
    table = dynamodb.Table(table_name)
    findings = []
    scan_kwargs = {}
    while True:
        response = table.scan(**scan_kwargs)
        findings.extend(item for item in response.get("Items", []) if item.get("status") == "open")
        if len(findings) >= 500:
            return findings[:500]
        last_key = response.get("LastEvaluatedKey")
        if not last_key:
            return findings
        scan_kwargs["ExclusiveStartKey"] = last_key


def build_digest():
    findings = scan_open_findings()
    severity_order = {"critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4}
    findings.sort(key=lambda item: severity_order.get(item.get("severity", "medium"), 2))
    return {
        "open_findings": len(findings),
        "top_findings": findings[:25],
        "attack_chain_candidates": [
            item for item in findings
            if item.get("severity") in ("critical", "high") and item.get("confidence") == "high"
        ][:10],
    }


class ReasonerHandler(BaseHTTPRequestHandler):
    def _send_json(self, status, payload):
        body = json.dumps(payload, default=str).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send_json(200, {"status": "ok"})
            return
        if self.path == "/digest":
            self._send_json(200, build_digest())
            return
        self._send_json(404, {"error": "not found"})

    def do_POST(self):
        length = min(int(self.headers.get("content-length", "0")), MAX_BODY_SIZE_BYTES)
        _ = self.rfile.read(length) if length else b""
        self._send_json(200, build_digest())


def main():
    port = int(os.environ.get("PORT", "8080"))
    server = HTTPServer(("0.0.0.0", port), ReasonerHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
