# ☁️ AWS Cloud Security Lab

**Phase 5 of 6 — Security Lifecycle Portfolio**
**Focus:** Cloud infrastructure security — identity, network segmentation, data protection, logging, monitoring, and threat detection on AWS.
**Approach:** Layered, architect-level implementation — every control exists for a documented reason, every detection is validated, every decision maps to a real-world threat it mitigates.

---

## Why This Lab Exists

Most cloud tutorials teach you to *launch* things. This lab teaches you to *secure* them.

The gap between "I launched an EC2 instance" and "I understand how cloud environments get compromised" is where this project lives. AWS breaches do not happen because attackers are clever — they happen because:

- IAM policies are too permissive and an overprivileged credential gets stolen
- S3 buckets are misconfigured and data is publicly readable without the owner knowing
- CloudTrail is not enabled, so there is no record of what happened after the breach
- Security groups allow 0.0.0.0/0 on sensitive ports because "it was easier"
- No one is watching — no alarms fire, no one investigates, the attacker dwells for months

This lab implements — and documents — the controls that prevent each of those outcomes. It is structured around the same layered security model used in real AWS production environments.

---

## Architecture Philosophy

Every design decision in this lab follows five principles. Understanding them is more important than memorising the steps.

**Zero Trust** — no principal (human user, application, or service) is trusted by default. Every identity must authenticate, must be explicitly authorised for what it needs, and must not carry permissions beyond that scope. There are no wildcard permissions in this lab.

**Defence in Depth** — security at every layer independently. Network controls do not depend on IAM being correct. Logging does not depend on the network being secure. If one layer is bypassed, the next one catches it. An attacker who gets past the security group still hits OS-level controls. An attacker who compromises a credential still cannot delete audit logs.

**Least Privilege** — the single most violated principle in real AWS environments. Every IAM user, role, and policy in this lab is scoped to exactly what is needed and nothing more. No `"Action": "s3:*"`. No `"Resource": "*"` without justification.

**Immutable Audit Trail** — every API call, every login, every configuration change is logged. Logs are encrypted, versioned, and protected against deletion. You can reconstruct exactly what happened, who did it, and when — from any region.

**Separation of Duties** — the identity that deploys infrastructure is not the same identity that can modify audit logs. The developer cannot touch IAM. The auditor can read everything but change nothing.

---

## Full Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     AWS Account                             │
│                                                             │
│  Layer 1: IAM & Identity                                    │
│  ├── Root account (locked, MFA only)                        │
│  ├── admin-wilson     (admin, MFA enforced)                 │
│  ├── developer-user   (EC2 + S3 only, permission boundary)  │
│  └── readonly-auditor (read-only, no change rights)         │
│                                                             │
│  Layer 2: Network (VPC 10.0.0.0/16)                         │
│  ├── Public Subnet  10.0.1.0/24  → Bastion host             │
│  └── Private Subnet 10.0.2.0/24  → Application EC2         │
│       (no public IP — not reachable from internet directly) │
│                                                             │
│  Layer 3: EC2 Hardening                                     │
│  ├── IMDSv2 enforced (SSRF protection)                      │
│  ├── SSM Agent (management without open SSH port)           │
│  ├── IAM role only — no hardcoded credentials               │
│  └── CloudWatch agent (ships logs + metrics)                │
│                                                             │
│  Layer 4: S3 Security                                       │
│  ├── cloudtrail-logs bucket (locked, MFA Delete)            │
│  ├── app-data bucket (private, encrypted, versioned)        │
│  └── Block Public Access — account-level + per bucket       │
│                                                             │
│  Layer 5: CloudTrail                                        │
│  └── All regions, log validation, encrypted, tamper-proof   │
│                                                             │
│  Layer 6: CloudWatch Alarms                                 │
│  └── 7 critical alarms → SNS → email                        │
│                                                             │
│  Layer 7: GuardDuty                                         │
│  └── Enabled + validated (findings deliberately generated)  │
│                                                             │
│  Layer 8: AWS Config                                        │
│  └── Continuous compliance evaluation across all resources  │
└─────────────────────────────────────────────────────────────┘
```

---

## Environment

### Host Machine

| Component | Detail |
|---|---|
| OS | Kali Linux 2026.1 |
| Hypervisor | VMware Workstation |
| Network Mode | NAT (internet access for SSH to AWS) |

### AWS Infrastructure

| Component | Detail |
|---|---|
| Cloud Provider | AWS (AWS Educate free tier) |
| Region | US East — N. Virginia (us-east-1) |
| Instance Name | CyberNinja101 |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | t3.micro |
| Key Pair | cyberninja-key.pem |
| VPC | Custom (10.0.0.0/16) — not the default VPC |

---

## Implementation

### Layer 1 — IAM & Account Hardening

**Threat being mitigated:** Credential compromise, privilege escalation, unauthorised API access.

The root account is the most powerful identity in AWS. It cannot be restricted by IAM policies — it bypasses everything. This makes it the highest-value target and the most dangerous thing to use routinely.

**Root account hardening:**
- MFA enabled on root immediately after account creation
- No access keys created for root — ever
- Root is used once to create the first admin IAM user, then the console is closed
- Root credentials stored offline

**IAM identity structure:**

Users are never given permissions directly. Permissions attach to groups. Users are members of groups. This is how IAM scales without becoming unmanageable.

```
IAM Group: cloud-admins
└── Policy: AdministratorAccess (scoped)
    └── User: admin-wilson (MFA enforced via policy condition)

