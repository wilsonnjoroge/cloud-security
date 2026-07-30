# 🚨 Compromised IAM — Incident Response Playbook

> **Phase 3 · Document 19 of 29**  
> **Estimated cost:** Free · **Estimated time:** 60 minutes  
> **Prerequisites:** `02-iam-users-groups-roles.md`, `17-cloudtrail-log-analysis.md`

---

## Why IAM Compromise Is the Most Critical Cloud Incident

In traditional environments, a compromised server is one machine. In AWS, a compromised IAM identity can mean the entire account — spinning up infrastructure, exfiltrating all data, creating backdoors, destroying evidence.

```
Compromised IAM key
      │
      ├── Launch mining instances in every region ($thousands/hour)
      ├── Exfiltrate all S3 data
      ├── Access all Secrets Manager secrets
      ├── Create backdoor IAM users with admin access
      ├── Delete all snapshots and backups
      └── Disable CloudTrail to cover tracks
```

> IAM compromise incidents require immediate, decisive action — every minute of inaction increases both the financial and data loss impact.

---

## The IAM Incident Response Playbook

```
DETECT → SCOPE → CONTAIN → ERADICATE → RECOVER → DOCUMENT
```

---

## Step 1 — DETECT: Recognize the Indicators

### GuardDuty alerts that indicate IAM compromise

| Finding | Meaning |
|---------|---------|
| `UnauthorizedAccess:IAMUser/ConsoleLoginSuccess.B` | Login from unusual location |
| `UnauthorizedAccess:IAMUser/MaliciousIPCaller` | API calls from known malicious IP |
| `CredentialAccess:IAMUser/AnomalousBehavior` | Unusual credential usage pattern |
| `Persistence:IAMUser/UserPermissions` | IAM permission changes |
| `Stealth:IAMUser/CloudTrailLoggingDisabled` | Attempt to disable logging |

### CloudTrail indicators

```sql
-- Impossible travel: same user from two different countries within minutes
fields eventTime, userIdentity.userName, sourceIPAddress
| filter userIdentity.userName = "dev-alice"
| filter eventName = "ConsoleLogin"
| sort eventTime asc

-- API calls from a new IP never used before
fields eventTime, sourceIPAddress
| filter userIdentity.userName = "dev-alice"
| stats count(*) as calls by sourceIPAddress
| sort calls asc
-- New IPs with low call counts are suspicious — may be first-time attacker use

-- High-volume API calls (automated enumeration)
fields userIdentity.userName, eventName
| filter userIdentity.userName = "dev-alice"
| stats count(*) as calls by bin(5m), userIdentity.userName
| sort calls desc
-- Sudden spike in API call volume
```

---

## Step 2 — SCOPE: Determine What Was Compromised

Before containing, understand exactly what you are dealing with:

```bash
# === What type of credential was compromised? ===

# IAM user with console access?
aws iam get-login-profile --user-name dev-alice

# IAM user with access keys?
aws iam list-access-keys --user-name dev-alice

# IAM role (temporary credentials)?
# Check CloudTrail for AssumeRole events

# === What permissions does this identity have? ===
aws iam list-attached-user-policies --user-name dev-alice
aws iam list-user-policies --user-name dev-alice
aws iam list-groups-for-user --user-name dev-alice
# Check each group's policies too

# === When were the credentials created/last used? ===
aws iam get-credential-report
# Or:
aws iam get-access-key-last-used --access-key-id AKIAIOSFODNN7EXAMPLE

# === What did the attacker do? (CloudTrail) ===
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=dev-alice \
  --start-time $(date -u -d "2 hours ago" +%Y-%m-%dT%H:%M:%SZ) \
  --query 'Events[*].{Time:EventTime,Event:EventName,IP:CloudTrailEvent}' \
  --output table
```

---

## Step 3 — CONTAIN: Stop the Bleeding

**Act fast — do these in order:**

### 3a — Revoke active console sessions

```bash
# This invalidates all temporary console sessions immediately
aws iam delete-login-profile --user-name dev-alice
# Then recreate if needed: aws iam create-login-profile --user-name dev-alice --password NewTempPass --password-reset-required
```

