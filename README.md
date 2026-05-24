<img width="1274" height="875" alt="image" src="https://github.com/derrickSh43/AWS_AgentCore_Security_Agent_Sec_platform/blob/main/Screenshot%202026-05-24%20173604.png" />

## EKS Security Operations Platform — Architecture & Design

A layered, AWS-native security operations platform built around an existing EKS cluster. Deterministic scanners produce normalized findings that feed an AI reasoning layer. The AI can query data, summarize risk, and propose fixes — but every cluster change requires a human-reviewed pull request merged through ArgoCD.


---

## Platform Layers

| Layer | Purpose |
|---|---|
| **Detection** | Multiple scanners covering runtime, posture, code, and infrastructure |
| **Normalization & Enrichment** | Lambdas translate every source into a single finding schema |
| **Findings Pipeline** | Immutable S3 archive, DynamoDB store, EventBridge fan-out |
| **AI Reasoning** | AgentCore runtime correlates findings, prioritizes risk, proposes fixes |
| **GitOps Boundary** | Only path to cluster change — PR → ArgoCD → EKS |
| **Visibility** | DefectDojo dashboard for engineer review |

---

## Detection Sources

### Current Build

| Scanner | What It Covers | How It Feeds In |
|---|---|---|
| **Falco** | Runtime syscall anomalies on EKS nodes | eBPF DaemonSet → Falcosidekick → CloudWatch Logs → Lambda |
| **Prowler** | Cloud posture (CIS, NIST, SOC2 checks) | K8s CronJob every 12 hours → S3 JSON → Lambda |
| **Snyk** | Code vulnerabilities and IaC misconfigs | GitHub Webhook → API Gateway → Lambda |
| **AWS Security Agent** | Automated pen-testing of the environment | Weekly EventBridge Schedule → Lambda → AWS Security Agent API |
| **AWS DevOps Agent** | Operational context (deployments, incidents) | EventBridge rule on default bus → Lambda |

### Future Additions

| Scanner | What It Covers | How It Feeds In |
|---|---|---|
| **Trivy / ECR** | Container image CVEs at registry level, before deploy | ECR push event → Lambda or CI pipeline step |
| **EBS Snapshot Scan** | Agentless node-level scanning without agent install | Scheduled snapshot → scan job → Lambda normalizer |

---

## Normalization & Enrichment

Every scanner output passes through a dedicated **Normalizer Lambda** that:

1. Validates and parses the raw payload
2. Archives the original payload to S3 (`{source}/{date}/{finding-id}.json`)
3. Writes a normalized record to DynamoDB using a stable `finding_id` derived from a SHA-256 of the source + key fields
4. Publishes a `Normalized Security Finding` event to the custom EventBridge bus
5. Pushes the finding to DefectDojo via the import-scan API

**Normalized finding schema:**

```json
{
  "finding_id": "snyk-a3f8c2d1e9b047",
  "source": "snyk",
  "status": "open",
  "severity": "high",
  "confidence": "high",
  "title": "SQL Injection in query builder",
  "resource": "app/db/query.py",
  "first_seen_epoch": 1716500000,
  "last_seen_epoch": 1716500000,
  "raw": { ...original payload... }
}
```

### Future Enrichment

| Component | What It Adds |
|---|---|
| **CVE Watch Lambda** | Pulls CISA KEV and NVD feeds daily, writes active exploits to a separate DynamoDB table so the AI can cross-reference findings against known-exploited CVEs |
| **Cartography** | Builds an IAM and Kubernetes identity graph (Neo4j or Neptune), enabling blast-radius queries — "if this role is compromised, what can it reach?" |

---

## Findings Pipeline

```
Raw Payload  ──►  S3 Archive (KMS, 1yr retention, immutable)
                        │
Normalized   ──►  DynamoDB (normalized_findings)
Record              KMS encrypted · PITR enabled
                        │
                  EventBridge (custom security bus)
                    ├── Critical/High findings → AgentCore Invoker
                    ├── Daily 8AM schedule → AgentCore Invoker
                    └── Failed events → SQS Dead Letter Queue
```

**Future pipeline additions:**

- `cve_watchlist` DynamoDB table — active exploit feed for AI cross-referencing
- Neo4j / Neptune graph database — identity blast-radius paths fed by Cartography

---

## AI Reasoning Layer

The reasoning layer is event-driven and read-only by default. It does not modify infrastructure.

```
EventBridge (critical/high finding or 8AM schedule)
    │
    ▼
AgentCore Invoker Lambda
  – Queries DynamoDB for all open critical + high findings
  – Packages top 25 with count and context
    │
    ▼
AgentCore Reasoning Runtime (container on EKS)
  – LLM-powered reasoning
  – Correlates findings across all detection sources
  – Prioritizes by severity, confidence, and exploit availability
  – Proposes remediation steps
    │
    ▼
AgentCore MCP Gateway (AWS IAM authenticated)
  – Exposes tool Lambdas to the agent via MCP protocol
```

