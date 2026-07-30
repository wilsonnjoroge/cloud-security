# 🔐 IAM : Users, Groups, Roles & Policies

> **Phase 1 · Document 2 of 29**  
> **Estimated cost:** Free (IAM has no cost)  
> **Estimated time:** 60–90 minutes  
> **Prerequisite:** `01-vpc-from-scratch.md`

---

## What Is IAM?

IAM (Identity and Access Management) is how AWS controls **who can do what** on your account. Every action in AWS — launching an instance, reading an S3 bucket, deleting a database — goes through IAM first.

```
Request → IAM checks identity → IAM checks permissions → Allow or Deny
```

> **Forensics relevance:** Compromised IAM credentials are the #1 cause of cloud breaches. Understanding IAM deeply means you can both prevent attacks and investigate them when they happen.

---

## The Four Core Concepts

| Concept | What it is | Real-world analogy |
|---------|-----------|-------------------|
| **User** | A permanent identity for a person or app | An employee badge |
| **Group** | A collection of users sharing permissions | A department |
| **Role** | A temporary identity assumed by a service or person | A visitor pass |
| **Policy** | A JSON document defining allowed/denied actions | An access control list |

---

## The Golden Rule of IAM

> **Principle of Least Privilege:** Give only the permissions needed — nothing more.  
> A developer who only needs to read S3 should never have EC2 or IAM permissions.

---

## Step 1 — Enable MFA on Your Root Account

Before creating anything, secure the root account. The root account has unlimited power and cannot be restricted by IAM policies.

```
Top-right → your account name → Security credentials
→ Multi-factor authentication → Assign MFA device
→ Authenticator app → scan QR code with Google Authenticator or Authy
```

> ⚠️ **Never use the root account for daily work.** Create an admin IAM user (Step 2) and use that instead. Root is for emergencies only.


---

## Step 2 — Create an Admin IAM User

**Console path:** `IAM → Users → Create user`

| Field | Value |
|-------|-------|
| Username | `admin-yourname` |
| AWS Management Console access | Enable |
| Console password | Custom → set a strong password |
| Require password reset | Uncheck (for your own admin account) |

### Attach permissions
On the permissions page, select **Attach policies directly** and attach:

- `AdministratorAccess`

> This user now has full AWS access — but unlike root, their actions are fully logged in CloudTrail and they can be restricted or deleted.

Click **Create user** → download or save the credentials.


![Access IAM](../screenshots/iam/01-access-iam-a.png)

![Create Admin User](../screenshots/iam/01-crate-admin-user-a.png)

![](../screenshots/iam/01-crate-admin-user-b.png)

![](../screenshots/iam/01-crate-admin-user-c.png)

![](../screenshots/iam/01-crate-admin-user-d.png)

---

## Step 3 — Create Groups

Groups let you manage permissions at scale. Instead of assigning policies to each user, you assign them to the group.

**Console path:** `IAM → User groups → Create group`

### Group 1 — Developers

| Field | Value |
|-------|-------|
| Group name | `lab-developers` |
| Attach policies | `AmazonEC2FullAccess`, `AmazonS3FullAccess` |

### Group 2 — Security Analysts

| Field | Value |
|-------|-------|
| Group name | `lab-security` |
| Attach policies | `SecurityAudit`, `AmazonGuardDutyReadOnlyAccess` |

### Group 3 — Read Only

| Field | Value |
|-------|-------|
| Group name | `lab-readonly` |
| Attach policies | `ReadOnlyAccess` |


![Create Groups](../screenshots/iam/03-crate-groups-a.png)

![](../screenshots/iam/03-crate-groups-b.png)

![](../screenshots/iam/03-crate-groups-c.png)

---

## Step 4 — Create IAM Users and Assign to Groups

**Console path:** `IAM → Users → Create user`

Create three users to simulate a team:

| Username | Group | Purpose |
|----------|-------|---------|
| `dev-willy` | `lab-developers` | Simulates a developer |
| `sec-voke` | `lab-security` | Simulates a security analyst |
| `readonly-josh` | `lab-readonly` | Simulates an auditor |

