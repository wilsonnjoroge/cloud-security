# AWS Cloud Security Lab — Testing & Validation Methodology
### Cloud Security Operations — Detection & Control Validation Framework

**Document Type:** Executive Methodology Overview
**Environment:** AWS (Educate Free Tier) · EC2 · IAM · VPC · S3 · CloudTrail · CloudWatch · GuardDuty · AWS Config
**Standard:** MITRE ATT&CK for Cloud (ATT&CK Matrix: Enterprise — Cloud) Aligned
**Companion To:** `aws_security_runbook.md` · `README.md`

---

## Overview

This document defines a structured, repeatable methodology for validating security control coverage across an AWS cloud environment. Rather than clicking through the console to "enable" services, this framework maps every control to the threat it mitigates, the event it generates, and a measurable validation outcome.

The goal is not to "turn on security services" — it is to **prove that your controls detect what they claim to detect**, and that your logging pipeline captures evidence of every significant action taken in the account.

Cloud security fails silently. An IAM policy can be misconfigured and appear correct. GuardDuty can be enabled but findings never reach a human. A CloudTrail trail can exist but not cover the region where an attacker operates. This methodology closes every one of those gaps through deliberate, evidence-based validation.

---

## Lab Environment

| Component | Role | Primary Evidence Source |
|---|---|---|
| AWS Account (Educate) | The environment under test | CloudTrail, Billing, Config |
| IAM (Users, Roles, Policies) | Identity & access control layer | CloudTrail API events, IAM Access Analyzer |
| VPC + Security Groups + NACLs | Network control layer | VPC Flow Logs, CloudTrail |
| EC2 Instance (CyberNinja101) | Compute target — application server | CloudWatch agent logs, auth.log, syslog |
| S3 Buckets | Data layer | S3 Access Logs, CloudTrail data events |
| CloudTrail | Immutable audit log | S3 delivery, CloudWatch Logs integration |
| CloudWatch | Alerting pipeline | Metric filters, alarms, SNS notifications |
| GuardDuty | Threat intelligence detection | GuardDuty findings, CloudWatch Events |
| AWS Config | Continuous compliance engine | Config rules, compliance snapshots |
| Kali Linux (local VM) | Validation & attack simulation source | Local terminal output |

---

## Core Testing Philosophy

Cloud security validation is measured across **six control domains**. Every test maps to one of these:

| Domain | What It Covers |
|---|---|
| **Identity & Access** | IAM misconfigurations, over-permissioned policies, credential exposure, privilege escalation |
| **Network Controls** | Security group gaps, exposed ports, public subnet attack surface, NACL bypass |
| **Data Protection** | S3 public access, unencrypted objects, missing versioning, unauthorised access |
| **Audit Integrity** | CloudTrail coverage, log tampering, multi-region gaps, data event blindspots |
| **Active Monitoring** | CloudWatch alarm coverage, SNS pipeline validation, detection latency |
| **Threat Detection** | GuardDuty finding generation, behavioural anomalies, AWS Config drift detection |

---

## Detection Coverage Matrix

### A. Identity & Access Control Validation
**MITRE ATT&CK Cloud:** T1078 (Valid Accounts) · T1098 (Account Manipulation) · T1548 (Abuse Elevation Control)
**Priority:** Critical

| Test Action | Evidence Source | CloudTrail Event | Expected Alert |
|---|---|---|---|
| Root account console login | CloudTrail | `ConsoleLogin` (userIdentity.type = Root) | CloudWatch alarm — RootAccountLogin |
| IAM user creation | CloudTrail | `CreateUser` | CloudWatch alarm — IAMPolicyChange |
| IAM policy attached to user directly | CloudTrail | `AttachUserPolicy` | CloudWatch alarm — IAMPolicyChange |
| Privilege escalation — attach AdministratorAccess | CloudTrail | `AttachUserPolicy` | CloudWatch alarm — IAMPolicyChange |
| Access key created for IAM user | CloudTrail | `CreateAccessKey` | CloudWatch alarm — IAMPolicyChange |
| MFA device deactivated | CloudTrail | `DeactivateMFADevice` | CloudWatch alarm — MFADeactivation |
| Cross-account assume role attempt (unauthorised) | CloudTrail | `AssumeRole` (AccessDenied) | CloudWatch alarm — UnauthorisedAPICall |
| IAM role used from EC2 to access out-of-scope resource | CloudTrail | `GetObject` on restricted bucket (AccessDenied) | CloudWatch alarm — UnauthorisedAPICall |

---

### B. Network Control Validation
**MITRE ATT&CK Cloud:** T1046 (Network Service Scanning) · T1190 (Exploit Public-Facing Application) · T1595 (Active Scanning)
**Priority:** Critical