IAM Group: developers
└── Policy: custom-developer-policy (EC2 + specific S3 bucket only)
    └── User: developer-user
        └── Permission Boundary: developer-boundary (hard ceiling on what they can ever access)

IAM Group: auditors
└── Policy: ReadOnlyAccess
    └── User: readonly-auditor
```

**Permission boundary:** Applied to `developer-user`. Even if the developer somehow receives an AdministratorAccess policy (through misconfiguration or attack), the boundary prevents them from ever exceeding developer-level permissions. This is an advanced control that most cloud practitioners have never implemented.

**IAM password policy:**
- Minimum 14 characters
- Requires uppercase, lowercase, numbers, and symbols
- 90-day rotation enforced
- No reuse of last 5 passwords
- MFA required for console access on admin accounts

**EC2 IAM role (`ec2-ssm-role`):**

The application EC2 instance never has hardcoded credentials. It assumes a role that grants it exactly two things: SSM access (for management) and read access to one specific S3 bucket path. Nothing else. If the instance is compromised, the attacker inherits only those two scoped permissions.

```json
{
  "Effect": "Allow",
  "Action": [
    "ssm:UpdateInstanceInformation",
    "ssm:ListAssociations",
    "s3:GetObject"
  ],
  "Resource": [
    "*",
    "arn:aws:s3:::app-data-[accountid]/readonly/*"
  ]
}
```

**Screenshots:**
- `01-root-mfa-enabled.png`
- `02-iam-users-groups.png`
- `03-password-policy.png`
- `04-permission-boundary.png`
- `05-ec2-iam-role.png`

---

### Layer 2 — Network Security (VPC, Security Groups, NACLs)

**Threat being mitigated:** Unauthorised network access, lateral movement, internet-exposed attack surface.

The default VPC is a security anti-pattern. Every EC2 instance launched into it gets a public IP by default. There is no subnet segmentation. Security groups start permissive. This lab does not use the default VPC.

**VPC architecture:**

```
VPC: 10.0.0.0/16

├── Public Subnet:  10.0.1.0/24  (us-east-1a)
│   └── Bastion host (the only entry point from the internet)
│
└── Private Subnet: 10.0.2.0/24  (us-east-1a)
    └── Application EC2 (no public IP — unreachable from internet)
```

The application server has no public IP address. There is no direct path from the internet to it. To reach it you must go through the bastion in the public subnet, which only accepts SSH from your specific IP address.

**Security groups:**

Security groups are stateful — return traffic is automatically allowed. You only define what is permitted inbound.

`sg-bastion` — attached to the bastion host:
- Inbound: SSH (port 22) from `YOUR.IP.ADDRESS/32` only — not `0.0.0.0/0`
- Outbound: SSH to private subnet (`10.0.2.0/24`) only

`sg-application` — attached to the application EC2:
- Inbound: SSH from `sg-bastion` only (security group reference, not IP range)
- Inbound: HTTP/HTTPS from anywhere (if serving web traffic)
- Outbound: HTTPS to internet (for OS updates only)

Security group chaining — `sg-application` references `sg-bastion` as the SSH source, not an IP range. This means even if the bastion's IP changes, the rule remains correct. More importantly, it means the only thing that can SSH to the app server is the bastion — nothing else.

**NACLs (Network Access Control Lists):**

NACLs are stateless — unlike security groups, return traffic must be explicitly permitted. They operate at the subnet level, adding a second independent enforcement layer.

NACLs are configured to:
- Allow only necessary traffic defined in the security groups
- Explicitly allow ephemeral ports 1024–65535 for return traffic (required for stateless operation — missing this is a common misconfiguration)
- Deny all by default

The critical distinction: **Security groups have no explicit deny** — they allow what is listed and deny everything else implicitly. **NACLs have explicit deny** — you can block specific IP ranges by rule. These two mechanisms are complementary, not redundant.

**Screenshots:**
- `06-vpc-subnet-diagram.png`
- `07-security-group-bastion.png`
- `08-security-group-application.png`
- `09-nacl-rules.png`

---

### Layer 3 — EC2 Hardening

**Threat being mitigated:** SSRF credential theft, SSH brute force, lateral movement from compromised instance.

**IMDSv2 enforced:**

The EC2 instance metadata service (IMDS) is reachable from inside the instance at `169.254.169.254`. It returns IAM role credentials, instance identity, and other sensitive data. IMDSv1 allows a simple `curl` request to retrieve credentials — this is the exact vector used in the Capital One breach (2019). IMDSv2 requires a session token, which prevents cross-site request forgery attacks from being used to steal instance credentials.

```bash
# Enforced at launch — IMDSv1 disabled
aws ec2 modify-instance-metadata-options \
  --instance-id i-xxxx \
  --http-tokens required \
  --http-put-response-hop-limit 1