For each user:
- Enable **console access**
- Set a temporary password
- Add to the appropriate group on the permissions page

> **Note:** Do not attach policies directly to users. Always go through groups. This makes permission management scalable and auditable.


![Create IAM Users](../screenshots/iam/04-crate-iam-users-a.png)

![](../screenshots/iam/04-crate-iam-users-b.png)

![](../screenshots/iam/04-crate-iam-users-c.png)

![](../screenshots/iam/04-crate-iam-users-d.png)

---

## Step 5 — Create a Custom Policy

AWS managed policies are broad. In real environments you write custom policies scoped to exactly what is needed.

**Console path:** `IAM → Policies → Create policy → JSON`

Paste this policy — it allows a user to list and read from S3 but nothing else:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ReadOnly",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::lab-*",
        "arn:aws:s3:::lab-*/*"
      ]
    }
  ]
}
```

| Field | Value |
|-------|-------|
| Policy name | `lab-s3-readonly-policy` |
| Description | `Read-only access to lab S3 buckets only` |

> **Breaking down the policy:**
> - `Effect: Allow` — this grants access (alternative is `Deny`)
> - `Action` — exactly what is permitted
> - `Resource` — the ARN pattern this applies to (`lab-*` means any bucket starting with "lab-")

![Create a Custom Policy](../screenshots/iam/05-crate-custom-policies-lab1-s3-a.png)

![](../screenshots/iam/05-crate-custom-policies-lab1-s3-b.png)

---

## Step 6 — Create an IAM Role for EC2

Roles are used when AWS services need to talk to each other. Instead of putting credentials inside an EC2 instance (dangerous), you attach a role.

**Console path:** `IAM → Roles → Create role`

| Field | Value |
|-------|-------|
| Trusted entity | AWS service |
| Use case | EC2 |
| Permissions | `AmazonS3ReadOnlyAccess` |
| Role name | `lab-ec2-s3-read-role` |


![Create an IAM Role](../screenshots/iam/06-crate-custom-role-lab1-ec2-a.png)

![](../screenshots/iam/06-crate-custom-role-lab1-ec2-b.png)

![](../screenshots/iam/06-crate-custom-role-lab1-ec2-c.png)

![](../screenshots/iam/06-crate-custom-role-lab1-ec2-d.png)


### Attach the role to your EC2 instance

```
EC2 → Instances → select lab-web-server
→ Actions → Security → Modify IAM role
→ Select lab-ec2-s3-read-role → Update
```

Your EC2 instance can now read from S3 without any hardcoded credentials. This is how all production systems should be configured.


![Attach role to EC2](../screenshots/iam/07-assign-custom-role-lab1-ec2-a.png)

![Attach role to EC2](../screenshots/iam/07-assign-custom-role-lab1-ec2-b.png)

---

## Step 7 — Test Permissions (Important)

Testing confirms your policies actually work as intended.

### Test as dev-willy

Log out → log back in as `dev-willy`

```
Try: EC2 → Launch instance         → should work
Try: IAM → Users                   → should be denied
Try: S3 → Create bucket            → should work
```

![Launch instance](../screenshots/iam/08-dev-willy-launch-ec2-instance.png)

![List Users](../screenshots/iam/08-dev-willy-list-users.png)

![Create bucket](../screenshots/iam/08-dev-willy-create-s3-bucket.png)


### Test as sec-voke

```
Try: GuardDuty → view findings     → should work
Try: EC2 → Terminate instance      → should be denied
```

![Access GuardDuty](../screenshots/iam/to-be-included.png)

![Terminate EC2 Instance](../screenshots/iam/08-sec-voke-terminate-ec2-instance.png)


### Test as readonly-josh

```
Try: EC2 → view instances          → should work
Try: EC2 → Launch instance         → should be denied
Try: S3 → view buckets             → should work
Try: S3 → Delete bucket            → should be denied
```

![View EC2 Instances](../screenshots/iam/08-readonly-josh-view-ec2-instances.png)

![Launch EC2 Instances](../screenshots/iam/08-readonly-josh-launch-ec2-instance.png)

![View S3 Buckets](../screenshots/iam/08-readonly-josh-view-s3-buckets.png)

![Delete S3 Buckets](../screenshots/iam/08-readonly-josh-delete-s3-buckets.png)


> **Why test?** In security, untested controls are untrustworthy controls. Always verify your policies behave as intended — both the Allow and the Deny sides.

---

## Step 8 — Create Access Keys (CLI Access)

Access keys allow programmatic access to AWS (CLI, scripts, automation).

**Console path:** `IAM → Users → dev-willy → Security credentials → Create access key`

Select use case: **CLI**

```
Access key ID:     AKIAIOSFODNN7-EXAMPLE
Secret access key: wJalrXUtnFEMI/K7MDENG/bPxRfiCY-EXAMPLE-KEY
```

> ⚠️ **Access key security rules:**
> - Never commit access keys to Git
> - Never put them in code or config files
> - Rotate them every 90 days
> - Delete keys that are no longer used
> - Prefer roles over access keys wherever possible

Configure the CLI on your machine:

```bash
aws configure
# AWS Access Key ID: paste key
# AWS Secret Access Key: paste secret
# Default region: us-east-2
# Default output format: json
```

Test it:

```bash
aws sts get-caller-identity
```

Expected output:

```json
{
    "UserId": "AIDAIOSFODNN7EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/dev-willy"
}
```

---

## Step 9 — IAM Credential Report (Forensics Tool)

The credential report shows the security status of every IAM user on the account — last login, MFA status, key age, last key use.

```
IAM → Credential report → Download report
```

This CSV file is one of the first things you pull during a cloud incident investigation. It tells you:
- Who has active access keys (and when they were last used)
- Who does not have MFA enabled
- Which accounts have never been used (potential ghost accounts)

> **Forensics challenge:** Open the report and answer:
> - Does every user have MFA enabled?
> - Are there any access keys older than 90 days?
> - Are there any users who have never logged in?

---

## Step 10 — Enable IAM Access Analyzer

Access Analyzer scans your account and flags any resources that are accessible from outside your account — a critical misconfiguration detector.

```
IAM → Access analyzer → Create analyzer
  Analyzer name: lab-analyzer
  Zone of trust:  Current account
