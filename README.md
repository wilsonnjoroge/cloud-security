
---

# AWS Enterprise Cloud Architecture Capstone

An enterprise-grade AWS environment built from scratch, following the AWS Well-Architected Framework: network, identity, compute, detection, forensics, and offensive validation modeled on a fictional PCI-DSS fintech, **AcmeFintech Ltd.**

 ![Status](https://img.shields.io/badge/status-in--progress-orange) ![Cloud](https://img.shields.io/badge/cloud-AWS-FF9900) ![Focus](https://img.shields.io/badge/focus-Cloud%20Security%20%7C%20DFIR-blue) ![Certification](https://img.shields.io/badge/target-AWS%20Certified%20Security%20--%20Specialty-232F3E)   

---

## About This Project

This repository documents the design, build, hardening, detection, incident response, and adversarial testing of a realistic multi-tier AWS environment. It's structured as a 29-document, four-phase roadmap moving from foundational architecture through detection engineering and incident response to offensive validation culminating in a capstone that runs the full lifecycle end to end: **build → attack → detect → respond → investigate.**

Every decision in this build is made against two questions:

1. Does this reduce the attack surface, in line with the AWS Well-Architected Framework's security pillar?
2. If this control fails, does the environment produce the evidence needed to investigate what happened?

This is a simulation of enterprise cloud security engineering, built to validate hands-on capability against the **AWS Certified Security – Specialty** exam and to demonstrate applied **cloud DFIR** competency.

The build is also documented publicly as a **30-Day AWS Well-Architected LinkedIn series**, sharing architecture decisions and enterprise risk framing for practitioners pursuing the same certification.

---

## Security Principles Applied Throughout

- Principle of least privilege
- MFA on all human-accessed accounts
- IAM roles instead of long-lived access keys
- Encryption at rest and in transit
- S3 versioning and logging enabled by default
- Security groups over broad network access
- Network segmentation across tiers
- Continuous monitoring and automated compliance checks


---

## Author

**Name:** Wilson Njoroge Wanderi, MSc, CCEP, CC, KCNA, ITIL®4  
**Area of Expertise:** Middleware Engineering Specialist, Cloud Security Specialist (AWS)  
**Education:** MSc Cybersecurity & Digital Forensics: Open University of Kenya  
**Research focus:** Behavioural anomaly detection at API integration boundaries in Tier-1 commercial banking environments.

---

## High-Level Architecture

```text
                    Internet
                        │
                Internet Gateway
                        │
                Public Subnet (DMZ)
                        │
                Security Groups
                        │
                     EC2 Instance
                        │
        ┌───────────────┼───────────────┐
        │               │               │
      IAM             CloudTrail      CloudWatch
        │               │               │
        └───────────────┼───────────────┘
                        │
                      S3 Bucket
                        │
        ┌───────────────┼───────────────┐
        │               │               │
    GuardDuty      AWS Config      Security Hub
```

---

## AWS Services Used

| Service | Purpose |
|----------|----------|
| VPC | Network isolation |
| EC2 | Compute |
| IAM | Identity management |
| S3 | Object storage |
| CloudTrail | API logging |
| CloudWatch | Monitoring |
| GuardDuty | Threat detection |
| AWS Config | Compliance monitoring |
| Security Hub | Security posture management |
| WAF | Web protection |
| KMS | Encryption |
| Secrets Manager | Credential management |



Full architecture rationale: [`27-enterprise-architecture-overview`](docs/27-enterprise-architecture-overview.md)

---

## Tech Stack

![AWS](https://img.shields.io/badge/AWS-232F3E?style=flat&logo=amazonaws&logoColor=white) ![VPC](https://img.shields.io/badge/VPC-8C4FFF?style=flat&logo=amazonaws&logoColor=white) ![IAM](https://img.shields.io/badge/IAM-DD344C?style=flat&logo=amazoniam&logoColor=white) ![EC2](https://img.shields.io/badge/EC2-FF9900?style=flat&logo=amazonec2&logoColor=white) ![S3](https://img.shields.io/badge/S3-569A31?style=flat&logo=amazons3&logoColor=white) ![RDS](https://img.shields.io/badge/RDS-527FFF?style=flat&logo=amazonrds&logoColor=white) ![KMS](https://img.shields.io/badge/KMS-DD344C?style=flat&logo=amazonaws&logoColor=white) ![Secrets Manager](https://img.shields.io/badge/Secrets_Manager-DD344C?style=flat&logo=amazonaws&logoColor=white) ![CloudTrail](https://img.shields.io/badge/CloudTrail-232F3E?style=flat&logo=amazonaws&logoColor=white) ![CloudWatch](https://img.shields.io/badge/CloudWatch-FF4F8B?style=flat&logo=amazoncloudwatch&logoColor=white) ![GuardDuty](https://img.shields.io/badge/GuardDuty-DD344C?style=flat&logo=amazonaws&logoColor=white) ![Security Hub](https://img.shields.io/badge/Security_Hub-DD344C?style=flat&logo=amazonaws&logoColor=white)![AWS Config](https://img.shields.io/badge/AWS_Config-232F3E?style=flat&logo=amazonaws&logoColor=white) ![WAF](https://img.shields.io/badge/WAF-DD344C?style=flat&logo=amazonaws&logoColor=white) ![SSM](https://img.shields.io/badge/Session_Manager-232F3E?style=flat&logo=amazonaws&logoColor=white) ![CloudGoat](https://img.shields.io/badge/CloudGoat-000000?style=flat&logo=github&logoColor=white) ![Pacu](https://img.shields.io/badge/Pacu-000000?style=flat&logo=github&logoColor=white) ![Volatility](https://img.shields.io/badge/Volatility-2E2E2E?style=flat) ![Sleuthkit](https://img.shields.io/badge/Sleuthkit-2E2E2E?style=flat) ![FTK Imager](https://img.shields.io/badge/FTK_Imager-2E2E2E?style=flat) ![LiME](https://img.shields.io/badge/LiME-2E2E2E?style=flat)

--- 

### Why This Structure

Each document builds on identity, network, or compute infrastructure established in a prior one, mirroring how production environments are actually provisioned:

- **Network** provides the segmented environment everything else runs inside.
- **Identity** is provisioned before compute, so no resource ever runs without correct, least-privilege permissions attached.
- **Compute** fuses network and identity: every EC2 instance is placed into pre-built subnets and assumes pre-built roles, never hardcoded credentials.
- **Storage, detection, and logging** extend this same environment, so that when something goes wrong, the evidence to investigate it already exists forensic readiness is treated as an architecture decision, not an afterthought.
- **Offensive validation** confirms the controls actually hold under realistic attack conditions, not just on paper.
- **The capstone** runs all of the above together against one realistic enterprise environment.

---

## Certification Alignment

Mapped directly to AWS Certified Security – Specialty exam domains:

| Domain | Covered by |
|---|---|
| Threat detection & incident response | Docs 09, 16–21, 29 |
| Security logging & monitoring | Docs 06, 07, 10, 17 |
| Infrastructure security | Docs 01, 03, 05, 24 |
| Identity & access management | Docs 02, 19, 23 |
| Data protection | Docs 04, 14, 15, 25 |
| Management & security governance | Docs 08, 11, 12, 27 |

---

## Project Roadmap & Completion Tracker

This table is the single source of truth for build progress.

### Phase 0: Reference

| Status | Project | Doc |
|---|---|---|
| [ ] | Master Reference Guide | `00-master-reference-guide` |

### Phase 1: Foundations

| Status | Project | Doc |
|---|---|---|
| ☑️ | VPC From Scratch | `01-vpc-lab-exercise` |
| ☑️| IAM Users, Groups, Roles & Policies | `02-iam-users-groups-roles` |
| ☑️| EC2 Instance Lifecycle | `03-ec2-instance-lifecycle` |
| ☑️ | S3 Buckets and Policies | `04-s3-buckets-and-policies` |
| ☑️ | Security Groups and NACLs | `05-security-groups-and-nacls` |
| ☑️ | CloudTrail Setup | `06-cloudtrail-setup` |
| ☑️ | CloudWatch Alarms | `07-cloudwatch-alarms` |
| [ ] | Billing and Cost Controls | `08-billing-and-cost-controls` |

### Phase 2: Detection & Hardening

| Status | Project | Doc |
|---|---|---|
| [ ] | GuardDuty Setup and Findings | `09-guardduty-setup-and-findings` |
| [ ] | VPC Flow Logs and Analysis | `10-vpc-flow-logs-and-analysis` |
| [ ] | AWS Config and Drift Detection | `11-aws-config-and-drift-detection` |
| [ ] | Security Hub Overview | `12-security-hub-overview` |
| [ ] | WAF Setup | `13-waf-setup` |
| [ ] | KMS Encryption Basics | `14-kms-encryption-basics` |
| [ ] | Secrets Manager | `15-secrets-manager` |

### Phase 3: Cloud Forensics & Incident Response

| Status | Project | Doc |
|---|---|---|
| [ ] | EBS Snapshot Forensics | `16-ebs-snapshot-forensics` |
| [ ] | CloudTrail Log Analysis | `17-cloudtrail-log-analysis` |
| [ ] | Memory Acquisition (EC2) | `18-memory-acquisition-ec2` |
| [ ] | Compromised IAM Response | `19-compromised-iam-response` |
| [ ] | S3 Breach Investigation | `20-s3-breach-investigation` |
| [ ] | Lambda Auto-Isolation | `21-lambda-auto-isolation` |

### Phase 4: Offensive Validation

| Status | Project | Doc |
|---|---|---|
| [ ] | CloudGoat Lab Setup | `22-cloudgoat-lab-setup` |
| [ ] | IAM Privilege Escalation | `23-iam-privilege-escalation` |
| [ ] | IMDS Attack and Hardening | `24-imds-attack-and-hardening` |
| [ ] | S3 Misconfiguration Attacks | `25-s3-misconfiguration-attacks` |
| [ ] | Pacu Framework Basics | `26-pacu-framework-basics` |

### Capstone Project

| Status | Project | Doc |
|---|---|---|
| [ ] | Enterprise Architecture Overview | `27-enterprise-architecture-overview` |
| [ ] | Building the Environment Step-by-Step | `28-building-the-environment-step-by-step` |
| [ ] | Attack-Detect-Respond Simulation | `29-attack-detect-respond-simulation` |

### Supporting References

| Status | Project | Doc |
|---|---|---|
| [ ] | AWS Security Methodology | `aws_security_methodology` |
| [ ] | AWS Security Runbook | `aws_security_runbook` |
| [ ] | VPC Lab Exercise (supplementary notes) | `vpc_lab_exercise` |

---

## Capstone Project Details

The capstone (Docs 27–29) is the point at which every prior phase converges into one realistic, attackable, and investigable environment:

- **Doc 27 Enterprise Architecture Overview**: defines the full AcmeFintech Ltd environment multi-tier VPC, bastion access pattern, isolated security/forensics subnet, IAM structure across five roles and four groups, and a complete PCI DSS control mapping.
- **Doc 28 Building the Environment Step-by-Step**: walks through provisioning the entire architecture in sequence, reusing and extending every pattern established in Phases 1–4.
- **Doc 29 Attack-Detect-Respond Simulation**: runs a live, realistic attack chain (IAM privilege escalation → data exfiltration → resource abuse) against the built environment, validates detection via GuardDuty/Security Hub, and walks through the full incident response and investigation process.

**Estimated capstone cost:** $15–25, run for 1–2 days then torn down.

---

**Fictional company profile:**

| Detail | Value |
|---|---|
| Company name | AcmeFintech Ltd |
| Business | Online payment processing |
| Compliance | PCI DSS (handles credit card data) |
| Team simulated | 3 developers, 1 security analyst, 1 DBA |
| Sensitivity | Financial data, customer PII |

---

## Prerequisites Checklist (from Doc 27)

**Phase 1**
- [x] Build a VPC from scratch (console and CLI)
- [x] Understand IAM users, groups, roles, policies
- [x] Know EC2 lifecycle and storage
- [x] Know S3 bucket policies and security
- [x] Know security groups and NACL differences
- [x] Have CloudTrail and CloudWatch running

**Phase 2**
- [ ] GuardDuty enabled and findings understood
- [ ] VPC Flow Logs configured and queryable
- [ ] AWS Config rules active
- [ ] Security Hub standards enabled
- [ ] WAF configured on an ALB
- [ ] KMS keys created and used
- [ ] Secrets Manager in use

**Phase 3**
- [ ] Acquire and analyze EBS snapshots
- [ ] Query CloudTrail to reconstruct attack timelines
- [ ] Understand memory acquisition with LiME
- [ ] Know the IAM incident response playbook
- [ ] Investigate S3 breaches
- [ ] Have a working Lambda auto-isolation function

**Phase 4**
- [ ] Run at least 2 CloudGoat scenarios
- [ ] Understand at least 5 IAM escalation paths
- [ ] Know the IMDS attack and enforce IMDSv2
- [ ] Know S3 misconfiguration attack patterns
- [ ] Use Pacu for enumeration

---

## Repository Structure

```
.
├── README.md
├── docs/                  : all 29 build documents plus reference guides
└── screenshots/
    ├── vpc/
    ├── iam/
    ├── ec2/
    └── s3/
```

Every document in `docs/` follows the same standard: objective, skills covered, AWS services, prerequisites, architecture, step-by-step procedure with screenshots, validation, security considerations, troubleshooting, and lessons learned. Screenshots follow a `NN-task-name-x.png` naming convention (e.g. `01-create-vpc-a.png`, `01-create-vpc-b.png`).

---

## Content Series

This build is documented publicly as part of a **30-Day AWS Well-Architected series on LinkedIn**: architecture decisions, enterprise risk framing, and exam-relevant insight for practitioners pursuing AWS Certified Security – Specialty.

---

## Future Improvements

- Infrastructure as Code (Terraform / CloudFormation)
- Multi-region deployment
- AWS Organizations & Control Tower
- Lambda-based security automation and EventBridge triggers
- CI/CD security pipeline integration
- AWS Detective and Amazon Inspector integration

---

## References

**AWS Documentation**
- [docs.aws.amazon.com](https://docs.aws.amazon.com)
- [AWS Security](https://aws.amazon.com/security)
- [Well-Architected Framework – Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar)

**Frameworks**
- AWS Well-Architected Framework
- CIS AWS Foundations Benchmark
- NIST Cybersecurity Framework
- MITRE ATT&CK for Cloud

---

## Disclaimer

All infrastructure, company names (AcmeFintech Ltd), and data used in this project are fictional and built exclusively within isolated, cost-controlled AWS lab environments for educational and portfolio purposes. No production or customer data is used at any stage.

## License

This project's documentation is shared for educational purposes. Reuse with attribution.