| Test Action | Evidence Source | Expected Detection |
|---|---|---|
| SSH port scan from Kali against public bastion IP | VPC Flow Logs, GuardDuty | `Recon:EC2/PortProbeUnprotectedPort` |
| SSH brute force against bastion (Hydra) | VPC Flow Logs, GuardDuty | `UnauthorizedAccess:EC2/SSHBruteForce` |
| Security group modified to allow 0.0.0.0/0 on port 22 | CloudTrail, AWS Config | CloudWatch alarm — SecurityGroupChange; Config rule `restricted-ssh` → NON_COMPLIANT |
| Attempt to reach application EC2 directly (no bastion) | VPC Flow Logs | Traffic dropped — no route; Flow log REJECT |
| NACL modified to allow traffic outside defined policy | CloudTrail | CloudWatch alarm — NetworkACLChange |
| Port scan against application EC2 private IP from bastion | VPC Flow Logs | Baseline comparison — confirm no unexpected open ports |

---

### C. Data Protection Validation (S3)
**MITRE ATT&CK Cloud:** T1530 (Data from Cloud Storage) · T1537 (Transfer Data to Cloud Account)
**Priority:** Critical

| Test Action | Evidence Source | Expected Detection |
|---|---|---|
| S3 bucket Block Public Access disabled (intentional misconfiguration) | CloudTrail, AWS Config | Config rule `s3-bucket-public-read-prohibited` → NON_COMPLIANT within 5 minutes |
| Object uploaded without server-side encryption | CloudTrail `PutObject`, AWS Config | Config rule `s3-bucket-server-side-encryption-enabled` → NON_COMPLIANT |
| CloudTrail log bucket read attempt (unauthorised) | CloudTrail `GetObject` (Access Denied) | CloudWatch alarm — UnauthorisedAPICall; access denied in S3 access log |
| Object deletion in versioned bucket | S3 access log, CloudTrail | Delete marker created — object recoverable; versioning confirmed working |
| Bucket policy modified to allow public read | CloudTrail `PutBucketPolicy` | CloudWatch alarm — S3BucketPolicyChange |
| Data exfiltration simulation — `aws s3 cp` of sensitive object to external location | CloudTrail data events | GuardDuty `Discovery:S3/AnomalousBehavior`; S3 access log GET from unexpected principal |

---

### D. Audit Integrity Validation
**MITRE ATT&CK Cloud:** T1562 (Impair Defenses) · T1070 (Indicator Removal)
**Priority:** Critical

| Test Action | Evidence Source | Expected Detection |
|---|---|---|
| CloudTrail trail stopped | CloudTrail `StopLogging` | CloudWatch alarm — CloudTrailChange |
| CloudTrail trail deleted | CloudTrail `DeleteTrail` | CloudWatch alarm — CloudTrailChange |
| CloudTrail log file validation check | CloudTrail `validate-logs` command | Hash chain intact — no tampering detected |
| S3 CloudTrail bucket — attempt to delete log object | S3 bucket policy (explicit deny) | `AccessDenied` — bucket policy enforcement confirmed |
| Confirm multi-region coverage — API call in eu-west-1 | CloudTrail (multi-region trail) | Event appears in trail from non-primary region |
| S3 data events not enabled — blind spot confirmation | CloudTrail configuration | Object-level operations missing from trail — data events must be explicitly enabled |

---

### E. Active Monitoring Validation
**MITRE ATT&CK Cloud:** T1078 (Valid Accounts) · T1098 (Account Manipulation)
**Priority:** High

| Test Action | Alarm Triggered | SNS Email Received |
|---|---|---|
| Root account login | RootAccountUsage | Yes — within 5 minutes |
| IAM policy attached directly to user | IAMPolicyChange | Yes |
| Security group inbound rule added | SecurityGroupChange | Yes |
| Failed console login × 3 | ConsoleAuthFailures | Yes |
| CloudTrail stopped | CloudTrailChange | Yes |
| API call returns `AccessDenied` | UnauthorisedAPICall | Yes |
| MFA device deactivated | MFADeactivation | Yes |

For each alarm: record the time the action was taken and the time the SNS email was received. Document detection latency. An alarm that never delivers to your inbox is not a working alarm.

---

### F. Threat Detection Validation (GuardDuty)
**MITRE ATT&CK Cloud:** T1110 (Brute Force) · T1046 (Network Service Scanning) · T1078 (Valid Accounts)
**Priority:** High

