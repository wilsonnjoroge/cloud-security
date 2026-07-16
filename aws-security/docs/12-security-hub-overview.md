# 🏠 Security Hub — Centralized Security Posture

> **Phase 2 · Document 12 of 29**  
> **Estimated cost:** ~$1–2/month · **Estimated time:** 45 minutes  
> **Prerequisites:** `09-guardduty-setup-and-findings.md`, `11-aws-config-and-drift-detection.md`

---

## What Is Security Hub?

Security Hub is your central security dashboard for AWS. It aggregates findings from GuardDuty, Config, Inspector, Macie, Firewall Manager, and third-party tools — giving you one place to see your entire security posture instead of checking each service separately.

```
GuardDuty findings ─────┐
AWS Config findings ─────┤
Inspector findings  ─────┼──→ Security Hub ──→ Unified dashboard
Macie findings      ─────┤                 ──→ Compliance scores
3rd party tools     ─────┘                 ──→ Automated response
```

> **SOC relevance:** In a real security operations center, analysts live in Security Hub. It is the single pane of glass that replaces opening 6 different AWS consoles.

---

## Security Hub Core Concepts

| Concept | What it is |
|---------|-----------|
| **Finding** | A security issue from any integrated service |
| **Standard** | A compliance framework with automated checks |
| **Control** | An individual check within a standard |
| **Insight** | A saved query that groups related findings |
| **Integration** | A connected AWS service or third-party tool |

---

## Step 1 — Enable Security Hub

**Console path:** `Security Hub → Go to Security Hub → Enable Security Hub`

On the setup page, enable these standards immediately:

| Standard | What it checks |
|----------|---------------|
| AWS Foundational Security Best Practices | 200+ controls across all AWS services |
| CIS AWS Foundations Benchmark v1.4.0 | CIS-defined hardening controls |
| NIST SP 800-53 Rev 5 | US government security framework |

> Enable all three. They overlap somewhat but each covers different controls. The combined view gives you the most complete picture.

Security Hub automatically begins pulling findings from GuardDuty and Config (if already enabled).

---

## Step 2 — Understand the Security Score

After 30 minutes, Security Hub displays a **Security score** — a percentage representing how many security controls you are passing.

```
Security Hub → Summary → Security score: 47%
```

A fresh account typically scores 40–60%. Your goal through this roadmap is to push it above 85%.

Each failed control shows:
- What the control checks
- Which resources are failing
- Why it matters
- How to remediate

---

## Step 3 — Navigate Findings

**Console path:** `Security Hub → Findings`

Filter findings by:

| Filter | Value | Purpose |
|--------|-------|---------|
| Severity | CRITICAL, HIGH | Focus on what matters most |
| Workflow status | NEW | Unreviewed findings only |
| Record state | ACTIVE | Not yet resolved |
| Product name | GuardDuty | Filter by source service |

### Finding severity levels

| Severity | Score | Meaning | Response time |
|----------|-------|---------|--------------|
| CRITICAL | 90–100 | Immediate risk | Within 1 hour |
| HIGH | 70–89 | Significant risk | Within 24 hours |
| MEDIUM | 40–69 | Risk with conditions | Within 1 week |
| LOW | 1–39 | Minor risk | Monthly review |
| INFORMATIONAL | 0 | No immediate risk | Best effort |

---

## Step 4 — Review CIS Benchmark Controls

The CIS AWS Foundations Benchmark is the industry standard for AWS hardening. Security Hub automates its 50+ checks.

**Console path:** `Security Hub → Security standards → CIS AWS Foundations Benchmark → View results`

### Critical controls to fix first

| Control ID | Check | Common failure reason |
|-----------|-------|----------------------|
| CIS 1.1 | Root account MFA enabled | MFA not set up |
| CIS 1.4 | Access keys not used for root | Keys exist on root account |
| CIS 1.12 | No root account access keys | Root has access keys |
| CIS 2.1 | CloudTrail enabled all regions | Single-region trail only |
| CIS 2.6 | CloudTrail S3 bucket not publicly accessible | Bucket misconfiguration |
| CIS 4.1 | No unrestricted SSH (0.0.0.0/0) | Security group open to all |
| CIS 4.2 | No unrestricted RDP (0.0.0.0/0) | Security group open to all |
| CIS 3.1 | Unauthorized API calls metric filter | CloudWatch alarm missing |

Fix each one, re-evaluate, and watch your score rise.

---

## Step 5 — Create Custom Insights

Insights are saved queries that group findings by a meaningful dimension.

**Console path:** `Security Hub → Insights → Create insight`

### Insight 1 — Critical findings by resource

```
Group by: Resource ID
Filter:   Severity = CRITICAL
          Record state = ACTIVE
Name:     Critical findings by resource
```

### Insight 2 — New findings in last 24 hours

```
Group by: Product name
Filter:   Created at = last 24 hours
          Workflow status = NEW
Name:     New findings today
```

