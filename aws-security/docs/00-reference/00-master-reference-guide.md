# 🗺️ AWS Cybersecurity Roadmap — Master Reference Guide

> **For:** Cybersecurity & Digital Forensics Track  
> **Account:** AWS Free Tier + $200 credits  
> **Duration:** ~20 weeks at 8+ hours/week  
> **Total documents:** 29 across 4 phases + capstone  
> **End state:** AWS Security Specialty ready · Full-spectrum cloud security practitioner

---

## How to Read This Document

This is your master map. Before starting any lab, read the relevant section here to understand:
- What you are about to learn
- Why it matters at this stage
- What it depends on
- What it unlocks next

Every document in this roadmap is connected. Nothing is standalone. The capstone only works because all 28 documents before it built the knowledge and the environment it runs on.

---

## The Architecture of This Roadmap

```
PHASE 1: FOUNDATIONS          → You learn what exists and how to build it
      │
      ▼
PHASE 2: SECURITY LAYER       → You learn how to protect what you built
      │
      ▼
PHASE 3: FORENSICS & IR       → You learn how to investigate what broke
      │
      ▼
PHASE 4: RED TEAM             → You learn how an attacker would break it
      │
      ▼
CAPSTONE                      → You build it, break it, detect it, fix it
```

Each phase is a lens on the same environment. Phase 1 builds it. Phase 2 secures it. Phase 3 investigates it. Phase 4 attacks it. The capstone does all four in sequence.

---

## Phase 1 — Foundations (Documents 01–08)

### The big picture

Phase 1 answers one question: **what is AWS and how does it connect?**

You cannot secure something you do not understand. You cannot investigate something you did not build. Phase 1 is not optional groundwork — it is the direct prerequisite for every security and forensic action in phases 2 through 4. Every attack in Phase 4, every detection in Phase 2, every forensic artifact in Phase 3 exists inside the infrastructure Phase 1 teaches you to build.

### Document dependency map

```
01 — VPC from scratch
      │
      ├──→ 05 (Security Groups live inside VPCs)
      ├──→ 09 (GuardDuty monitors VPC traffic)
      ├──→ 10 (Flow Logs are a VPC feature)
      └──→ 28 (Capstone VPC is built using this knowledge)

02 — IAM: users, groups, roles, policies
      │
      ├──→ 03 (EC2 roles are IAM roles)
      ├──→ 04 (S3 bucket policies reference IAM ARNs)
      ├──→ 14 (KMS key policies are IAM-style JSON)
      ├──→ 19 (Compromised IAM is the most critical IR scenario)
      ├──→ 23 (All 12 escalation paths require specific IAM permissions)
      └──→ 28 (Capstone IAM structure: 5 users, 4 groups, 4 roles)

03 — EC2 instance lifecycle
      │
      ├──→ 05 (Security groups attach to EC2)
      ├──→ 16 (EBS snapshots come from EC2 volumes)
      ├──→ 18 (Memory acquisition targets running EC2)
      ├──→ 21 (Lambda isolates EC2 instances)
      ├──→ 24 (IMDS attack targets EC2 metadata service)
      └──→ 28 (Capstone has bastion + app server EC2)

04 — S3 buckets and policies
      │
      ├──→ 06 (CloudTrail logs land in S3)
      ├──→ 10 (Flow Logs can be sent to S3)
      ├──→ 14 (S3 encrypted with KMS keys)
      ├──→ 20 (S3 breach investigation requires S3 knowledge)
      ├──→ 25 (S3 attacks target misconfigured buckets)
      └──→ 28 (Capstone has log bucket + data bucket)

05 — Security groups and NACLs
      │
      ├──→ 13 (WAF is a Layer 7 complement to SG Layer 3/4)
      ├──→ 19 (SG modification is a common attacker action)
      ├──→ 21 (Lambda isolation works by swapping security groups)
      └──→ 28 (Capstone has 5 purpose-built security groups)

06 — CloudTrail setup
      │
      ├──→ 07 (CloudWatch alarms fire on CloudTrail metric filters)
      ├──→ 11 (Config uses CloudTrail for change tracking)
      ├──→ 17 (CloudTrail log analysis IS Phase 3 forensics)
      └──→ 19 (CloudTrail is the primary IAM IR evidence source)

07 — CloudWatch alarms
      │
      ├──→ 09 (GuardDuty findings route through EventBridge/CloudWatch)
      ├──→ 21 (Lambda IR triggered by CloudWatch → EventBridge)
      └──→ 28 (Capstone security dashboard uses CloudWatch)

08 — Billing and cost controls
      │
      └──→ All subsequent phases (budget protection for $200 credits)
```