```

After a few minutes it will show findings for any S3 buckets, IAM roles, or other resources with external access.

> In a forensic investigation, Access Analyzer findings can reveal backdoors left by an attacker — external roles or bucket policies granting persistent access even after credentials are rotated.

---

## IAM Best Practices Summary

| Practice | Why it matters |
|----------|---------------|
| Enable MFA on root and all users | Credential theft alone is not enough to gain access |
| Never use root for daily tasks | Root actions cannot be restricted or audited by IAM |
| Use groups, not direct user policies | Scalable, auditable, consistent |
| Use roles for services, not access keys | No long-lived credentials to steal |
| Apply least privilege | Limits blast radius of any compromise |
| Rotate access keys every 90 days | Limits window of exposure for leaked keys |
| Review credential report monthly | Detects stale and ghost accounts |
| Enable Access Analyzer | Detects unintended external access |

---

## Cleanup

IAM resources are free — no cleanup needed for cost purposes. However for hygiene:

```
1. Delete access keys for test users when done with CLI exercises
2. You can leave users, groups, and roles — they cost nothing
```

---

## IAM Cheat Sheet

```
User    → permanent identity → for humans and apps needing long-term access
Group   → collection of users → assign policies here, not to users directly
Role    → temporary identity → for AWS services and cross-account access
Policy  → JSON permission document → attached to users, groups, or roles

ARN format: arn:aws:iam::ACCOUNT-ID:user/USERNAME
                          ^^^^^^^^^^^ your 12-digit AWS account number
```

---

## Phase 1 Progress Tracker

- [x] VPC from scratch
- [x] IAM users, groups, roles, policies
- [ ] EC2 instance lifecycle
- [ ] S3 buckets and policies
- [ ] Security groups and NACLs
- [ ] CloudTrail setup
- [ ] CloudWatch alarms
- [ ] Billing and cost controls

---

*Phase 1 · AWS Cybersecurity & Digital Forensics Roadmap*