| Test Action | GuardDuty Finding Expected | Validation Method |
|---|---|---|
| Nmap SYN scan against EC2 public IP | `Recon:EC2/PortProbeUnprotectedPort` | GuardDuty console — Findings dashboard |
| Hydra SSH brute force against bastion | `UnauthorizedAccess:EC2/SSHBruteForce` | GuardDuty console + SNS notification |
| Root account login | `Policy:IAMUser/RootCredentialUsage` | GuardDuty console + SNS notification |
| API call from known Tor exit node (simulate) | `UnauthorizedAccess:IAMUser/TorIPCaller` | GuardDuty test findings API |
| Unusual S3 object access pattern | `Discovery:S3/AnomalousBehavior` | GuardDuty console after deliberate access spike |
| EC2 instance communicating on unusual port | `Behavior:EC2/NetworkPortUnusual` | GuardDuty console after netcat listener |

---

### G. Continuous Compliance Validation (AWS Config)
**Priority:** High

| Config Rule | What It Checks | Expected State | Action If NON_COMPLIANT |
|---|---|---|---|
| `iam-root-access-key-check` | Root has no access keys | COMPLIANT | Delete root access key immediately |
| `mfa-enabled-for-iam-console-access` | All console users have MFA | COMPLIANT | Enforce MFA via IAM policy condition |
| `restricted-ssh` | No SG allows SSH from 0.0.0.0/0 | COMPLIANT | Restrict SG rule to specific IP /32 |
| `vpc-default-security-group-closed` | Default SG has no rules | COMPLIANT | Remove all rules from default SG |
| `s3-bucket-public-read-prohibited` | No bucket publicly readable | COMPLIANT | Enable Block Public Access |
| `s3-bucket-server-side-encryption-enabled` | All buckets encrypted | COMPLIANT | Enable default encryption SSE-KMS |
| `cloudtrail-enabled` | Trail active | COMPLIANT | Re-enable trail — triggers alarm if stopped |
| `cloud-trail-log-file-validation-enabled` | Hash validation on | COMPLIANT | Enable via trail settings |
| `ec2-imdsv2-check` | All instances require IMDSv2 | COMPLIANT | Modify instance metadata options |
| `s3-bucket-logging-enabled` | Access logging on app-data bucket | COMPLIANT | Enable logging to dedicated log bucket |

---

## Validation Cycle

Every test must complete all six steps. Skipping steps produces assumed coverage, not verified coverage.

```
STEP 1 — Generate the event
         Execute the exact action from the correct context (AWS console, CLI, or Kali VM)

STEP 2 — Confirm the raw event exists
         CloudTrail → Event History · OR · source log (auth.log, S3 access log, VPC Flow Log)

STEP 3 — Confirm CloudTrail ingestion
         CloudTrail → Event History → filter by event name and time
         Confirm: principal, region, resource, and request parameters are all present

STEP 4 — Confirm detection fired
         CloudWatch → Alarms → check alarm transitioned to ALARM state
         GuardDuty → Findings → verify finding type, severity, and affected resource
         AWS Config → Rules → verify compliance state changed

STEP 5 — Confirm notification delivered
         Check email inbox for SNS notification
         Record: time of action vs. time of notification (detection latency)

STEP 6 — Tune if missing
         See per-test troubleshooting note in the runbook
         Common causes: metric filter pattern mismatch · SNS subscription unconfirmed ·
         CloudTrail not delivering to CloudWatch Logs · GuardDuty not enabled in correct region
```

---

## Recommended Testing Progression

| Phase | Domain | Objective |
|---|---|---|
| **Phase 1 — Audit Baseline** | CloudTrail, CloudWatch Logs | Confirm all logging pipelines are active before any tests run |
| **Phase 2 — Identity Controls** | IAM | Validate privilege controls, MFA enforcement, permission boundaries |
| **Phase 3 — Network Controls** | VPC, Security Groups, NACLs | Confirm segmentation holds; validate GuardDuty network findings |
| **Phase 4 — Data Controls** | S3, encryption, versioning | Validate data protection controls; confirm Config rules fire on drift |
| **Phase 5 — Active Monitoring** | CloudWatch alarms, SNS | Validate every alarm fires and delivers end-to-end |
| **Phase 6 — Threat Detection** | GuardDuty, AWS Config | Validate behavioural detection; generate and verify findings |

Do not advance to the next phase until the current phase is verified. Phase 1 is not a formality — if CloudTrail is not delivering to CloudWatch Logs, Phases 5 and 6 will silently fail.

---

## Threat-to-Control Mapping

This table maps real-world attack scenarios to the specific control that detects or prevents them. Every control in this lab exists to address at least one row in this table.