### What Phase 1 unlocks

After Phase 1 you can:
- Build any AWS network topology from scratch
- Create and manage all IAM identities with least privilege
- Launch, manage, and secure EC2 instances
- Secure and audit S3 storage
- Read and query audit logs in real time
- Monitor infrastructure health with alarms

Without Phase 1 you cannot do Phase 2 — you would be configuring security tools on infrastructure you don't understand.

---

## Phase 2 — Security & Blue Team (Documents 09–15)

### The big picture

Phase 2 answers the question: **how do you know when something is wrong?**

Phase 1 built the infrastructure. Phase 2 adds the detection layer — the sensors, cameras, and alarms that tell you when the infrastructure is under attack or misconfigured. Every tool in Phase 2 produces evidence that Phase 3 analyzes and that Phase 4 tries to evade.

The relationship between Phase 2 tools is additive — each one watches a different slice of the environment:

```
GuardDuty    → watches API calls and network traffic for threats
VPC Flow Logs → watches raw network connections
AWS Config   → watches resource configuration changes
Security Hub  → aggregates everything into one score
WAF          → watches HTTP requests before they reach the app
KMS          → controls who can decrypt data
Secrets Mgr  → controls who can access credentials
```

No single tool sees everything. Together they leave an attacker almost nowhere to hide.

### Document dependency map

```
09 — GuardDuty
      │
      ├──→ depends on: 01 (VPC), 06 (CloudTrail already enabled)
      ├──→ feeds: 12 (Security Hub aggregates GuardDuty findings)
      ├──→ triggers: 21 (Lambda auto-isolation on GuardDuty findings)
      └──→ detected in: Phase 4 (attackers try to disable or evade it)

10 — VPC Flow Logs
      │
      ├──→ depends on: 01 (VPC must exist), 04 (S3 for log storage)
      ├──→ feeds: 17 (flow logs correlated with CloudTrail in IR)
      ├──→ feeds: 20 (flow logs show network exfiltration evidence)
      └──→ used in: Capstone Part 4 (network forensics during investigation)

11 — AWS Config
      │
      ├──→ depends on: 04 (S3 for config log storage), 02 (IAM service role)
      ├──→ feeds: 12 (Security Hub shows Config compliance findings)
      ├──→ used in: 17 (Config shows resource state at time of incident)
      └──→ detects: Phase 4 attacks that modify security groups or policies

12 — Security Hub
      │
      ├──→ depends on: 09 (GuardDuty), 11 (Config), Inspector, Macie
      ├──→ aggregates ALL Phase 2 findings into one dashboard
      └──→ used in: Capstone Part 2 (first stop when alarm fires)

13 — WAF
      │
      ├──→ depends on: 03 (needs ALB which needs EC2 target)
      ├──→ protects: the web application in the capstone app server
      └──→ logs used in: 20 (S3 breach investigation cross-reference)

14 — KMS
      │
      ├──→ depends on: 02 (key policies are IAM policies)
      ├──→ encrypts: EBS volumes (03), S3 buckets (04), RDS (capstone)
      ├──→ used in: 15 (Secrets Manager uses KMS to encrypt secrets)
      ├──→ used in: 16 (forensic snapshots encrypted with KMS)
      └──→ attacked in: Phase 4 (ransomware via KMS re-encryption)

15 — Secrets Manager
      │
      ├──→ depends on: 14 (KMS encrypts the secrets), 02 (IAM controls access)
      ├──→ replaces: hardcoded credentials in EC2 user-data (03)
      ├──→ exfiltrated in: 17 (attacker GetSecretValue events)
      └──→ rotated in: 19 (IR step — rotate all accessed secrets)
```

