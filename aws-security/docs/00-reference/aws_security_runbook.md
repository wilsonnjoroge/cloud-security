# AWS Cloud Security Lab — Operational Runbook
### Exact Commands · Expected Output · Verification Steps

**Document Type:** Technical Runbook
**Version:** 1.0
**Environment:** AWS Educate Free Tier · EC2 (t3.micro) · Kali Linux (VMware NAT) · us-east-1
**Companion To:** `aws_security_methodology.md` · `README.md`

---

## Placeholder Reference

| Placeholder | Description |
|---|---|
| `<ACCOUNT_ID>` | Your 12-digit AWS account ID |
| `<BASTION_IP>` | Public IP of bastion EC2 instance |
| `<APP_PRIVATE_IP>` | Private IP of application EC2 (10.0.2.x) |
| `<YOUR_IP>` | Your Kali VM public IP — `curl ifconfig.me` |
| `<REGION>` | Primary region — `us-east-1` |
| `<TRAIL_BUCKET>` | CloudTrail S3 bucket name |
| `<SNS_EMAIL>` | Email address subscribed to SNS alerts |
| `<ADMIN_USER>` | IAM admin username — `admin-wilson` |
| `<DEV_USER>` | IAM developer username — `developer-user` |
| `<AUDITOR_USER>` | IAM auditor username — `readonly-auditor` |

---

## How to Use This Runbook

Every test follows the same six-step validation cycle. Do not skip steps — a skipped step means the detection is assumed, not verified.

```
STEP 1 — Generate the event       Run the exact command on the correct system
STEP 2 — Confirm raw event        CloudTrail Event History · source log · VPC Flow Log
STEP 3 — Confirm ingestion        CloudTrail → Event History · CloudWatch Logs → Discover
STEP 4 — Confirm detection fired  CloudWatch Alarm · GuardDuty Finding · Config Rule
STEP 5 — Confirm notification     Check email inbox for SNS alert; record detection latency
STEP 6 — Tune if missing          See troubleshooting note in each section
```

---

## Pre-Flight Checks

Run these before any test phase. If these fail, nothing downstream will work.

### 1. Confirm AWS CLI Is Configured on Kali

```bash
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXXX",
    "Account": "<ACCOUNT_ID>",
    "Arn": "arn:aws:iam::<ACCOUNT_ID>:user/admin-wilson"
}
```

If this fails: `aws configure` — enter access key, secret key, region `us-east-1`, output `json`.

### 2. Confirm CloudTrail Is Active and Delivering

```bash
aws cloudtrail get-trail-status --name cloud-security-lab-trail
```

Expected: `"IsLogging": true` and `LatestDeliveryTime` within the last hour.

```bash
aws cloudtrail describe-trails --include-shadow-trails false
```

Expected: `"IsMultiRegionTrail": true` and `"LogFileValidationEnabled": true`.

### 3. Confirm CloudWatch Log Group Exists for CloudTrail

```bash
aws logs describe-log-groups --log-group-name-prefix "CloudTrail"
```

Expected: log group `CloudTrail/cloud-security-lab` listed with a recent `lastIngestionTime`.

### 4. Confirm GuardDuty Is Enabled

```bash
aws guardduty list-detectors
```

Expected: a detector ID returned. If empty — GuardDuty is not enabled.

```bash
# Get detector status
DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
aws guardduty get-detector --detector-id $DETECTOR_ID
```

Expected: `"Status": "ENABLED"`.

### 5. Confirm SNS Subscription Is Confirmed

```bash
aws sns list-subscriptions
```

Expected: your email listed with `"SubscriptionArn"` as a full ARN (not `PendingConfirmation`).

If `PendingConfirmation`: check your inbox and click the confirmation link AWS sent.

### 6. Confirm EC2 Instances Are Running

```bash
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,PublicIpAddress,PrivateIpAddress,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

Expected: both bastion and application instances listed as running.

---

---

# PHASE 1 — AUDIT BASELINE
**Goal:** Confirm all logging pipelines are active and flowing before any attack simulations run. Nothing in Phase 2–6 is valid if Phase 1 is not verified.

---

## 1.1 — Generate a Known CloudTrail Event and Verify End-to-End

**On Kali — make a benign API call:**
```bash
aws ec2 describe-instances --region us-east-1
```

**Verify in CloudTrail Event History:**
```
AWS Console → CloudTrail → Event History
Filter: Event name = DescribeInstances
```

Expected: event visible within 15 minutes with correct `userIdentity`, `sourceIPAddress`, and `requestParameters`.

**Verify in CloudWatch Logs:**
```
AWS Console → CloudWatch → Log Groups → CloudTrail/cloud-security-lab
→ Search log stream for: DescribeInstances
```

Expected: same event visible in CloudWatch Logs — confirms the CloudTrail → CloudWatch Logs delivery pipeline is working.

**Tune if missing:** Check the CloudTrail trail has CloudWatch Logs integration enabled. Under trail settings, confirm a CloudWatch Logs log group and IAM role are assigned.

---

## 1.2 — Confirm S3 CloudTrail Log Delivery

```bash
aws s3 ls s3://<TRAIL_BUCKET>/AWSLogs/<ACCOUNT_ID>/CloudTrail/us-east-1/ \
  --recursive | tail -5