### MCP Tool Lambdas

| Tool | What It Returns |
|---|---|
| `query_falco` | Open runtime findings from DynamoDB |
| `query_prowler` | Open posture findings from DynamoDB |
| `query_snyk` | Open code/IaC findings from DynamoDB |
| `query_security_agent` | Pen-test results from DynamoDB |
| `query_devops` | Operational context from DynamoDB |
| `daily_digest` | AI-generated prioritized summary |
| `open_remediation_pr` | Proposes a fix via GitHub pull request |
| `query_cve_watchlist` *(future)* | Active exploits from CISA KEV / NVD |
| `query_identity_graph` *(future)* | IAM blast radius from Cartography graph |

> The agent reasons and proposes. It cannot merge or deploy. Every remediation requires a human-approved PR.

---

## GitOps Boundary

The only path to a cluster change:

```
AI proposes PR
    │
    ▼
Pull Request (GitHub)
  – Human code owner review required
  – Branch protection enforced
  – Dismiss stale reviews on push
    │
    ▼
ArgoCD (manual sync by default)
  – Watches the Git repository
  – Applies desired state only from approved commits
    │
    ▼
EKS Cluster
  – State reflects only what is in Git
  – No out-of-band changes
```

This boundary means the AI layer has no write path to the cluster. The worst outcome of a compromised agent is a pull request that a human must approve.

---

## Visibility

| Component | Role |
|---|---|
| **DefectDojo** | Security dashboard deployed on EKS via Helm. All normalized findings are imported via the DefectDojo scan API. Engineers triage, track, and close findings here. |
| **Splunk / Datadog** *(future)* | SIEM integration via DynamoDB Streams + EventBridge forwarding. Enables compliance report generation, custom alert rules, and long-term retention beyond DynamoDB TTL. |

---

## Data Flow — End to End

### Stage 1 — Detection

Scanners run on their own schedules and trigger mechanisms:

- **Falco** continuously monitors syscalls via eBPF; anomalous events are sent by Falcosidekick to a CloudWatch log group
- **Prowler** runs a K8s CronJob every 12 hours and writes JSON results to S3
- **Snyk** receives a GitHub webhook on every pull request and code_scanning_alert event
- **AWS Security Agent** runs a full pen-test weekly on Monday at 8AM via EventBridge Scheduler
- **AWS DevOps Agent** emits operational events to the default EventBridge bus

### Stage 2 — Normalization

Each source has a dedicated Lambda normalizer that:
- Extracts the relevant fields
- Generates a stable `finding_id` (SHA-256 of source + key fields, deterministic across re-ingestions)
- Writes the normalized record to DynamoDB
- Archives the full raw payload to S3
- Publishes a `Normalized Security Finding` event to the custom EventBridge bus
- Pushes the finding to DefectDojo for dashboard visibility

### Stage 3 — Pipeline Storage

Normalized findings land in three places simultaneously:
- **S3** — immutable raw archive for audit and replay
- **DynamoDB** — live queryable store with GSIs on source, status, and severity
- **EventBridge** — real-time event stream that drives the AI reasoning layer and future SIEM forwarding

### Stage 4 — AI Reasoning

Two triggers activate the AgentCore Invoker Lambda:
1. A critical or high-severity finding arrives on EventBridge
2. The daily 8AM EventBridge Scheduler rule fires

The Invoker queries DynamoDB for all open critical and high findings, packages the top 25 with a count summary, and invokes the AgentCore Reasoning Runtime. The runtime uses its MCP tool Lambdas to query each detection source directly, builds cross-source correlation, and produces a prioritized analysis with proposed remediation steps.

### Stage 5 — Action & Visibility

- **High-priority findings** surface immediately in DefectDojo for engineer triage
- **AI proposals** take the form of pull requests opened by the `open_remediation_pr` tool
- **Daily digest** summarizes the security posture across all sources at 8AM
- **All findings** are available for export to Splunk or Datadog via DynamoDB Streams (future)

---

## Future Additions

### CVE Watchlist

**What:** A Lambda that pulls the CISA Known Exploited Vulnerabilities (KEV) catalog and NVD feed on a daily schedule, writing active CVEs to a dedicated DynamoDB table. The `query_cve_watchlist` MCP tool lets the AI agent cross-reference open findings against the watchlist to surface findings with known active exploits.

**Impact:** Closes the gap between "this is a finding" and "this is being actively exploited in the wild right now" — the distinction that drives real prioritization decisions.

### Cartography — Identity Graph

**What:** An open-source tool (by Lyft) that maps IAM roles, Kubernetes service accounts, EC2 instances, S3 buckets, and more into a graph database (Neo4j or Neptune). A K8s CronJob runs Cartography on a schedule. The `query_identity_graph` MCP tool exposes blast-radius queries to the AI agent.