### Insight 3 — Open high-severity IAM findings

```
Group by: Resource type
Filter:   Severity = HIGH
          Resource type = AwsIamUser OR AwsIamRole
          Record state = ACTIVE
Name:     High severity IAM issues
```

---

## Step 6 — Set Up Automated Response with EventBridge

Automatically respond to critical findings:

**Console path:** `EventBridge → Rules → Create rule`

```json
{
  "source": ["aws.securityhub"],
  "detail-type": ["Security Hub Findings - Imported"],
  "detail": {
    "findings": {
      "Severity": { "Label": ["CRITICAL"] },
      "Workflow": { "Status": ["NEW"] }
    }
  }
}
```

Target: SNS topic → immediate email alert

For automated remediation, target a Lambda function instead:

```python
import boto3

def lambda_handler(event, context):
    finding = event['detail']['findings'][0]
    severity = finding['Severity']['Label']
    resource_type = finding['Resources'][0]['Type']
    resource_id = finding['Resources'][0]['Id']
    
    print(f"CRITICAL finding: {finding['Title']}")
    print(f"Resource: {resource_type} - {resource_id}")
    
    # Add automated remediation logic here
    # e.g., isolate EC2, disable IAM user, etc.
```

---

## Step 7 — Integrate AWS Inspector

Inspector scans your EC2 instances and container images for vulnerabilities (CVEs).

```
Security Hub → Integrations → AWS Inspector → Enable
```

Inspector findings now flow into Security Hub. A finding looks like:

```
Title:    CVE-2023-44487 - HTTP/2 Rapid Reset Attack
Severity: HIGH
Resource: EC2 instance i-1234567890abcdef0
Package:  nghttp2-1.41.0-1
Fix:      Update to nghttp2-1.43.0-2
```

> Inspector gives you vulnerability management integrated with your security posture. Critical CVEs on internet-facing instances are HIGH priority — an attacker can exploit these before you patch.

---

## Step 8 — Integrate Macie for Data Classification

Macie discovers and classifies sensitive data in S3 buckets.

```
Security Hub → Integrations → Amazon Macie → Enable
```

Macie scans S3 and flags:
- Credit card numbers (PCI data)
- Social security numbers (PII)
- Passwords and API keys accidentally uploaded
- Medical information (HIPAA data)

> For your forensics work: Macie findings help you identify what was at risk in an S3 breach. If Macie shows credit card data in a bucket that was publicly accessible, you have a data breach requiring regulatory notification.

---

## Step 9 — Workflow Management

Security Hub is only useful if you triage findings systematically.

**Workflow statuses:**

| Status | Meaning | When to use |
|--------|---------|------------|
| NEW | Unreviewed | Default state |
| NOTIFIED | Ticket created | Remediation assigned |
| IN_PROGRESS | Being fixed | Actively working |
| RESOLVED | Fixed | After remediation verified |
| SUPPRESSED | Won't fix / false positive | After investigation confirms benign |

Set up a weekly review cadence:
1. Filter: NEW + CRITICAL/HIGH → triage everything
2. Assign NOTIFIED to findings with tickets
3. Suppress confirmed false positives (with documented justification)
4. Mark RESOLVED after verifying fixes

---

## Security Hub vs Individual Services

| Question | Use |
|----------|-----|
| Is my overall security posture good? | Security Hub score |
| Is a specific EC2 instance being attacked? | GuardDuty |
| Did a security group change yesterday? | AWS Config |
| Who made that change? | CloudTrail |
| Does my instance have unpatched CVEs? | Inspector (via Security Hub) |
| Is there PII in my S3 buckets? | Macie (via Security Hub) |
| What network traffic happened? | VPC Flow Logs |

---

## Common CLI Commands

```bash
# Get all critical findings
aws securityhub get-findings \
  --filters '{"SeverityLabel":[{"Value":"CRITICAL","Comparison":"EQUALS"}]}'

# Update finding workflow status
aws securityhub batch-update-findings \
  --finding-identifiers Id=arn:...,ProductArn=arn:... \
  --workflow '{"Status":"IN_PROGRESS"}'

# Get security score
aws securityhub describe-hub

# List enabled standards
aws securityhub get-enabled-standards
```

---

## Cleanup

```
# Security Hub: ~$0.0010 per finding ingested
# For a small lab with few findings: ~$1-2/month

# To disable (stops all findings):
Security Hub → Settings → General → Disable Security Hub
Note: Disabling deletes all findings — export first if needed
```

---

## Phase 2 Progress Tracker

- [x] GuardDuty setup and findings
- [x] VPC Flow Logs and analysis
- [x] AWS Config and drift detection
- [x] Security Hub overview
- [ ] WAF setup
- [ ] KMS encryption basics
- [ ] Secrets Manager

---

*Phase 2 · AWS Cybersecurity & Digital Forensics Roadmap*
