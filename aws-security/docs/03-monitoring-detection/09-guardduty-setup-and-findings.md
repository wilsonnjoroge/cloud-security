# 🛡️ GuardDuty: Threat Detection & Findings

> **Phase 2 · Document 9 of 29**  
> **Estimated cost:** ~$1–3/month · **Estimated time:** 60 minutes  
> **Prerequisites:** All Phase 1 documents complete

---

## What Is GuardDuty?

GuardDuty is AWS's intelligent threat detection service. It continuously analyzes CloudTrail logs, VPC Flow Logs, and DNS logs: without you having to set up any of that manually: and uses machine learning to surface real threats.

```
CloudTrail events  ─┐
VPC Flow Logs      ─┼─→ GuardDuty ML engine → Findings → Alerts
DNS query logs     ─┘
```

> **Think of it as:** A SOC analyst that never sleeps, watching every API call and network connection across your entire account, 24/7.

---

## GuardDuty Finding Categories

| Category | What it detects |
|----------|----------------|
| **Backdoor** | EC2 instance communicating with known C2 servers |
| **Behavior** | Unusual API activity, impossible travel |
| **CryptoCurrency** | Mining pool connections from EC2 |
| **Discovery** | Reconnaissance: port scanning, credential enumeration |
| **Exfiltration** | Unusual S3 data access patterns |
| **Impact** | Resource hijacking, data destruction |
| **Initial Access** | Tor exit nodes, unusual login locations |
| **Persistence** | New IAM user creation, policy changes after compromise |
| **Privilege Escalation** | IAM role assumption chains, policy modifications |
| **Stealth** | CloudTrail disabled, password policy weakened |
| **Trojan** | DNS requests to known malicious domains |
| **UnauthorizedAccess** | SSH brute force, API calls from unusual geo-locations |

---

## Step 1: Enable GuardDuty

**Console path:** `GuardDuty → Get started → Enable GuardDuty`

That's it. No agents, no configuration, no log routing needed.

GuardDuty immediately begins:
- Pulling CloudTrail management events
- Analyzing VPC Flow Logs
- Monitoring DNS resolution logs

> GuardDuty has a **30-day free trial**. After that, cost is based on volume of data analyzed. For a lab account: ~$1–3/month.

### Enable additional protection plans

```
GuardDuty → Settings → Protection plans
```

| Plan | What it adds | Enable? |
|------|-------------|---------|
| S3 Protection | Detects malicious S3 access patterns | Yes |
| EKS Protection | Kubernetes threat detection | Optional |
| Malware Protection | Scans EBS volumes for malware | Yes |
| Lambda Protection | Detects compromised Lambda functions | Yes |
| RDS Protection | Anomalous RDS login attempts | Yes |

---

## Step 2: Generate Sample Findings

GuardDuty comes with a built-in sample findings generator: creates one of every finding type so you can see what real alerts look like.

```
GuardDuty → Settings → Sample findings → Generate sample findings
```

Browse through the findings. For each one, note:

| Field | What it tells you |
|-------|-----------------|
| Finding type | Category and technique (e.g. `UnauthorizedAccess:EC2/SSHBruteForce`) |
| Severity | Low (1–3.9), Medium (4–6.9), High (7–8.9), Critical (9–10) |
| Resource affected | Which EC2, IAM user, S3 bucket etc. |
| Action | What happened |
| Actor | Source IP, ASN, geolocation |
| Count | How many times this was observed |

> Focus on **High** and **Critical** findings in a real environment. Medium findings are worth triaging weekly. Low findings are informational.

---

## Step 3: Understand Key Findings in Depth

### Finding: `UnauthorizedAccess:EC2/SSHBruteForce`

```
Severity: Medium
Meaning:  An external IP is making repeated SSH login attempts to your EC2 instance
Response: Check if any logins succeeded → review /var/log/secure
          Block the source IP in the security group or NACL
          If login succeeded: full incident response (see Phase 3)
```

### Finding: `Stealth:IAMUser/CloudTrailLoggingDisabled`

```
Severity: High
Meaning:  Someone disabled your CloudTrail trail
Response: IMMEDIATE: assume compromise
          Re-enable CloudTrail first
          Pull any remaining logs from before it was disabled
          Find who disabled it → investigate that identity
```

### Finding: `CryptoCurrency:EC2/BitcoinTool.B`