| Attack Scenario | MITRE Technique | Control That Detects/Prevents It |
|---|---|---|
| Attacker steals IAM access keys, calls AWS API | T1078 — Valid Accounts | CloudTrail captures all API calls; GuardDuty `UnauthorizedAccess:IAMUser/MaliciousIPCaller` |
| Attacker compromises EC2 and calls IMDSv1 to steal role credentials | T1552.005 — Cloud Instance Metadata API | IMDSv2 enforced — session token required, SSRF attack blocked |
| Attacker opens security group to 0.0.0.0/0 | T1562.007 — Disable Cloud Logs | CloudWatch alarm `SecurityGroupChange`; Config rule `restricted-ssh` → NON_COMPLIANT |
| Attacker disables CloudTrail to cover tracks | T1562.008 — Disable or Modify Cloud Logs | CloudWatch alarm fires on `StopLogging` event; GuardDuty also detects this independently |
| Attacker exfiltrates data from S3 bucket | T1530 — Data from Cloud Storage | S3 access logging + CloudTrail data events; GuardDuty `Discovery:S3/AnomalousBehavior` |
| Attacker escalates privileges via IAM policy attachment | T1548 — Abuse Elevation Control | CloudWatch alarm `IAMPolicyChange`; Permission boundary prevents escalation beyond scope |
| Attacker brute-forces SSH on public-facing instance | T1110 — Brute Force | GuardDuty `UnauthorizedAccess:EC2/SSHBruteForce`; SG rate-limits connections to /32 source |
| Attacker creates backdoor IAM user | T1136.003 — Cloud Account | CloudWatch alarm `IAMPolicyChange`; CloudTrail `CreateUser` event; Config detects new user |
| Attacker moves data to external S3 bucket | T1537 — Transfer Data to Cloud Account | CloudTrail cross-account PutObject; GuardDuty `Exfiltration:S3/ObjectRead.Unusual` |
| Attacker operates from unmonitored AWS region | T1535 — Unused/Unsupported Cloud Regions | CloudTrail multi-region trail captures all regions; GuardDuty enabled globally |
| Misconfigured bucket exposes data publicly | T1530 — Data from Cloud Storage | AWS Config `s3-bucket-public-read-prohibited` → NON_COMPLIANT; Block Public Access account-level |
| Root account used for routine operations | T1078.004 — Cloud Accounts | CloudWatch alarm `RootAccountUsage`; GuardDuty `Policy:IAMUser/RootCredentialUsage` |

---

## MITRE ATT&CK for Cloud — Coverage Summary

By completing this methodology, the following ATT&CK for Cloud tactic categories are exercised and validated:

| Tactic | Techniques Covered | Phases Where Validated |
|---|---|---|
| Initial Access | T1078 (Valid Accounts), T1190 (Exploit Public-Facing App) | Phase 2, Phase 3 |
| Execution | T1059 (Command Scripting), T1651 (Cloud Administration Command) | Phase 3 |
| Persistence | T1136 (Create Account), T1098 (Account Manipulation) | Phase 2 |
| Privilege Escalation | T1548 (Abuse Elevation Control), T1078 | Phase 2 |
| Defence Evasion | T1562 (Impair Defenses), T1070 (Indicator Removal) | Phase 4, Phase 5 |
| Credential Access | T1552 (Unsecured Credentials), T1110 (Brute Force) | Phase 2, Phase 3 |
| Discovery | T1046 (Network Service Scanning), T1595 (Active Scanning), T1619 (Cloud Storage Object Discovery) | Phase 3, Phase 4 |
| Exfiltration | T1530 (Data from Cloud Storage), T1537 (Transfer to Cloud Account) | Phase 4 |
| Impact | T1485 (Data Destruction), T1491 (Defacement) | Phase 4 |

---

## Coverage Gaps — Default AWS Configuration

The following are security gaps present in a default AWS account out of the box. Documenting what was wrong before hardening is as important as documenting what was fixed.

| Default State | Risk | Control Applied |
|---|---|---|
| Root account has no MFA | Account takeover via credential compromise | MFA enforced on root |
| Default VPC exists with public subnets and permissive default SG | All instances in default VPC are publicly exposed | Custom VPC used; default VPC default SG rules cleared |
| CloudTrail not enabled by default | Zero visibility into account API activity | Multi-region trail created on day one |
| GuardDuty not enabled by default | No threat detection without explicit activation | Enabled in account setup |
| S3 Block Public Access not enforced at account level (older accounts) | Single misconfigured bucket exposes data | Account-level Block Public Access enabled |
| EC2 IMDSv1 accessible by default | SSRF attacks can steal IAM role credentials | IMDSv2 required via instance metadata options |
| IAM users created without MFA requirement | Compromised password = full account access | MFA required via IAM policy condition |
| CloudTrail does not log S3 data events by default | Object-level exfiltration is invisible | Data events explicitly enabled for critical buckets |
| AWS Config not enabled by default | No continuous compliance evaluation | Config enabled with managed rules on day one |

---

## Key Principle

> The control is not validated when it is enabled.
> The control is validated when a deliberate test action produces a verifiable, documented alert — and you can explain the chain from event to log to alarm to notification.

---

*For exact commands, expected CLI output, and per-phase implementation steps — refer to: **AWS Security Lab Operational Runbook** (`aws_security_runbook.md`)*
