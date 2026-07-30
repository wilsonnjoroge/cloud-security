# 🏢 Enterprise Architecture Overview — The Capstone Environment

> **Capstone · Document 27 of 29**  
> **Estimated cost:** ~$15–25 (run for 1–2 days then tear down) · **Estimated time:** 30 minutes reading  
> **Prerequisites:** All 26 preceding documents complete

---

## What You Are Building

The capstone is a realistic multi-tier AWS environment that mirrors what you would find in a real company. It brings together everything from all four phases into one connected system — then you attack it, detect the attack, and respond to it.

```
┌─────────────────────────────────────────────────────────────────────┐
│                        ENTERPRISE VPC                               │
│  CIDR: 10.0.0.0/16                     Region: us-east-2           │
│                                                                      │
│  ┌──────────────────┐     ┌──────────────────┐                      │
│  │  PUBLIC TIER      │     │  PRIVATE APP TIER │                     │
│  │  10.0.1.0/24      │     │  10.0.2.0/24      │                     │
│  │                   │     │                   │                     │
│  │  [WAF]            │     │  [App Server EC2] │                     │
│  │  [ALB]            │──→  │  Port 8080        │                     │
│  │  [Bastion EC2]    │     │  IAM role         │                     │
│  └──────────────────┘     └────────┬──────────┘                     │
│                                     │                                │
│  ┌──────────────────┐     ┌─────────▼──────────┐                    │
│  │  SECURITY TIER    │     │  PRIVATE DB TIER   │                    │
│  │  10.0.4.0/24      │     │  10.0.3.0/24       │                    │
│  │                   │     │                    │                    │
│  │  [SIEM EC2]       │     │  [RDS MySQL]       │                    │
│  │  [Forensic WS]    │     │  Port 3306         │                    │
│  └──────────────────┘     └────────────────────┘                    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────────────────────┐
│                     SUPPORTING SERVICES                             │
│                                                                     │
│  IAM: Admin, Developers, Security, ReadOnly roles                   │
│  S3:  App assets, logs, backups, CloudTrail                        │
│  KMS: Encryption keys for EBS, RDS, S3                             │
│  Secrets Manager: DB credentials, API keys                         │
│  CloudTrail: All regions, all events                               │
│  GuardDuty: Threat detection enabled                               │
│  Security Hub: CIS + AWS Best Practices standards                  │
│  Config: All resources tracked                                     │
│  CloudWatch: Alarms, dashboards, log analysis                      │
│  WAF: CRS + rate limiting on ALB                                   │
└────────────────────────────────────────────────────────────────────┘
```

---

## The Fictional Company — AcmeFintech Ltd

To make the scenario realistic, you are building the AWS infrastructure for a fictional fintech company:

| Detail | Value |
|--------|-------|
| Company name | AcmeFintech Ltd |
| Business | Online payment processing |
| Compliance | PCI DSS (handles credit card data) |
| Team | 3 developers, 1 security analyst, 1 DBA |
| Sensitivity | Financial data, customer PII |

This context matters because:
- Security controls must meet PCI DSS requirements
- S3 buckets may contain cardholder data (triggers Macie alerts)
- RDS stores customer financial records (must be encrypted)
- IAM must enforce least privilege for each role

---

## Architecture Decisions and Why

### Why a bastion host instead of direct SSH?

```
Internet → Bastion (public subnet) → App servers (private subnet)
```

The bastion is the single entry point for admin SSH access. App servers have no public IPs — they are unreachable from the internet directly. Compromise the bastion → you can reach the app tier. The bastion's SSH access is logged via CloudWatch.

### Why separate security subnet?

The SIEM and forensic workstation live in an isolated subnet with no route to the app or DB tiers — they pull logs and read snapshots without having any access to production systems. An attacker who compromises the app tier cannot pivot to compromise the forensic workstation.

### Why RDS instead of EC2 database?

RDS handles automated backups, patching, encryption, and multi-AZ failover. More importantly for forensics: RDS has its own audit logging (MySQL general query log) which CloudWatch captures — giving you database-level forensic evidence.

### Why ALB + WAF instead of direct EC2?

The Application Load Balancer sits between the internet and app servers. WAF filters malicious requests at the ALB level before they reach the application. This decouples your defense from your application code.

---

## IAM Structure for AcmeFintech