### The detection stack — how Phase 2 tools communicate

```
Attack happens
      │
      ▼
GuardDuty detects anomalous API/network behavior
      │
AWS Config detects configuration change
      │
VPC Flow Logs record network connection
      │
WAF logs the HTTP request (if web-based)
      │
      ▼
All findings → Security Hub (centralized dashboard)
      │
      ▼
EventBridge rule fires on HIGH/CRITICAL finding
      │
      ▼
Lambda auto-isolation runs (document 21)
      │
      ▼
SNS sends alert to analyst
```

### What Phase 2 unlocks

After Phase 2 you can:
- Detect active threats in real time (GuardDuty)
- Audit network connections after the fact (Flow Logs)
- Prove configuration state at any point in time (Config)
- Maintain a continuous compliance score (Security Hub)
- Block application-layer attacks (WAF)
- Protect all data at rest and in transit (KMS)
- Eliminate hardcoded credentials from code (Secrets Manager)

Without Phase 2, Phase 3 has no evidence to analyze — you would be investigating a crime scene with no cameras and no logs.

---

## Phase 3 — Cloud Forensics & Incident Response (Documents 16–21)

### The big picture

Phase 3 answers the question: **what happened, how bad is it, and how do we stop it?**

This is where your Digital Forensics degree transfers directly to the cloud. The methodology is identical — preserve evidence, analyze without contaminating, reconstruct the timeline, determine scope, contain and recover. The tools are different. The thinking is the same.

Phase 3 depends on Phase 2 for its evidence. GuardDuty provides the initial alert. CloudTrail provides the timeline. VPC Flow Logs provide the network picture. Config provides the resource state. Without Phase 2 running before the incident, Phase 3 has nothing to investigate.

### Document dependency map

```
16 — EBS Snapshot Forensics
      │
      ├──→ depends on: 03 (EBS volumes are EC2 storage)
      ├──→ depends on: 14 (snapshots may be KMS-encrypted)
      ├──→ depends on: 02 (forensic analyst needs IAM permissions)
      ├──→ used in: Capstone Part 3 (evidence acquisition step)
      └──→ followed by: 17 (disk analysis leads to log analysis)

17 — CloudTrail Log Analysis
      │
      ├──→ depends on: 06 (CloudTrail must be running — Phase 1!)
      ├──→ depends on: 10 (Flow Logs correlated here)
      ├──→ used in: 19 (IAM IR entirely driven by CloudTrail)
      ├──→ used in: 20 (S3 breach uses CloudTrail GetObject events)
      └──→ used in: Capstone Part 2 (detection and scope determination)

18 — Memory Acquisition
      │
      ├──→ depends on: 03 (must understand EC2 to access running instance)
      ├──→ depends on: 16 (disk forensics precedes memory analysis conceptually)
      ├──→ tools: LiME (acquisition) + Volatility 3 (analysis)
      └──→ catches: fileless malware that leaves no disk artifacts

19 — Compromised IAM Response
      │
      ├──→ depends on: 02 (must know IAM to respond to IAM incidents)
      ├──→ depends on: 06 (CloudTrail is the evidence source)
      ├──→ depends on: 09 (GuardDuty is the detection source)
      ├──→ used in: Capstone Part 3 (containment of dev-alice)
      └──→ hardened by: 23 (knowing escalation paths helps you find backdoors)

20 — S3 Breach Investigation
      │
      ├──→ depends on: 04 (must understand S3 to investigate it)
      ├──→ depends on: 06 (CloudTrail GetObject events are the evidence)
      ├──→ depends on: 10 (Flow Logs show network exfiltration)
      ├──→ applies: 14 (versioning recovery of deleted objects)
      └──→ used in: Capstone Part 2 (Macie + CloudTrail exfiltration analysis)

21 — Lambda Auto-Isolation
      │
      ├──→ depends on: 09 (triggered by GuardDuty findings)
      ├──→ depends on: 05 (isolation works by swapping security groups)
      ├──→ depends on: 02 (Lambda needs IAM role to perform actions)
      ├──→ depends on: 03 (knows how to snapshot EBS before isolating)
      └──→ used in: Capstone Part 3 (auto-isolation fires during the attack sim)
```