```

Expected: `.json.gz` log files with timestamps from the last hour.

**Download and inspect a log file:**
```bash
aws s3 cp s3://<TRAIL_BUCKET>/AWSLogs/<ACCOUNT_ID>/CloudTrail/us-east-1/$(date +%Y/%m/%d)/ \
  ./cloudtrail-sample/ --recursive --exclude "*" --include "*.json.gz"

gunzip -c cloudtrail-sample/*.json.gz | python3 -m json.tool | head -80
```

Expected: readable JSON events with `eventName`, `userIdentity`, `sourceIPAddress`, and `eventTime`.

**Tune if missing:** Confirm the trail S3 bucket policy allows CloudTrail to write. The bucket policy must include `"Principal": {"Service": "cloudtrail.amazonaws.com"}` with `s3:PutObject` permission.

---

## 1.3 — Validate CloudTrail Log File Integrity

```bash
aws cloudtrail validate-logs \
  --trail-arn arn:aws:cloudtrail:<REGION>:<ACCOUNT_ID>:trail/cloud-security-lab-trail \
  --start-time $(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ) \
  --verbose
```

Expected output:
```
Validating log files for trail arn:aws:cloudtrail:...
...
Results requested for 2026/...
...
No invalid log files found.
```

Any `invalid` result means a log file was modified or deleted after delivery — treat as a security incident.

---

## 1.4 — Confirm VPC Flow Logs Are Active

```bash
aws ec2 describe-flow-logs \
  --filter "Name=resource-id,Values=<VPC_ID>"
```

Expected: flow log listed with `"FlowLogStatus": "ACTIVE"` delivering to CloudWatch Logs or S3.

**Generate test traffic and confirm:**
```bash
# On Kali — ping the bastion
ping -c 5 <BASTION_IP>

# On Wazuh/Kali — check flow log group
aws logs filter-log-events \
  --log-group-name VPCFlowLogs \
  --filter-pattern "<BASTION_IP>" \
  --limit 5
```

Expected: flow log entries showing `ACCEPT` for ICMP traffic from `<YOUR_IP>` to `<BASTION_IP>`.

---

---

# PHASE 2 — IDENTITY CONTROLS
**Goal:** Validate IAM privilege controls, MFA enforcement, permission boundaries, and alert on identity-related events.

---

## 2.1 — Root Account Login Detection

> This test requires logging into the AWS console as root. Do this once — confirm the alarm fires — then immediately log out and never use root again.

**Action:**
```
AWS Console → Sign in as root account (email + password + MFA)
```

**Verify in CloudTrail:**
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=ConsoleLogin \
  --query 'Events[?contains(Username, `Root`)]'
```

Expected: event with `"userIdentity": {"type": "Root"}`.

**Verify CloudWatch alarm fired:**
```
AWS Console → CloudWatch → Alarms → RootAccountUsage → state: ALARM
```

**Verify SNS email received:**
Subject: `ALARM: RootAccountUsage`
Body: includes account ID, event time, and source IP.

Record time of login vs. time of email — this is your detection latency.

**Expected Alert:**
| Alarm Name | State | SNS Email |
|---|---|---|
| RootAccountUsage | ALARM | Yes — within 5 minutes |

**Tune if missing:** Confirm the CloudWatch metric filter pattern is: `{ $.userIdentity.type = "Root" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != "AwsServiceEvent" }`. Confirm the metric filter is applied to the correct CloudWatch log group (the one CloudTrail delivers to).

---

## 2.2 — IAM Policy Change Detection

**On Kali — attach a policy directly to a user (intentional misconfiguration):**
```bash
aws iam attach-user-policy \
  --user-name <DEV_USER> \
  --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
```

**Verify in CloudTrail:**
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AttachUserPolicy \
  --max-results 3
```

Expected: event showing `userName: developer-user` and `policyArn: ReadOnlyAccess`.

**Verify CloudWatch alarm fired:**
```
CloudWatch → Alarms → IAMPolicyChange → state: ALARM
```

**Clean up — detach the policy:**
```bash
aws iam detach-user-policy \
  --user-name <DEV_USER> \
  --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
```

**Expected Alert:**
| Alarm Name | State | Triggering Event |
|---|---|---|
| IAMPolicyChange | ALARM | AttachUserPolicy |

**Tune if missing:** Metric filter pattern: `{ ($.eventName=DeleteGroupPolicy) || ($.eventName=DeleteRolePolicy) || ($.eventName=DeleteUserPolicy) || ($.eventName=PutGroupPolicy) || ($.eventName=PutRolePolicy) || ($.eventName=PutUserPolicy) || ($.eventName=CreatePolicy) || ($.eventName=DeletePolicy) || ($.eventName=CreatePolicyVersion) || ($.eventName=DeletePolicyVersion) || ($.eventName=SetDefaultPolicyVersion) || ($.eventName=AttachRolePolicy) || ($.eventName=DetachRolePolicy) || ($.eventName=AttachUserPolicy) || ($.eventName=DetachUserPolicy) || ($.eventName=AttachGroupPolicy) || ($.eventName=DetachGroupPolicy) }`.

---

## 2.3 — Permission Boundary Enforcement Validation

**Confirm developer-user cannot exceed their boundary — attempt a forbidden action:**
```bash
# Assume developer-user credentials (use the developer-user access key)
aws configure --profile developer

# Attempt to list IAM users — should be denied by permission boundary
aws iam list-users --profile developer
```

Expected:
```
An error occurred (AccessDenied) when calling the ListUsers operation:
User: arn:aws:iam::<ACCOUNT_ID>:user/developer-user is not authorized to perform: iam:ListUsers
```

**Verify in CloudTrail:**
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=ListUsers \
  --max-results 3
```

Expected: event with `"errorCode": "AccessDenied"`.

**Verify CloudWatch alarm fired:**
```
CloudWatch → Alarms → UnauthorisedAPICall → state: ALARM
```

**Expected Alert:**
| Alarm Name | Triggering Event | errorCode |
|---|---|---|
| UnauthorisedAPICall | ListUsers | AccessDenied |

**Tune if missing:** Metric filter pattern: `{ ($.errorCode = "*UnauthorizedAccess*") || ($.errorCode = "AccessDenied") }`.

---

## 2.4 — MFA Enforcement Validation

**Test that a user without MFA cannot access the console for sensitive operations:**

On Kali — attempt an IAM operation using credentials without MFA session token:
```bash
# Using developer-user long-term credentials (no MFA session)
aws iam create-user --user-name test-no-mfa --profile developer
```

Expected (if MFA condition is in policy):
```
An error occurred (AccessDenied) when calling the CreateUser operation:
An MFA device is required to perform this action.
```

The IAM group policy should include this condition:
```json
{
  "Effect": "Deny",
  "Action": "*",
  "Resource": "*",
  "Condition": {
    "BoolIfExists": {
      "aws:MultiFactorAuthPresent": "false"
    }
  }
}
```

If the action succeeds without MFA — the condition is missing. Add it to the group policy and retest.

---

## 2.5 — EC2 IAM Role Scope Validation

**SSH into the EC2 instance and confirm the role scope:**
```bash
ssh -i cyberninja-key.pem ubuntu@<BASTION_IP>
```

**On the EC2 instance — confirm the role is attached:**
```bash
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

Expected: `ec2-ssm-role` returned.

**Confirm IMDSv2 is required (IMDSv1 should be blocked):**
```bash
# This should fail — IMDSv1 request (no token)
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/ec2-ssm-role
```

Expected: `401 - Unauthorized` — IMDSv1 blocked.

**IMDSv2 request (correct method):**
```bash
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/ec2-ssm-role
```

Expected: temporary credentials JSON with `AccessKeyId`, `SecretAccessKey`, `Token`, and `Expiration`.

**Confirm role cannot access out-of-scope resources:**
```bash
# Attempt to list all S3 buckets from inside EC2 — should be denied
aws s3 ls
```

Expected: `AccessDenied` — role only has `s3:GetObject` on a specific path, not `s3:ListAllMyBuckets`.

---

---

# PHASE 3 — NETWORK CONTROLS
**Goal:** Validate VPC segmentation, security group enforcement, NACL rules, and GuardDuty network findings.

---

## 3.1 — Confirm Application EC2 Is Not Reachable Directly

**From Kali — attempt to SSH directly to the application EC2 private IP (should fail):**
```bash
ssh -i cyberninja-key.pem ubuntu@<APP_PRIVATE_IP>
```

Expected: connection times out — `<APP_PRIVATE_IP>` is in a private subnet with no internet gateway route. Not reachable from the internet.

**Confirm via VPC route table:**
```bash
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=<PRIVATE_SUBNET_ID>" \
  --query 'RouteTables[].Routes[]'
```

Expected: no route `0.0.0.0/0` via `igw-` (internet gateway). Only a local route `10.0.0.0/16`.

---

## 3.2 — Security Group — Confirm SSH Source Restriction

**Verify bastion security group only allows SSH from your IP:**
```bash
aws ec2 describe-security-groups \
  --group-ids <SG_BASTION_ID> \
  --query 'SecurityGroups[].IpPermissions'
```

Expected:
```json
[{
    "FromPort": 22,
    "ToPort": 22,
    "IpProtocol": "tcp",
    "IpRanges": [{"CidrIp": "<YOUR_IP>/32"}]
}]
```

`0.0.0.0/0` appearing here is a critical misconfiguration.

**Attempt SSH from a different IP (confirm it is blocked):**

If you have access to a second machine or a proxy, attempt SSH from a non-whitelisted IP. Expected: connection refused or timeout.

---

## 3.3 — Security Group Change Detection

**Introduce a deliberate misconfiguration — open SSH to the world:**
```bash
aws ec2 authorize-security-group-ingress \
  --group-id <SG_BASTION_ID> \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0
```

**Verify in CloudTrail:**
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AuthorizeSecurityGroupIngress \
  --max-results 3
```

**Verify CloudWatch alarm fired:**
```
CloudWatch → Alarms → SecurityGroupChange → state: ALARM
```

**Verify AWS Config flagged it:**
```
AWS Console → Config → Rules → restricted-ssh → NON_COMPLIANT
Resource: <SG_BASTION_ID>
```

**Remediate immediately:**
```bash
aws ec2 revoke-security-group-ingress \
  --group-id <SG_BASTION_ID> \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0
```

Confirm Config rule returns to COMPLIANT after remediation (may take up to 5 minutes).

**Expected Alerts:**
| Detection | Source | State |
|---|---|---|
| SecurityGroupChange alarm | CloudWatch | ALARM |
| `restricted-ssh` rule | AWS Config | NON_COMPLIANT |
| SNS email | Inbox | Received |

---

## 3.4 — GuardDuty — Port Probe Finding

**From Kali — run an Nmap SYN scan against the bastion:**
```bash
nmap -sS <BASTION_IP>
```

**Check GuardDuty for the finding:**
```bash
DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)

aws guardduty list-findings \
  --detector-id $DETECTOR_ID \
  --finding-criteria '{"Criterion": {"type": {"Eq": ["Recon:EC2/PortProbeUnprotectedPort"]}}}'
```

Expected: finding ID returned within 5–15 minutes of the scan.

```bash
# Get finding details
FINDING_ID=$(aws guardduty list-findings \
  --detector-id $DETECTOR_ID \
  --finding-criteria '{"Criterion": {"type": {"Eq": ["Recon:EC2/PortProbeUnprotectedPort"]}}}' \
  --query 'FindingIds[0]' --output text)

aws guardduty get-findings \
  --detector-id $DETECTOR_ID \
  --finding-ids $FINDING_ID \
  --query 'Findings[0].{Type:Type,Severity:Severity,Region:Region,Resource:Resource.InstanceDetails.InstanceId}'
```

Expected output:
```json
{
    "Type": "Recon:EC2/PortProbeUnprotectedPort",
    "Severity": 2.0,
    "Region": "us-east-1",
    "Resource": "i-083987f..."
}
```

**Tune if missing:** GuardDuty port probe findings require the instance to have an unprotected port exposed. Confirm the bastion has port 22 open in its security group (even restricted to /32). GuardDuty analyses network traffic patterns — allow up to 15 minutes after the scan.

---

## 3.5 — GuardDuty — SSH Brute Force Finding

**From Kali — run Hydra against the bastion:**
```bash
hydra -l ubuntu -P /usr/share/wordlists/metasploit/unix_passwords.txt \
  ssh://<BASTION_IP> -t 4 -V
```

> This will fail to authenticate (correct — we are testing detection, not exploitation). Allow it to run for 2–3 minutes to generate sufficient failed attempts.

**Verify raw log on EC2:**
```bash
ssh -i cyberninja-key.pem ubuntu@<BASTION_IP>
sudo tail -50 /var/log/auth.log | grep "Failed password"
```

Expected: rapid sequence of `Failed password for ubuntu from <YOUR_IP>`.

**Check GuardDuty:**
```bash
aws guardduty list-findings \
  --detector-id $DETECTOR_ID \
  --finding-criteria '{"Criterion": {"type": {"Eq": ["UnauthorizedAccess:EC2/SSHBruteForce"]}}}'
```

Expected: finding returned within 15 minutes.

**Expected Alerts:**
| Finding Type | Severity | Source |
|---|---|---|
| `UnauthorizedAccess:EC2/SSHBruteForce` | Medium (5.0) | GuardDuty |
| SNS email | — | Inbox |

---

---

# PHASE 4 — DATA CONTROLS
**Goal:** Validate S3 security controls, confirm data protection, and verify Config detects drift.

---

## 4.1 — Block Public Access — Misconfiguration Detection

**Introduce a deliberate misconfiguration — disable Block Public Access on the app-data bucket:**
```bash
aws s3api put-public-access-block \
  --bucket app-data-<ACCOUNT_ID> \
  --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
```

**Verify AWS Config flagged it:**
```
AWS Console → Config → Rules → s3-bucket-public-read-prohibited → NON_COMPLIANT
```

Expected: resource `app-data-<ACCOUNT_ID>` listed as non-compliant within 5 minutes.

**Remediate:**
```bash
aws s3api put-public-access-block \
  --bucket app-data-<ACCOUNT_ID> \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

Confirm Config rule returns to COMPLIANT.

---

## 4.2 — Encryption Validation

**Confirm server-side encryption is the bucket default:**
```bash
aws s3api get-bucket-encryption \
  --bucket app-data-<ACCOUNT_ID>
```

Expected:
```json
{
    "ServerSideEncryptionConfiguration": {
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "aws:kms",
                "KMSMasterKeyID": "arn:aws:kms:..."
            }
        }]
    }
}
```

**Upload a test object and confirm it is encrypted:**
```bash
echo "lab test content" > /tmp/test-object.txt
aws s3 cp /tmp/test-object.txt s3://app-data-<ACCOUNT_ID>/test/test-object.txt

aws s3api head-object \
  --bucket app-data-<ACCOUNT_ID> \
  --key test/test-object.txt \
  --query '{Encryption:ServerSideEncryption,KMSKeyId:SSEKMSKeyId}'
```

Expected:
```json
{
    "Encryption": "aws:kms",
    "KMSKeyId": "arn:aws:kms:us-east-1:..."
}
```

**Attempt to upload without encryption specified — default should apply automatically:**
```bash
aws s3 cp /tmp/test-object.txt s3://app-data-<ACCOUNT_ID>/test/unencrypted-attempt.txt \
  --sse AES256
```

If the bucket policy requires SSE-KMS and denies other encryption types, this should fail with `AccessDenied`. Confirm by checking the bucket policy includes a `Deny` on `PutObject` without the correct `s3:x-amz-server-side-encryption` header.

---

## 4.3 — Versioning and Deletion Recovery

**Confirm versioning is enabled:**
```bash
aws s3api get-bucket-versioning \
  --bucket app-data-<ACCOUNT_ID>
```

Expected: `"Status": "Enabled"`.

**Upload a file, overwrite it, then recover the original:**
```bash
echo "version 1" > /tmp/versioned-test.txt
aws s3 cp /tmp/versioned-test.txt s3://app-data-<ACCOUNT_ID>/test/versioned-test.txt

echo "version 2 — overwritten" > /tmp/versioned-test.txt
aws s3 cp /tmp/versioned-test.txt s3://app-data-<ACCOUNT_ID>/test/versioned-test.txt

# List all versions
aws s3api list-object-versions \
  --bucket app-data-<ACCOUNT_ID> \
  --prefix test/versioned-test.txt

# Retrieve version 1 by its VersionId
aws s3api get-object \
  --bucket app-data-<ACCOUNT_ID> \
  --key test/versioned-test.txt \
  --version-id <VERSION_ID_OF_V1> \
  /tmp/recovered-version1.txt

cat /tmp/recovered-version1.txt
```

Expected: `version 1` — confirms versioning allows recovery from overwrites.

---

## 4.4 — CloudTrail Log Bucket Protection

**Attempt to delete a CloudTrail log object — should be denied by bucket policy:**
```bash
# Get the name of a recent log file
aws s3 ls s3://<TRAIL_BUCKET>/AWSLogs/<ACCOUNT_ID>/CloudTrail/us-east-1/$(date +%Y/%m/%d)/ \
  | head -3

# Attempt to delete it
aws s3 rm s3://<TRAIL_BUCKET>/AWSLogs/<ACCOUNT_ID>/CloudTrail/us-east-1/$(date +%Y/%m/%d)/<LOG_FILE_NAME>
```

Expected:
```
delete failed: ... An error occurred (AccessDenied) when calling the DeleteObject operation:
```

Bucket policy enforcement confirmed — even the admin user cannot delete audit logs.

**Verify in CloudTrail:**
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=DeleteObject \
  --max-results 3
```

Expected: `DeleteObject` event with `errorCode: AccessDenied` — the attempt is logged even though it was blocked.

---

## 4.5 — S3 Access Logging Verification

**Confirm access logging is enabled on app-data bucket:**
```bash
aws s3api get-bucket-logging \
  --bucket app-data-<ACCOUNT_ID>
```

Expected: `TargetBucket` pointing to your logging bucket.

**Generate access events and verify they appear in the log:**
```bash
aws s3 cp s3://app-data-<ACCOUNT_ID>/test/test-object.txt /tmp/downloaded.txt
aws s3 ls s3://app-data-<ACCOUNT_ID>/test/
```

Wait 5–15 minutes (S3 access logs are not real-time), then:
```bash
aws s3 ls s3://<LOGGING_BUCKET>/ --recursive | tail -5
aws s3 cp s3://<LOGGING_BUCKET>/<LATEST_LOG_FILE> /tmp/s3-access-log.txt
cat /tmp/s3-access-log.txt | grep "REST.GET.OBJECT"
```

Expected: entries showing your IAM user, timestamp, operation (`REST.GET.OBJECT`), and the object key accessed.

---

---

# PHASE 5 — ACTIVE MONITORING
**Goal:** Validate every CloudWatch alarm fires end-to-end: event → metric filter → alarm state → SNS email.

---

## 5.1 — Full Alarm Validation Checklist

Run each trigger action below and record the results in the table.

| Alarm | Trigger Action | Alarm State | Email Received | Detection Latency |
|---|---|---|---|---|
| RootAccountUsage | Log in as root | ALARM | ☐ | |
| IAMPolicyChange | `aws iam attach-user-policy ...` | ALARM | ☐ | |
| SecurityGroupChange | Add 0.0.0.0/0 inbound rule | ALARM | ☐ | |
| NetworkACLChange | Add/modify a NACL rule | ALARM | ☐ | |
| CloudTrailChange | `aws cloudtrail stop-logging ...` | ALARM | ☐ | |
| UnauthorisedAPICall | Denied API call by boundary | ALARM | ☐ | |
| MFADeactivation | `aws iam deactivate-mfa-device ...` | ALARM | ☐ | |

For each alarm, record:
- Time action was taken
- Time alarm transitioned to `ALARM` state
- Time SNS email was received

Any alarm that does not deliver to inbox within 10 minutes is not a working detection pipeline.

---

## 5.2 — CloudTrail Stop-Logging Alarm

**Stop CloudTrail — the most critical detection:**
```bash
aws cloudtrail stop-logging \
  --name cloud-security-lab-trail
```

**Verify CloudWatch alarm fired:**
```
CloudWatch → Alarms → CloudTrailChange → state: ALARM
```

**Verify SNS email received.**

**Re-enable immediately:**
```bash
aws cloudtrail start-logging \
  --name cloud-security-lab-trail
```

Confirm trail is logging again:
```bash
aws cloudtrail get-trail-status \
  --name cloud-security-lab-trail \
  --query '{IsLogging:IsLogging,LatestDeliveryTime:LatestDeliveryTime}'
```

**Tune if missing:** Metric filter pattern: `{ ($.eventName = StopLogging) || ($.eventName = DeleteTrail) || ($.eventName = UpdateTrail) || ($.eventName = PutEventSelectors) }`.

---

## 5.3 — Console Authentication Failure Alarm

**Trigger 3+ failed console login attempts:**
```
AWS Console login page → enter correct email, wrong password × 3
```

**Verify in CloudTrail:**
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=ConsoleLogin \
  --max-results 5 \
  --query 'Events[].CloudTrailEvent' \
  | python3 -c "import sys,json; [print(json.loads(e)['responseElements']['ConsoleLogin'], json.loads(e)['eventTime']) for e in json.load(sys.stdin)]"
```

Expected: `"Failure"` entries for each failed attempt.

**Verify CloudWatch alarm fired:**
```
CloudWatch → Alarms → ConsoleAuthFailures → state: ALARM
```

**Tune if missing:** Metric filter pattern: `{ ($.eventName = ConsoleLogin) && ($.errorMessage = "Failed authentication") }`.

---

---

# PHASE 6 — THREAT DETECTION
**Goal:** Validate GuardDuty detects active threats. Generate findings deliberately. Verify the full pipeline.

---

## 6.1 — Generate GuardDuty Test Findings (API Method)

AWS provides a built-in method to generate sample findings for all finding types. Use this to validate the GuardDuty → CloudWatch Events → SNS pipeline without requiring a live attack.

```bash
DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)

aws guardduty create-sample-findings \
  --detector-id $DETECTOR_ID \
  --finding-types \
    "Recon:EC2/PortProbeUnprotectedPort" \
    "UnauthorizedAccess:EC2/SSHBruteForce" \
    "Policy:IAMUser/RootCredentialUsage" \
    "Discovery:S3/AnomalousBehavior" \
    "UnauthorizedAccess:IAMUser/TorIPCaller"
```

**Verify findings in GuardDuty console:**
```
AWS Console → GuardDuty → Findings
```

Expected: 5 sample findings listed with `[SAMPLE]` prefix.

**Verify SNS email received for each finding type.**

---

## 6.2 — Live GuardDuty Validation — Port Probe

*(Already covered in Phase 3.4 — cross-reference findings here.)*

```bash
# Confirm finding persists and was not auto-archived
aws guardduty list-findings \
  --detector-id $DETECTOR_ID \
  --finding-criteria '{
    "Criterion": {
      "type": {"Eq": ["Recon:EC2/PortProbeUnprotectedPort"]},
      "service.archived": {"Eq": ["false"]}
    }
  }'
```

---

## 6.3 — Live GuardDuty Validation — SSH Brute Force

*(Already covered in Phase 3.5 — confirm the finding here.)*

```bash
aws guardduty list-findings \
  --detector-id $DETECTOR_ID \
  --finding-criteria '{"Criterion": {"type": {"Eq": ["UnauthorizedAccess:EC2/SSHBruteForce"]}}}'
```

Expected: finding with severity 5.0 (Medium), resource = bastion instance ID.

---

## 6.4 — AWS Config — Compliance Dashboard Snapshot

**Get the current compliance summary:**
```bash
aws configservice describe-compliance-by-config-rule \
  --query 'ComplianceByConfigRules[].{Rule:ConfigRuleName,Compliance:Compliance.ComplianceType}' \
  --output table
```

Expected: all rules showing `COMPLIANT` after all remediations in Phases 3 and 4 are applied.

Any `NON_COMPLIANT` remaining is an open finding — document it and the remediation action.

**Get the full compliance history for a specific rule:**
```bash
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name restricted-ssh \
  --compliance-types NON_COMPLIANT COMPLIANT \
  --query 'EvaluationResults[].{Resource:EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId,Compliance:ComplianceType,Time:ResultRecordedTime}' \
  --output table
```

This shows the timeline of compliance state changes — useful for demonstrating that a misconfiguration was introduced, detected, and remediated.

---

## 6.5 — EC2 Instance Lifecycle — Stop, Start, Scale

**Stop the instance:**
```bash
aws ec2 stop-instances --instance-ids <INSTANCE_ID>
aws ec2 wait instance-stopped --instance-ids <INSTANCE_ID>
aws ec2 describe-instances \
  --instance-ids <INSTANCE_ID> \
  --query 'Reservations[].Instances[].State.Name'
```

Expected: `"stopped"`.

**Change instance type (requires stopped state):**
```bash
aws ec2 modify-instance-attribute \
  --instance-id <INSTANCE_ID> \
  --instance-type '{"Value": "t3.small"}'
```

**Start the instance:**
```bash
aws ec2 start-instances --instance-ids <INSTANCE_ID>
aws ec2 wait instance-running --instance-ids <INSTANCE_ID>
aws ec2 describe-instances \
  --instance-ids <INSTANCE_ID> \
  --query 'Reservations[].Instances[].[State.Name,InstanceType,PublicIpAddress]'
```

Expected: `"running"`, `"t3.small"`, new public IP (changes on restart unless Elastic IP is assigned).

**Verify in CloudTrail:**
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=StopInstances
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=ModifyInstanceAttribute
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=StartInstances
```

All three lifecycle events appear in CloudTrail — confirms full audit trail of infrastructure changes.

---

---

# QUICK REFERENCE — CloudWatch Metric Filter Patterns

| Alarm Name | Metric Filter Pattern |
|---|---|
| RootAccountUsage | `{ $.userIdentity.type = "Root" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != "AwsServiceEvent" }` |
| IAMPolicyChange | `{ ($.eventName=DeleteGroupPolicy) \|\| ($.eventName=PutUserPolicy) \|\| ($.eventName=AttachUserPolicy) \|\| ($.eventName=DetachUserPolicy) \|\| ($.eventName=CreatePolicy) \|\| ($.eventName=DeletePolicy) \|\| ($.eventName=AttachRolePolicy) \|\| ($.eventName=DetachRolePolicy) }` |
| SecurityGroupChange | `{ ($.eventName = AuthorizeSecurityGroupIngress) \|\| ($.eventName = AuthorizeSecurityGroupEgress) \|\| ($.eventName = RevokeSecurityGroupIngress) \|\| ($.eventName = RevokeSecurityGroupEgress) \|\| ($.eventName = CreateSecurityGroup) \|\| ($.eventName = DeleteSecurityGroup) }` |
| NetworkACLChange | `{ ($.eventName = CreateNetworkAcl) \|\| ($.eventName = CreateNetworkAclEntry) \|\| ($.eventName = DeleteNetworkAcl) \|\| ($.eventName = DeleteNetworkAclEntry) \|\| ($.eventName = ReplaceNetworkAclEntry) \|\| ($.eventName = ReplaceNetworkAclAssociation) }` |
| CloudTrailChange | `{ ($.eventName = StopLogging) \|\| ($.eventName = DeleteTrail) \|\| ($.eventName = UpdateTrail) }` |
| UnauthorisedAPICall | `{ ($.errorCode = "*UnauthorizedAccess*") \|\| ($.errorCode = "AccessDenied") }` |
| ConsoleAuthFailures | `{ ($.eventName = ConsoleLogin) && ($.errorMessage = "Failed authentication") }` |
| MFADeactivation | `{ ($.eventName = DeactivateMFADevice) \|\| ($.eventName = DeleteVirtualMFADevice) }` |
| S3BucketPolicyChange | `{ ($.eventName = PutBucketAcl) \|\| ($.eventName = PutBucketPolicy) \|\| ($.eventName = PutBucketCors) \|\| ($.eventName = PutBucketLifecycle) \|\| ($.eventName = PutBucketReplication) \|\| ($.eventName = DeleteBucketPolicy) \|\| ($.eventName = DeleteBucketCors) \|\| ($.eventName = DeleteBucketLifecycle) \|\| ($.eventName = DeleteBucketReplication) }` |

---

# QUICK REFERENCE — GuardDuty Finding Types

| Finding Type | Severity | Trigger |
|---|---|---|
| `Recon:EC2/PortProbeUnprotectedPort` | Low (2.0) | Port scan against EC2 with exposed port |
| `UnauthorizedAccess:EC2/SSHBruteForce` | Medium (5.0) | Repeated SSH failures from same source |
| `Policy:IAMUser/RootCredentialUsage` | Medium (6.0) | Root account login or API call |
| `UnauthorizedAccess:IAMUser/TorIPCaller` | Medium (5.0) | API call from Tor exit node IP |
| `Discovery:S3/AnomalousBehavior` | Medium (5.0) | Unusual S3 access pattern |
| `Exfiltration:S3/ObjectRead.Unusual` | High (8.0) | Unusual volume of S3 object reads |
| `Behavior:EC2/NetworkPortUnusual` | Medium (5.0) | EC2 communicating on unusual outbound port |
| `Stealth:IAMUser/CloudTrailLoggingDisabled` | Low (3.0) | CloudTrail stopped |
| `Persistence:IAMUser/UserPermissions` | Medium (5.0) | IAM permissions modified |

---

# QUICK REFERENCE — AWS Config Managed Rules

| Rule Name | Checks | Remediation |
|---|---|---|
| `iam-root-access-key-check` | No root access keys exist | Delete via IAM console |
| `mfa-enabled-for-iam-console-access` | All console users have MFA | Enforce via IAM policy condition |
| `restricted-ssh` | No SG allows 0.0.0.0/0 on port 22 | Restrict to /32 or remove rule |
| `vpc-default-security-group-closed` | Default SG has no rules | Remove all inbound/outbound rules |
| `s3-bucket-public-read-prohibited` | No bucket is publicly readable | Enable Block Public Access |
| `s3-bucket-server-side-encryption-enabled` | All buckets encrypted | Enable SSE-KMS as default |
| `cloudtrail-enabled` | Trail is active | Re-enable — alarm also fires |
| `cloud-trail-log-file-validation-enabled` | Hash validation on | Enable in trail settings |
| `ec2-imdsv2-check` | All instances require IMDSv2 | `modify-instance-metadata-options --http-tokens required` |
| `s3-bucket-logging-enabled` | Access logging on | Enable with target bucket |

---

# MITRE ATT&CK for Cloud — Coverage Map

| Phase | Tactic | Technique ID | Technique | Lab Test |
|---|---|---|---|---|
| 2.1 | Defence Evasion / Persistence | T1078.004 | Cloud Accounts — Root | Root login detection |
| 2.2 | Privilege Escalation | T1548 | Abuse Elevation Control | Direct policy attach |
| 2.3 | Privilege Escalation | T1548 | Permission boundary bypass attempt | Developer user IAM call |
| 3.3 | Defence Evasion | T1562.007 | Disable or Modify Cloud Firewall | SG 0.0.0.0/0 misconfiguration |
| 3.4 | Reconnaissance | T1595 | Active Scanning | Nmap scan → GuardDuty |
| 3.5 | Credential Access | T1110 | Brute Force | Hydra SSH → GuardDuty |
| 4.1 | Defence Evasion | T1562 | Impair Defenses | Disable Block Public Access |
| 4.4 | Defence Evasion | T1070 | Indicator Removal | Attempt to delete audit log |
| 5.2 | Defence Evasion | T1562.008 | Disable Cloud Logs | Stop CloudTrail |
| 6.1 | Multiple | Multiple | Sample findings | GuardDuty API test findings |
| 6.5 | Impact | T1489 | Service Stop | Instance stop/start/scale |

---

*Runbook v1.0 — AWS Cloud Security Lab*
*See also: `aws_security_methodology.md` · `README.md` · `docs/threat-control-mapping.md`*