```

**SSH hardening** (`/etc/ssh/sshd_config`):
```
PasswordAuthentication no
PermitRootLogin no
MaxAuthTries 3
LoginGraceTime 30
```

Password authentication is disabled. Root login is disabled. The only way in is with the correct private key, from the bastion, using a non-root user.

**SSM Agent:**

AWS Systems Manager provides a secure channel to manage the instance without SSH being open at all. With SSM, you can open a shell session through the AWS console or CLI — no inbound port 22 required. This means `sg-application` can have SSH removed entirely in a production hardening scenario.

**CloudWatch agent:**

Installed on the instance. Ships system logs (`/var/log/syslog`, `/var/log/auth.log`) and OS metrics to CloudWatch. This means authentication events, sudo usage, and system errors are centralised and searchable — not siloed on the instance.

**User data script (applied at launch):**
```bash
#!/bin/bash
apt-get update -y
apt-get upgrade -y
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
```

**Linux user management:**

Three OS-level users created inside the VM to mirror the IAM identity structure:

```bash
# Create application user (no sudo)
sudo adduser appuser

# Create admin user (sudo access)
sudo adduser adminwilson
sudo usermod -aG sudo adminwilson

# Verify privilege separation
su - appuser
sudo whoami    # should fail — not in sudo group
```

**Screenshots:**
- `10-imdsv2-enforced.png`
- `11-ssm-session.png`
- `12-ssh-config-hardened.png`
- `13-user-management.png`

---

### Layer 4 — S3 Security

**Threat being mitigated:** Data exposure, unauthorised access, ransomware/deletion, exfiltration without audit trail.

S3 is responsible for more data breaches than any other AWS service. Not because it is insecure — because it is misconfigured. A single checkbox enables public access to everything in a bucket. This layer treats S3 with the same rigour as the network layer.

**Bucket architecture:**

Three purpose-specific buckets. No mixed purposes.

```
cloudtrail-logs-[accountid]   — audit logs only
app-data-[accountid]          — application data
static-assets-[accountid]     — public-facing assets only (if needed)
```

**Controls applied to every bucket:**

Block Public Access — enabled at account level AND per bucket. Belt and suspenders. A single account-level setting protects against any individual bucket misconfiguration.

Server-side encryption — SSE-KMS on `cloudtrail-logs` and `app-data`. Every object is encrypted at rest. CloudTrail logs every KMS decrypt operation, so you know when data is read.

Versioning + MFA Delete — versioning means deleted or overwritten objects are recoverable. MFA Delete means no one can permanently destroy versions without a physical MFA device. A compromised credential alone cannot destroy your audit trail.

**CloudTrail bucket policy** — the most locked-down bucket in the account:

```json
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": ["s3:DeleteObject", "s3:PutBucketPolicy"],
  "Resource": "arn:aws:s3:::cloudtrail-logs-[accountid]/*",
  "Condition": {
    "StringNotEquals": {
      "aws:PrincipalArn": "arn:aws:iam::[accountid]:root"
    }
  }
}
```

Only root can modify the CloudTrail bucket policy — and root requires MFA. An attacker with admin credentials still cannot delete your audit logs.

**S3 access logging:**

Every `GetObject`, `PutObject`, and `DeleteObject` operation on `app-data` is logged to a dedicated logging bucket. This is separate from CloudTrail management events — data event logging must be explicitly enabled and produces the evidence trail for exfiltration investigations.

**Screenshots:**
- `14-block-public-access.png`
- `15-bucket-encryption.png`
- `16-versioning-mfa-delete.png`
- `17-bucket-policy.png`
- `18-s3-access-logging.png`

---

### Layer 5 — CloudTrail (Immutable Audit Log)

**Threat being mitigated:** Undetected account activity, post-breach forensic gaps, log tampering.

CloudTrail records every API call made in your account — console clicks, CLI commands, SDK calls, and automated service actions. Without it, a breach investigation starts from nothing.

**Configuration:**

```
Multi-region trail: yes (all regions, not just us-east-1)
Log file validation: enabled (SHA-256 hash chain — detects tampering)
S3 destination: cloudtrail-logs-[accountid]
SSE-KMS encryption: enabled
CloudWatch Logs integration: enabled (feeds the alarms in Layer 6)
```

Multi-region matters: attackers launch resources in regions you are not watching. If your trail is us-east-1 only, activity in eu-west-1 is invisible.

Log file validation: each log file is hashed and the hash is signed. If a log file is modified or deleted after delivery, validation fails. You can prove tampering in court.

**Screenshots:**
- `19-cloudtrail-trail-config.png`
- `20-log-validation-enabled.png`
- `21-cloudtrail-s3-delivery.png`

---

### Layer 6 — CloudWatch Monitoring & Alerting

**Threat being mitigated:** Undetected privilege escalation, account takeover, infrastructure changes going unnoticed.

Logging without alerting is a filing cabinet. This layer creates metric filters on CloudTrail logs and attaches alarms that fire to SNS → email. Every alarm represents a real threat scenario.

| Alarm | Threat It Detects |
|---|---|
| Root account login | Root should never log in — any activity is an incident |
| IAM policy changes | Privilege escalation attempt |
| Security group rule changes | Attacker opening access or covering tracks |
| Failed console logins ≥ 3 | Brute force or credential stuffing |
| CloudTrail stopped or deleted | Attacker blinding your logging |
| Unauthorised API calls | Credential probing with insufficient permissions |
| MFA device deactivated | Account takeover indicator |

Each alarm follows the same pattern:

```
CloudTrail log → CloudWatch Logs → Metric Filter → CloudWatch Alarm → SNS Topic → Email
```

This is a real alerting pipeline. When a root login occurs, an email arrives within minutes.

**Screenshots:**
- `22-metric-filter-root-login.png`
- `23-cloudwatch-alarm-config.png`
- `24-sns-topic-subscription.png`
- `25-alarm-email-received.png`

---

### Layer 7 — GuardDuty (Threat Detection)

**Threat being mitigated:** Active attacks, anomalous behaviour, compromised credentials, reconnaissance.

GuardDuty is AWS's managed threat detection service. It analyses CloudTrail, VPC Flow Logs, and DNS logs using ML models and threat intelligence feeds. This layer does not just enable GuardDuty — it **validates** it by deliberately generating findings.

The difference between "I enabled GuardDuty" and "GuardDuty works" is the difference between a checkbox and a tested control.

**Findings generated and validated:**

| Finding | How Generated | Expected Alert |
|---|---|---|
| `Recon:EC2/PortProbeUnprotectedPort` | Nmap scan from Kali VM against EC2 | GuardDuty fires within 5 minutes |
| `UnauthorizedAccess:EC2/SSHBruteForce` | Hydra SSH brute force attempt against bastion | GuardDuty fires on repeated failed attempts |
| `Policy:IAMUser/RootCredentialUsage` | Root account console login | Fires immediately |

Each finding is documented with:
- The exact action taken to generate it
- The GuardDuty finding screenshot
- The SNS email notification screenshot
- The time between action and alert

This validates the full detection-to-notification pipeline.

**Screenshots:**
- `26-guardduty-enabled.png`
- `27-portprobe-finding.png`
- `28-sshbruteforce-finding.png`
- `29-root-credential-finding.png`
- `30-guardduty-alert-email.png`

---

### Layer 8 — AWS Config (Continuous Compliance)

**Threat being mitigated:** Configuration drift — infrastructure that was secure when deployed becoming insecure over time through incremental changes.

CloudWatch alarms tell you when something happens. GuardDuty tells you when an attack is occurring. AWS Config tells you whether your infrastructure is **currently configured correctly** — continuously, not just at deployment time.

**Managed rules deployed:**

| Rule | What It Checks |
|---|---|
| `iam-root-access-key-check` | Root account has no access keys |
| `mfa-enabled-for-iam-console-access` | All IAM users with console access have MFA |
| `restricted-ssh` | No security group allows SSH from 0.0.0.0/0 |
| `vpc-default-security-group-closed` | Default SG has no inbound/outbound rules |
| `s3-bucket-public-read-prohibited` | No S3 bucket is publicly readable |
| `s3-bucket-server-side-encryption-enabled` | All buckets have encryption enabled |
| `cloudtrail-enabled` | CloudTrail is active in the account |
| `cloud-trail-log-file-validation-enabled` | Log file validation is on |
| `ec2-imdsv2-check` | All EC2 instances require IMDSv2 |

If someone modifies a security group to add `0.0.0.0/0`, Config marks that resource non-compliant within minutes and can trigger an SNS alert. Infrastructure cannot silently drift from its secure baseline.

**Screenshots:**
- `31-config-rules-compliant.png`
- `32-config-compliance-dashboard.png`
- `33-config-noncompliant-example.png`

---

## What This Demonstrates

A hiring manager or senior assessor reviewing this project will observe:

- **Architectural thinking** — decisions are made for documented reasons, not convenience. The private subnet, the security group chaining, the permission boundary — each one has a clear threat it addresses.
- **Validated controls** — GuardDuty findings are not assumed to work. They are tested. Detection is not a checkbox.
- **Advanced controls** — IMDSv2 enforcement, permission boundaries, MFA Delete on S3, log file validation with hash chaining, NACLs with explicit stateless rules — these are not in beginner tutorials. They are in production environments.
- **Threat mapping** — every control is connected to the threat it mitigates. This is how security professionals think, not how system administrators think.
- **Separation of concerns** — identity, network, compute, data, logging, monitoring, and detection are treated as independent layers. A failure in one does not cascade through all.

---

## Repository Structure

```
cloud-security-lab/
│
├── README.md
│
├── 01-iam/
│   ├── notes.md
│   └── policies/
│       ├── developer-policy.json
│       ├── developer-boundary.json
│       └── ec2-ssm-role.json
│
├── 02-network/
│   └── notes.md
│
├── 03-ec2-hardening/
│   ├── notes.md
│   └── user-data.sh
│
├── 04-s3-security/
│   ├── notes.md
│   └── cloudtrail-bucket-policy.json
│
├── 05-cloudtrail/
│   └── notes.md
│
├── 06-cloudwatch/
│   ├── notes.md
│   └── metric-filters.json
│
├── 07-guardduty/
│   └── notes.md
│
├── 08-config/
│   └── notes.md
│
├── screenshots/
│   ├── 01-root-mfa-enabled.png
│   ├── 02-iam-users-groups.png
│   ├── 03-password-policy.png
│   ├── 04-permission-boundary.png
│   ├── 05-ec2-iam-role.png
│   ├── 06-vpc-subnet-diagram.png
│   ├── 07-security-group-bastion.png
│   ├── 08-security-group-application.png
│   ├── 09-nacl-rules.png
│   ├── 10-imdsv2-enforced.png
│   ├── 11-ssm-session.png
│   ├── 12-ssh-config-hardened.png
│   ├── 13-user-management.png
│   ├── 14-block-public-access.png
│   ├── 15-bucket-encryption.png
│   ├── 16-versioning-mfa-delete.png
│   ├── 17-bucket-policy.png
│   ├── 18-s3-access-logging.png
│   ├── 19-cloudtrail-trail-config.png
│   ├── 20-log-validation-enabled.png
│   ├── 21-cloudtrail-s3-delivery.png
│   ├── 22-metric-filter-root-login.png
│   ├── 23-cloudwatch-alarm-config.png
│   ├── 24-sns-topic-subscription.png
│   ├── 25-alarm-email-received.png
│   ├── 26-guardduty-enabled.png
│   ├── 27-portprobe-finding.png
│   ├── 28-sshbruteforce-finding.png
│   ├── 29-root-credential-finding.png
│   ├── 30-guardduty-alert-email.png
│   ├── 31-config-rules-compliant.png
│   ├── 32-config-compliance-dashboard.png
│   └── 33-config-noncompliant-example.png
│
└── docs/
    ├── executive-summary.md
    ├── technical-report.md
    └── threat-control-mapping.md
```

---

<div align="center">

**Lab conducted for educational purposes — AWS Educate isolated environment.**

**⭐ If you find this work valuable, please consider starring the repository**

**Wilson Njoroge Wanderi**

[github.com/wilsonnjoroge](https://github.com/wilsonnjoroge)

*Last Updated: June 2026*

</div>