### The forensic evidence chain

```
INCIDENT DETECTED (Phase 2 detection layer fires)
      │
      ▼
PRESERVE (before touching anything)
  16 → EBS snapshot           (disk evidence)
  18 → Memory acquisition     (volatile evidence)
  17 → CloudTrail preserved   (API evidence) — already preserved if trail enabled
  10 → Flow Logs preserved    (network evidence) — already running
      │
      ▼
ANALYZE (on forensic workstation, never on live instance)
  16 → Mount snapshot read-only, run Sleuth Kit / YARA
  18 → Run Volatility against memory dump
  17 → CloudWatch Logs Insights / CloudTrail Lake queries
  10 → Athena queries against flow log S3 data
      │
      ▼
SCOPE (how bad is it?)
  19 → Which IAM identities were compromised?
  20 → Which S3 data was accessed or deleted?
  17 → Full attacker timeline reconstructed
      │
      ▼
CONTAIN
  21 → Lambda auto-isolates EC2 (already done automatically)
  19 → Disable IAM user, attach deny-all policy
  20 → Restrict S3 bucket policy
      │
      ▼
ERADICATE → RECOVER → DOCUMENT
```

### What Phase 3 unlocks

After Phase 3 you can:
- Acquire forensic disk evidence from cloud instances
- Reconstruct complete attacker timelines from API logs
- Capture and analyze volatile memory from running instances
- Execute the full IAM incident response playbook
- Scope and contain an S3 data breach
- Automate first response so containment happens in under 30 seconds

Without Phase 3, Phase 4 has no defensive counterpart — you would be running attacks with no understanding of how they are detected and investigated.

---

## Phase 4 — Red Team & Adversary Simulation (Documents 22–26)

### The big picture

Phase 4 answers the question: **how would an attacker actually break in?**

This phase is studied last for a reason. Every attack technique in Phase 4 is immediately more meaningful because you built the infrastructure (Phase 1), understand how it is defended (Phase 2), and know how attacks are investigated (Phase 3). When you run the IMDS attack in document 24, you already know which CloudTrail event it generates, which GuardDuty finding it triggers, and how to isolate the instance.

Phase 4 is not just about learning to attack — it is about understanding the attacker's perspective deeply enough to build better defenses.

### Document dependency map

```
22 — CloudGoat Lab Setup
      │
      ├──→ depends on: ALL Phase 1 (need to understand what you are attacking)
      ├──→ depends on: ALL Phase 2 (need to recognize the detections that fire)
      ├──→ requires: SEPARATE AWS account (never run in main account)
      └──→ provides: realistic attack scenarios for docs 23-26

23 — IAM Privilege Escalation
      │
      ├──→ depends on: 02 (must understand IAM policies deeply)
      ├──→ depends on: 22 (CloudGoat provides the vulnerable environment)
      ├──→ each escalation path has a corresponding CloudTrail event
      ├──→ detection rules built from: 06 (CloudTrail) + 07 (CloudWatch)
      └──→ prevention via: SCPs (requires AWS Organizations knowledge)

24 — IMDS Attack and Hardening
      │
      ├──→ depends on: 03 (must understand EC2 metadata service)
      ├──→ depends on: 02 (stolen credentials are IAM credentials)
      ├──→ attack generates: GuardDuty UnauthorizedAccess findings (09)
      ├──→ hardening: IMDSv2 enforcement via CLI and Config rule (11)
      └──→ detection: CloudTrail AssumedRole from unexpected IP (17)

25 — S3 Misconfiguration Attacks
      │
      ├──→ depends on: 04 (must understand S3 policies and ACLs)
      ├──→ depends on: 20 (knowing how breaches are investigated makes attacks clearer)
      ├──→ detected by: Macie (12), Config s3-bucket-public-read-prohibited (11)
      └──→ hardening: S3 security baseline script in document 25

26 — Pacu Framework
      │
      ├──→ depends on: 22-25 (need manual knowledge before using automation)
      ├──→ synthesizes: all attack techniques into one automated framework
      ├──→ generates distinctive CloudTrail signature (detectable)
      └──→ teaches: what automated attacks look like for blue team detection
```