**Impact:** Answers "if this pod's service account is compromised, what AWS resources can it reach?" — the lateral movement question that flat findings lists cannot answer.

### Trivy / ECR Image Scanning

**What:** Trivy scans container images at push time (ECR event-driven) and optionally in the CI pipeline before they ever reach the registry. A Lambda normalizer ingests scan results into the same findings pipeline.

**Impact:** Catches CVEs at the registry level — before the image can be deployed — rather than after it's running on a node.

### EBS Snapshot Agentless Scanning

**What:** Snapshot-based node scanning without installing any agent on the node. A scheduled job creates EBS snapshots, mounts them read-only, runs a vulnerability scanner against the filesystem, and normalizes results through the Lambda pipeline.

**Impact:** Covers nodes where eBPF-based runtime agents cannot run, and gives filesystem-level visibility (installed packages, secrets on disk) that syscall monitoring cannot provide.

### Splunk / Datadog SIEM

**What:** DynamoDB Streams forward all finding writes to a Lambda that publishes to EventBridge. A forwarding rule sends events to Splunk HEC or Datadog API. Custom dashboards and alert rules can be built on top of the normalized finding schema.

**Impact:** Long-term retention, compliance report generation (SOC2, PCI, CIS), and integration with existing SOC tooling and on-call workflows.

---

## Comparison: This Platform vs. Wiz vs. Tenable

### Capability Coverage

| Capability | This Platform | Wiz | Tenable |
|---|:---:|:---:|:---:|
| Runtime threat detection (eBPF) | ✅ Falco | ✅ | ❌ |
| Cloud posture / CSPM | ✅ Prowler | ✅ | ✅ |
| Code & IaC vulnerability scanning | ✅ Snyk | ✅ | ⚠️ add-on |
| Automated pen-testing | ✅ AWS Security Agent | ❌ | ✅ Tenable.io |
| AI-driven findings correlation | ✅ AgentCore | ✅ Wiz AI | ⚠️ limited |
| Container image scanning | ⚠️ future (Trivy) | ✅ | ✅ |
| Agentless node scanning | ⚠️ future (EBS) | ✅ | ✅ |
| Identity / blast-radius graph | ⚠️ future (Cartography) | ✅ | ❌ |
| CVE watchlist (CISA KEV) | ⚠️ future | ✅ | ✅ |
| SIEM integration | ⚠️ future | ✅ | ✅ |
| GitOps remediation guardrails | ✅ ArgoCD | ❌ | ❌ |
| Deterministic normalized findings | ✅ | ⚠️ proprietary | ⚠️ proprietary |
| AWS-native IAM / shared responsibility | ✅ | ❌ | ❌ |

### Where Each Tool Leads

| Dimension | This Platform | Wiz | Tenable |
|---|---|---|---|
| **Depth** | Configurable, open schemas, all data owned by you | Deep proprietary graph, fully managed | Deep vuln scanning, mature agent ecosystem |
| **AI reasoning** | AWS AgentCore — improving as models improve | Purpose-built Wiz AI | Limited, early-stage |
| **Compliance reports** | Needs SIEM layer (future) | Out of the box | Out of the box — auditor recognized |
| **Operational overhead** | Moderate — you manage the pipeline | Low — SaaS | Low — SaaS |
| **Data ownership** | Full — your AWS account, your KMS keys | Wiz holds scan data | Tenable holds scan data |
| **Cost at 10 clusters (est.)** | $150–325/month | $60,000–120,000/year | $50,000–155,000/year |
| **Customization** | Full — open Terraform, open Lambda | Limited — vendor controls schema | Limited — vendor controls schema |

### Honest Assessment

**This platform wins when:**
- You want data ownership and full control over the findings schema
- You want AWS-native shared responsibility (AWS Security Agent and DevOps Agent are AWS-managed services)
- You believe model quality will continue improving, making the AI reasoning layer more valuable over time
- Budget is a real constraint — you get 80% of the coverage at 1–2% of the commercial cost
- You need GitOps remediation guardrails that commercial tools do not provide

**Commercial tools win when:**
- You need auditor-recognized compliance reports out of the box (SOC2, PCI, ISO27001)
- You need a full-time security team to delegate platform maintenance to a vendor
- You need deep proprietary threat intelligence not available through public feeds
- Your org cannot maintain Terraform infrastructure and Lambda functions long-term

**The gap closes with:**
- CVE watchlist → active exploit prioritization on par with commercial intel feeds
- Cartography → identity graph closes the blast-radius gap with Wiz
- Trivy/ECR → image scanning closes the registry-level CVE gap
- EBS scanning → agentless node coverage closes the last major posture gap
- Splunk/Datadog → compliance reports close the auditor gap

> The core argument: deterministic normalized findings running through open infrastructure, reasoned on by a model that improves every few months, owned entirely in your AWS account — that is a defensible architecture that gets materially better without you changing the platform.