### 3b — Disable access keys

```bash
# List all keys
aws iam list-access-keys --user-name dev-alice

# Disable each key (don't delete yet — you may need key ID for investigation)
aws iam update-access-key \
  --user-name dev-alice \
  --access-key-id AKIAIOSFODNN7EXAMPLE \
  --status Inactive
```

### 3c — Attach an explicit deny policy

This is a belt-and-suspenders approach — even if you missed a key or session, this denies everything:

```bash
# Create the deny-all policy
aws iam create-policy \
  --policy-name EMERGENCY-DENY-ALL \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*"
    }]
  }'

# Attach it to the compromised user
aws iam attach-user-policy \
  --user-name dev-alice \
  --policy-arn arn:aws:iam::ACCOUNT-ID:policy/EMERGENCY-DENY-ALL
```

> The deny policy overrides any allow policies — guaranteed lockout even if the attacker added permissions you haven't found yet.

### 3d — Revoke all active sessions for a role (if role was compromised)

```bash
# For compromised roles — invalidate all temporary credentials
aws iam put-role-policy \
  --role-name CompromisedRole \
  --policy-name DenyAll \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "DateLessThan": {
          "aws:TokenIssueTime": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"
        }
      }
    }]
  }'
```

This denies all sessions issued before right now — forcing re-authentication.

---

## Step 4 — SCOPE EXPANSION: Find All Backdoors

The attacker likely created persistence mechanisms. Find them all:

```bash
# === New IAM users created ===
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateUser \
  --start-time $(date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ)

# === New access keys created ===
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateAccessKey

# === New admin policies attached ===
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AttachUserPolicy

# === Users added to admin groups ===
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AddUserToGroup

# === New roles created (cross-account backdoor) ===
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateRole

# === New identity providers (SAML/OIDC backdoor) ===
aws iam list-saml-providers
aws iam list-open-id-connect-providers
```

For each backdoor found:

```bash
# Disable backdoor user
aws iam delete-login-profile --user-name attacker-backdoor
aws iam update-access-key --user-name attacker-backdoor --access-key-id AKIA... --status Inactive

# Remove from groups
aws iam remove-user-from-group --user-name attacker-backdoor --group-name admin-group

# Detach policies
aws iam detach-user-policy --user-name attacker-backdoor --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Delete the backdoor user
aws iam delete-user --user-name attacker-backdoor
```

---

## Step 5 — SCOPE EXPANSION: Check All Regions

Attackers often launch resources in regions you don't monitor. Check every region:

```bash
# Check for EC2 instances in all regions
for region in $(aws ec2 describe-regions --query 'Regions[*].RegionName' --output text); do
  echo "=== $region ==="
  aws ec2 describe-instances \
    --region $region \
    --filters "Name=instance-state-name,Values=running,stopped,pending" \
    --query 'Reservations[*].Instances[*].{ID:InstanceId,State:State.Name,Type:InstanceType,Launch:LaunchTime}' \
    --output table 2>/dev/null
done

# Check for S3 buckets (global but check all)
aws s3api list-buckets \
  --query 'Buckets[*].{Name:Name,Created:CreationDate}' \
  --output table

# Check CloudTrail — were new trails created (to log to attacker-controlled bucket)?
aws cloudtrail describe-trails --include-shadow-trails true

# Check for new SNS subscriptions (data exfiltration via events)
for region in us-east-1 us-east-2 us-west-2 eu-west-1; do
  echo "=== $region ==="
  aws sns list-subscriptions --region $region
done
```

---

## Step 6 — ERADICATE: Remove All Attacker Presence