### Attack → Detection cross-reference

Every attack in Phase 4 has a detection in Phase 2 and an investigation method in Phase 3:

| Phase 4 Attack | Phase 2 Detection | Phase 3 Investigation |
|---------------|------------------|-----------------------|
| IAM privesc via AttachUserPolicy | GuardDuty Persistence finding · CloudWatch metric filter | CloudTrail AttachUserPolicy event → 17 |
| IMDS credential theft via SSRF | GuardDuty UnauthorizedAccess:EC2 | CloudTrail AssumedRole from external IP → 17 |
| S3 bucket public exposure | Config s3-bucket-public-read-prohibited · Macie | S3 server access logs + CloudTrail → 20 |
| CloudTrail disable attempt | CloudWatch alarm on StopLogging | The attempt itself is in CloudTrail → 17 |
| Lambda code injection for privesc | GuardDuty Lambda Protection | CloudTrail UpdateFunctionCode + Invoke → 17 |
| Pacu enumeration burst | CloudTrail Insights (API rate spike) | CloudWatch Logs Insights query → 17 |
| Secrets Manager dump | GuardDuty CredentialAccess finding | CloudTrail GetSecretValue volume → 17 |

### What Phase 4 unlocks

After Phase 4 you can:
- Run structured attack scenarios against intentionally vulnerable environments
- Execute and recognize all major IAM privilege escalation paths
- Demonstrate the complete SSRF → IMDS → credential theft → lateral movement chain
- Enumerate, exploit, and secure S3 misconfigurations
- Use Pacu for automated AWS reconnaissance and exploitation
- Build detection rules specifically tuned to each attack technique

---

## Capstone — Enterprise Simulation (Documents 27–29)

### The big picture

The capstone is not a new phase — it is a synthesis. It takes the same environment you learned to build in Phase 1, adds all the security controls from Phase 2, executes a realistic attack that requires Phase 4 knowledge to understand, investigates it using Phase 3 methodology, and produces a professional incident report.

```
27 — Architecture Overview
      │
      Answers: what are we building and why?
      Introduces AcmeFintech Ltd — the fictional company
      Maps every architectural decision to a security requirement
      Provides cost breakdown so you know what to expect
      Lists prerequisites so you know when you are ready

28 — Building the Environment
      │
      ├──→ depends on: ALL 26 preceding documents
      ├──→ synthesizes Phase 1: VPC + subnets + route tables + IGW + NAT
      ├──→ synthesizes Phase 1: IAM structure for a 5-person team
      ├──→ synthesizes Phase 2: KMS + Secrets Manager + WAF + GuardDuty
      │                         + Security Hub + Config + CloudTrail
      ├──→ adds new elements: RDS database + ALB + multi-tier security groups
      └──→ produces: a running enterprise environment ready for attack

29 — Attack → Detect → Respond
      │
      ├──→ attack phase uses: Phase 4 techniques (IAM privesc, S3 exfil,
      │                       secrets access, backdoor creation, EC2 mining)
      ├──→ detect phase uses: Phase 2 tools (GuardDuty + Security Hub + CloudTrail)
      ├──→ contain phase uses: Phase 3 playbook (disable IAM, isolate EC2,
      │                        rotate secrets, snapshot for forensics)
      ├──→ investigate phase uses: Phase 3 methods (CloudTrail Logs Insights,
      │                            Flow Log queries, disk forensics)
      ├──→ recover phase uses: Phase 1 knowledge (rebuild from known good)
      └──→ produces: a professional incident report + hardened environment
```

### The capstone dependency graph