```
Severity: High
Meaning:  Your EC2 instance is connecting to a cryptocurrency mining pool
Response: Isolate the instance (remove from security group)
          Take EBS snapshot for forensics
          Investigate how the instance was compromised
          Check for IAM credential exposure
```

### Finding: `Exfiltration:S3/AnomalousBehavior`

```
Severity: High
Meaning:  An IAM identity is accessing S3 data in an unusual pattern
Response: Identify which IAM identity
          Disable/revoke the credentials immediately
          Check what data was accessed (S3 server access logs)
          Determine if data was downloaded (CloudTrail GetObject events)
```

### Finding: `Persistence:IAMUser/UserPermissions`

```
Severity: Medium
Meaning:  IAM permissions were modified: new policies attached, new users created
Response: Review the change: was it authorized?
          If unauthorized: this is an attacker establishing persistence
          Revert the changes, rotate all credentials
```

---

## Step 4: Set Up Automated Alerts

Connect GuardDuty findings to SNS so you get emails on critical findings.

**Console path:** `EventBridge → Rules → Create rule`

```
Rule name:    guardduty-high-severity-alert
Event source: AWS events

Event pattern:
{
  "source": ["aws.guardduty"],
  "detail-type": ["GuardDuty Finding"],
  "detail": {
    "severity": [{ "numeric": [">=", 7] }]
  }
}

Target: SNS topic → lab-security-alerts
```

Now any GuardDuty finding with severity 7 or above sends you an immediate email.

---

## Step 5: Suppress Low-Value Findings

Some findings will fire repeatedly for expected behavior (e.g. your own IP testing things). Suppress them to reduce noise.

```
GuardDuty → Findings → select a finding → Actions → Add suppression rule
```

Create a suppression rule that filters:
- Finding type = the specific finding
- Resource = your known test instance

> Suppression is like a whitelist for false positives. Be conservative: only suppress findings you have fully investigated and confirmed as benign.

---

## Step 6: GuardDuty with Multiple Accounts (Delegated Admin)

In an enterprise environment, GuardDuty aggregates findings from all accounts into a central security account.

```
Organization management account:
  GuardDuty → Settings → Delegate administrator → enter security account ID

Security account:
  GuardDuty → Accounts → Accept all member accounts
```

All findings from all accounts now appear in one place. This is the model used in real SOC environments.

---

## Step 7: Simulate a Real Finding (Safe)

You can test GuardDuty is working by querying a known malicious domain from your EC2 instance. GuardDuty will detect the DNS lookup and generate a finding.

SSH into your instance and run:

```bash
# This domain is reserved by GuardDuty for testing: not actually malicious
curl http://guarddutyc2activityb.com
```

Wait 5–15 minutes. GuardDuty should generate a finding:
`Backdoor:EC2/C&CActivity.B`

This confirms GuardDuty is actively monitoring DNS queries from your instance.

---

## Forensics Response Workflow for GuardDuty Findings

```
Finding received
      │
      ▼
Determine severity (High/Critical → immediate, Medium → same day)
      │
      ▼
Identify affected resource (which EC2, IAM user, S3 bucket)
      │
      ▼
Preserve evidence BEFORE any remediation:
  - EC2: take EBS snapshot, get system log, get screenshot
  - IAM: export credential report
  - S3: export access logs
      │
      ▼
Contain the threat:
  - EC2: isolate (remove from security group / add deny-all NACL)
  - IAM: disable user, revoke sessions, rotate keys
  - S3: apply restrictive bucket policy
      │
      ▼
Investigate root cause (CloudTrail, VPC Flow Logs, system logs)
      │
      ▼
Remediate and restore
      │
      ▼
Document timeline and write incident report
```

---

## Common CLI Commands

```bash
# List all active findings
aws guardduty list-findings \
  --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)

# Get finding details
aws guardduty get-findings \
  --detector-id <detector-id> \
  --finding-ids <finding-id>

# Archive a finding (mark as resolved)
aws guardduty archive-findings \
  --detector-id <detector-id> \
  --finding-ids <finding-id>

# Get your detector ID
aws guardduty list-detectors
```

---

## Phase 2 Progress Tracker

- [x] GuardDuty setup and findings
- [ ] VPC Flow Logs and analysis
- [ ] AWS Config and drift detection
- [ ] Security Hub overview
- [ ] WAF setup
- [ ] KMS encryption basics
- [ ] Secrets Manager

---

*Phase 2 · AWS Cybersecurity & Digital Forensics Roadmap*