```bash
# === Rotate all secrets that may have been accessed ===
# (check CloudTrail GetSecretValue events to know which ones)
aws secretsmanager rotate-secret --secret-id lab/database/credentials
aws secretsmanager rotate-secret --secret-id lab/api/external-service

# === Rotate all access keys for all users ===
# For each IAM user:
OLD_KEY=$(aws iam list-access-keys --user-name USERNAME --query 'AccessKeyMetadata[0].AccessKeyId' --output text)
aws iam create-access-key --user-name USERNAME  # Create new first
aws iam delete-access-key --user-name USERNAME --access-key-id $OLD_KEY

# === Invalidate all EC2 key pairs used by the compromised identity ===
# Attacker may have created new key pairs to SSH in
aws ec2 describe-key-pairs
# Delete any unknown key pairs:
aws ec2 delete-key-pair --key-name suspicious-keypair

# === Remove attacker-created security group rules ===
# Check Config timeline for security group changes during the incident
# Revert to known good state

# === Terminate attacker-launched instances ===
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*attacker*" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text | xargs -I {} aws ec2 terminate-instances --instance-ids {}
```

---

## Step 7 — RECOVER: Restore and Harden

```bash
# === Re-enable the legitimate user with new credentials ===
aws iam create-login-profile \
  --user-name dev-alice \
  --password "$(openssl rand -base64 24)" \
  --password-reset-required

# Remove the emergency deny policy
aws iam detach-user-policy \
  --user-name dev-alice \
  --policy-arn arn:aws:iam::ACCOUNT-ID:policy/EMERGENCY-DENY-ALL

# === Enable MFA for all users (enforcement) ===
# Create an MFA-enforcement policy and attach to all users
# (Denies all actions unless MFA is used)

# === Review and tighten IAM policies ===
# Remove any over-permissive policies added by attacker
# Apply least privilege review across all identities

# === Re-enable CloudTrail if it was disabled ===
aws cloudtrail start-logging --name lab-audit-trail

# === Verify GuardDuty is still enabled ===
aws guardduty list-detectors
```

---

## Step 8 — Post-Incident Actions

### Determine root cause

Common root causes of IAM compromise:

| Root cause | How to detect | Prevention |
|-----------|--------------|-----------|
| Access key committed to GitHub | GitHub secret scanning | Use Secrets Manager, not hardcoded keys |
| Phishing attack | Login from new IP/geo | MFA, SSO |
| EC2 IMDS attack | SSRF in app logs | Enforce IMDSv2 |
| Insider threat | Unusual hours/location | Behavior analytics |
| Third-party breach | Verify with vendor | Rotate keys after any vendor incident |

### Immediate hardening based on root cause

```bash
# If access key was leaked — enforce key rotation policy
aws iam create-account-password-policy \
  --max-password-age 90 \
  --require-uppercase-characters \
  --require-lowercase-characters \
  --require-numbers \
  --minimum-password-length 14

# If IMDS attack — enforce IMDSv2 on all instances
aws ec2 modify-instance-metadata-options \
  --instance-id i-xxx \
  --http-tokens required \
  --http-endpoint enabled

# Enforce IMDSv2 at account level via SCP (if using AWS Organizations)
```

---

## IAM Incident Response Checklist

```
IMMEDIATE (first 10 minutes):
  [ ] Disable compromised user/key
  [ ] Attach emergency deny policy
  [ ] Notify security team and management
  [ ] Preserve CloudTrail logs (verify still running)

SHORT TERM (first hour):
  [ ] Scope all activity via CloudTrail
  [ ] Find all backdoors (new users, keys, roles)
  [ ] Check all regions for attacker infrastructure
  [ ] Rotate all secrets that may have been accessed

MEDIUM TERM (first day):
  [ ] Determine root cause
  [ ] Eradicate all attacker presence
  [ ] Re-enable legitimate access with fresh credentials + MFA
  [ ] Assess data loss and breach notification requirements

LONG TERM (first week):
  [ ] Implement root cause fix
  [ ] Update incident response procedures
  [ ] Brief all team members
  [ ] Write post-incident report
  [ ] Schedule security review
```

---

## Phase 3 Progress Tracker

- [x] EBS snapshot forensics
- [x] CloudTrail log analysis
- [x] Memory acquisition on EC2
- [x] Compromised IAM incident response
- [ ] S3 breach investigation
- [ ] Lambda auto-isolation

---

*Phase 3 · AWS Cybersecurity & Digital Forensics Roadmap*