```
Phase 1          Phase 2          Phase 3          Phase 4
(build it)    (secure/monitor)  (investigate)    (attack it)
    │               │                │                │
    └───────────────┴────────────────┴────────────────┘
                            │
                            ▼
                   CAPSTONE (docs 27-29)
                   Build → Attack → Detect → Respond
```

---

## Cross-Phase Integration — The Key Relationships

### CloudTrail is the thread that runs through everything

```
Phase 1 (06): Enable CloudTrail — the evidence collection starts
Phase 2 (07): Alert on CloudTrail events — real-time detection
Phase 2 (11): Config uses CloudTrail — configuration change tracking
Phase 3 (17): Analyze CloudTrail — reconstruct attack timelines
Phase 3 (19): CloudTrail drives IAM IR — find every attacker action
Phase 3 (20): CloudTrail finds exfiltrated S3 objects — scope the breach
Phase 4 (26): Pacu generates CloudTrail events — learn what attacks look like
Capstone (29): CloudTrail is the primary evidence source for the simulation
```

### IAM is the foundation everything is built on

```
Phase 1 (02): Build IAM structure — users, groups, roles, policies
Phase 2 (14): KMS key policies are IAM policies — same JSON, same logic
Phase 2 (15): Secrets Manager access controlled by IAM — same model
Phase 3 (19): Compromised IAM is the most common and dangerous incident
Phase 4 (23): IAM privilege escalation — 12 paths through misconfigured IAM
Phase 4 (24): IMDS attack steals IAM role credentials from EC2 metadata
Capstone (28): IAM structure for AcmeFintech — 5 users, 4 groups, 4 roles
Capstone (29): Attack uses IAM escalation; response contains via IAM disable
```

### Security groups are both a defense layer and an incident response tool

```
Phase 1 (05): Build and understand security groups and NACLs
Phase 2 (13): WAF complements security groups at Layer 7
Phase 3 (21): Lambda isolation works by replacing the security group
Phase 4 (23): PassRole + RunInstances attack uses SG to reach the instance
Capstone (28): 5 purpose-built SGs for tiered access control
Capstone (29): Isolation SG applied during containment
```

### Evidence availability depends on logging being set up first

```
If CloudTrail is not enabled (Phase 1 doc 06):
  → Phase 3 doc 17 (CloudTrail analysis) has no logs to analyze
  → Phase 3 doc 19 (IAM IR) cannot reconstruct the attacker timeline
  → Phase 3 doc 20 (S3 investigation) cannot find GetObject events

If VPC Flow Logs are not enabled (Phase 2 doc 10):
  → Phase 3 doc 17 cannot show which IPs the instance connected to
  → Phase 3 doc 20 cannot prove data left the network

If S3 access logging is not enabled (Phase 1 doc 04):
  → Phase 3 doc 20 has no object-level access evidence

If versioning is not enabled (Phase 1 doc 04):
  → Phase 3 doc 20 cannot recover deleted evidence
```

This is why Phase 1 is not just orientation — it is the difference between having evidence and having none.

---

## Skills Progression Map

```
Week 1-3    (Phase 1 docs 01-03)
  You know: What a VPC is, how to launch EC2, what IAM does
  You can:  Build a basic cloud environment from scratch

Week 4-6    (Phase 1 docs 04-08)
  You know: S3 security, network defense layers, audit logging
  You can:  Secure and monitor basic infrastructure

Week 7-9    (Phase 2 docs 09-11)
  You know: Threat detection, network forensics, compliance
  You can:  Detect attacks in real time, prove compliance

Week 10-12  (Phase 2 docs 12-15)
  You know: Central security posture, WAF, KMS, secrets management
  You can:  Operate a basic cloud SOC, protect all data at rest

Week 13-15  (Phase 3 docs 16-18)
  You know: Cloud forensic acquisition, log analysis, memory forensics
  You can:  Acquire and analyze cloud evidence, reconstruct timelines

Week 16-17  (Phase 3 docs 19-21)
  You know: IAM IR playbook, S3 breach scoping, automated response
  You can:  Execute full incident response end-to-end

Week 18-19  (Phase 4 docs 22-26)
  You know: CloudGoat attack scenarios, IAM escalation, IMDS, Pacu
  You can:  Attack AWS environments, build tuned detections

Week 20     (Capstone docs 27-29)
  You know: Everything — you can build, secure, attack, and respond
  You can:  Operate as a cloud security professional
```