```
AcmeFintech AWS Account
      │
      ├── admin-ciso              → AdministratorAccess
      │
      ├── Group: developers
      │     ├── dev-alice         → EC2, S3, Lambda, CloudWatch (no IAM)
      │     ├── dev-bob           → EC2, S3, Lambda, CloudWatch (no IAM)
      │     └── dev-charlie       → EC2, S3, Lambda, CloudWatch (no IAM)
      │
      ├── Group: security-team
      │     └── sec-analyst       → SecurityAudit, GuardDuty, SecurityHub, CloudTrail
      │
      ├── Group: dba-team
      │     └── dba-diana         → RDS full access, S3 read (for backups)
      │
      ├── Group: readonly
      │     └── auditor-eve       → ReadOnlyAccess
      │
      └── Roles (for services)
            ├── AppServerRole     → S3 read, Secrets Manager read, CloudWatch logs
            ├── BastionRole       → SSM Session Manager, CloudWatch logs
            ├── LambdaRole        → S3 read, DynamoDB read/write, CloudWatch logs
            └── LambdaIRRole      → EC2 isolate, IAM disable, SNS publish
```

---

## Security Controls Mapping to PCI DSS

| PCI DSS Requirement | AWS Control |
|--------------------|------------|
| Req 1: Network controls | VPC, Security Groups, NACLs, WAF |
| Req 2: Secure configuration | AWS Config, CIS Benchmark in Security Hub |
| Req 3: Protect stored cardholder data | KMS encryption, S3 SSE-KMS, RDS encryption |
| Req 4: Encrypt in transit | TLS on ALB, HTTPS-only S3 policy |
| Req 5: Anti-malware | GuardDuty Malware Protection, Inspector |
| Req 6: Secure software | Inspector vulnerability scanning, WAF |
| Req 7: Access control | IAM least privilege, SCPs |
| Req 8: Identity management | MFA enforcement, IAM password policy |
| Req 10: Audit logging | CloudTrail, VPC Flow Logs, RDS audit log |
| Req 11: Security testing | Phase 4 attack scenarios |
| Req 12: Security policy | Config rules, Security Hub compliance |

---

## Cost Breakdown for the Capstone

| Service | Resource | Hourly cost | 24hr cost |
|---------|----------|------------|-----------|
| EC2 | Bastion (t2.micro) | $0.012 | $0.29 |
| EC2 | App server (t2.small) | $0.023 | $0.55 |
| EC2 | Forensic WS (t3.medium) | $0.047 | $1.13 |
| RDS | MySQL db.t3.micro | $0.017 | $0.41 |
| ALB | Application LB | $0.008 | $0.19 |
| NAT Gateway | 1 NAT GW | $0.045 | $1.08 |
| GuardDuty | ~30 day trial | $0 | $0 |
| Security Hub | ~findings based | ~$0.01 | ~$0.24 |
| **Total** | | **~$0.15/hr** | **~$3.89** |

> Run the full capstone for 1–2 days (cost: $4–8), complete the attack and response exercise, then tear it all down. Total capstone budget: under $15.

---

## Prerequisites Checklist

Before starting document 28:

```
Phase 1 Complete:
  [ ] Can build a VPC from scratch (console and CLI)
  [ ] Understand IAM users, groups, roles, policies
  [ ] Know EC2 lifecycle and storage
  [ ] Know S3 bucket policies and security
  [ ] Know security groups and NACLs differences
  [ ] Have CloudTrail and CloudWatch running

Phase 2 Complete:
  [ ] GuardDuty enabled and findings understood
  [ ] VPC Flow Logs configured and queryable
  [ ] AWS Config rules active
  [ ] Security Hub standards enabled
  [ ] WAF configured on an ALB
  [ ] KMS keys created and used
  [ ] Secrets Manager in use

Phase 3 Complete:
  [ ] Can acquire and analyze EBS snapshots
  [ ] Can query CloudTrail to reconstruct attack timelines
  [ ] Understand memory acquisition with LiME
  [ ] Know the IAM incident response playbook
  [ ] Can investigate S3 breaches
  [ ] Have a working Lambda auto-isolation function

Phase 4 Complete:
  [ ] Run at least 2 CloudGoat scenarios
  [ ] Understand at least 5 IAM escalation paths
  [ ] Know the IMDS attack and have enforced IMDSv2
  [ ] Know S3 misconfiguration attack patterns
  [ ] Have used Pacu for enumeration
```

---

*Capstone · AWS Cybersecurity & Digital Forensics Roadmap*