---

## Certification Alignment

| AWS Exam Domain | Primary Documents | Phase |
|----------------|------------------|-------|
| Identity & access management | 02, 19, 23 | 1, 3, 4 |
| Network security | 01, 05, 13 | 1, 2 |
| Data protection | 04, 14, 15 | 1, 2 |
| Threat detection | 09, 10, 12 | 2 |
| Incident response | 17, 19, 20, 21 | 3 |
| Compliance | 06, 07, 11 | 1, 2 |
| Infrastructure security | 03, 05, 13, 24 | 1, 2, 4 |

---

## The Single Most Important Rule

> **Log before you need to investigate.**

Every forensic capability in Phase 3 depends on logging decisions made in Phase 1 and Phase 2. CloudTrail must be enabled before the attack, not after. VPC Flow Logs must be running before the breach, not after. S3 access logging must be on before the exfiltration, not after.

In a real incident, the difference between a complete investigation and a dead end is whether someone enabled CloudTrail three months ago. That person is you, after completing document 06.

---

## Quick Reference — Document Index

| # | Document | Phase | Depends On | Unlocks |
|---|----------|-------|-----------|---------|
| 01 | VPC from scratch | 1 | — | Everything |
| 02 | IAM users groups roles | 1 | — | Everything |
| 03 | EC2 instance lifecycle | 1 | 01, 02 | 16, 18, 21, 24 |
| 04 | S3 buckets and policies | 1 | 02 | 06, 14, 20, 25 |
| 05 | Security groups and NACLs | 1 | 01 | 13, 19, 21 |
| 06 | CloudTrail setup | 1 | 04 | 07, 11, 17, 19, 20 |
| 07 | CloudWatch alarms | 1 | 03, 06 | 09, 21 |
| 08 | Billing and cost controls | 1 | — | Budget for all phases |
| 09 | GuardDuty | 2 | 01, 06 | 12, 21, Capstone |
| 10 | VPC Flow Logs | 2 | 01, 04 | 17, 20 |
| 11 | AWS Config | 2 | 04, 02 | 12 |
| 12 | Security Hub | 2 | 09, 11 | Capstone |
| 13 | WAF setup | 2 | 03, 05 | Capstone |
| 14 | KMS encryption | 2 | 02 | 15, 16 |
| 15 | Secrets Manager | 2 | 14, 02 | Capstone |
| 16 | EBS snapshot forensics | 3 | 03, 14 | 17 |
| 17 | CloudTrail log analysis | 3 | 06, 10 | 19, 20, Capstone |
| 18 | Memory acquisition | 3 | 03, 16 | — |
| 19 | Compromised IAM response | 3 | 02, 06, 09 | Capstone |
| 20 | S3 breach investigation | 3 | 04, 06, 10 | Capstone |
| 21 | Lambda auto-isolation | 3 | 09, 05, 02 | Capstone |
| 22 | CloudGoat lab setup | 4 | All Phase 1-3 | 23, 24, 25, 26 |
| 23 | IAM privilege escalation | 4 | 02, 22 | Capstone |
| 24 | IMDS attack and hardening | 4 | 03, 22 | Capstone |
| 25 | S3 misconfiguration attacks | 4 | 04, 22 | Capstone |
| 26 | Pacu framework | 4 | 22-25 | Capstone |
| 27 | Enterprise architecture overview | Capstone | All | 28, 29 |
| 28 | Building the environment | Capstone | All | 29 |
| 29 | Attack detect respond simulation | Capstone | All | Career |

---

*Master Reference Guide · AWS Cybersecurity & Digital Forensics Roadmap*  
*29 documents · 4 phases · 1 capstone · ~20 weeks*
