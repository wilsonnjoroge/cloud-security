# 🔎 CloudTrail Log Analysis — Attacker Timeline Reconstruction

> **Phase 3 · Document 17 of 29**  
> **Estimated cost:** Free (uses existing CloudTrail) · **Estimated time:** 60–90 minutes  
> **Prerequisites:** `06-cloudtrail-setup.md`, `16-ebs-snapshot-forensics.md`

---

## CloudTrail in Incident Response

CloudTrail is the authoritative record of everything that happened in your AWS account. In an incident, it answers the fundamental investigative questions:

```
Who?   → userIdentity (IAM user, role, root, service)
What?  → eventName (RunInstances, DeleteBucket, AttachUserPolicy)
When?  → eventTime (UTC timestamp)
Where? → sourceIPAddress, awsRegion
How?   → userAgent (console, CLI, SDK, unknown tool)
Result?→ errorCode (null = success, otherwise = failure reason)
```

---

## The Attacker Kill Chain in CloudTrail

Understanding which CloudTrail events map to which attack phases:

```
Initial Access
  └── ConsoleLogin (from unusual IP/geo)
  └── AssumeRole (from unexpected account)

Discovery
  └── ListBuckets, DescribeInstances, ListUsers
  └── GetAccountAuthorizationDetails (IAM enumeration)
  └── DescribeSecurityGroups

Privilege Escalation
  └── AttachUserPolicy, PutUserPolicy
  └── CreateAccessKey (for another user)
  └── AddUserToGroup (adding to admin group)

Persistence
  └── CreateUser, CreateAccessKey
  └── CreateLoginProfile
  └── AddUserToGroup

Lateral Movement
  └── AssumeRole (moving between accounts)
  └── RunInstances (launching new infrastructure)

Exfiltration
  └── GetObject (S3 reads)
  └── GetSecretValue (secrets access)
  └── DownloadDBLogFilePortion (database logs)

Defense Evasion
  └── DeleteTrail, StopLogging
  └── DeleteFlowLogs
  └── DeleteAlarms
```

---

## Step 1 — Set Up the Investigation Environment

For this exercise, simulate an attack sequence so you have logs to investigate.

```bash
# Using dev-alice credentials — simulate attacker who stole them

# Discovery phase
aws iam list-users
aws iam list-roles
aws iam get-account-authorization-details
aws s3 ls
aws ec2 describe-instances
aws ec2 describe-security-groups

# Privilege escalation attempt
aws iam attach-user-policy \
  --user-name dev-alice \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Access secrets
aws secretsmanager list-secrets
aws secretsmanager get-secret-value --secret-id lab/database/credentials

# Access S3 data
aws s3 ls s3://lab-private-yourname-2024/
aws s3 cp s3://lab-private-yourname-2024/ /tmp/ --recursive

# Attempt to disable CloudTrail (this will likely fail without perms)
aws cloudtrail stop-logging --name lab-audit-trail
```

Wait 5–10 minutes for logs to propagate to CloudWatch Logs.

---

## Step 2 — Reconstruct the Attack Timeline

### Query 1 — All activity by the compromised identity

```sql
-- CloudWatch Logs Insights
fields eventTime, eventName, sourceIPAddress, errorCode, userAgent
| filter userIdentity.userName = "dev-alice"
| sort eventTime asc
| limit 200
```

This gives you the full chronological sequence of everything the compromised identity did.

### Query 2 — Identify the initial access point

```sql
fields eventTime, eventName, sourceIPAddress, userAgent
| filter userIdentity.userName = "dev-alice"
| filter eventName = "ConsoleLogin" OR eventName = "GetSessionToken"
| sort eventTime asc
```

Note the `sourceIPAddress` — compare it to known legitimate IPs for this user. An unfamiliar IP means the credentials were used from a new location (attacker's machine).

### Query 3 — Discovery phase (reconnaissance)

```sql
fields eventTime, eventName, sourceIPAddress
| filter userIdentity.userName = "dev-alice"
| filter eventName in [
    "ListBuckets", "ListUsers", "ListRoles",
    "DescribeInstances", "DescribeSecurityGroups",
    "GetAccountAuthorizationDetails", "ListSecrets",
    "DescribeVpcs", "DescribeSubnets"
  ]
| sort eventTime asc
```

A cluster of List/Describe calls in a short time window = reconnaissance phase.

### Query 4 — Privilege escalation attempts

```sql
fields eventTime, eventName, requestParameters, errorCode
| filter userIdentity.userName = "dev-alice"
| filter eventName in [
    "AttachUserPolicy", "PutUserPolicy", "DetachUserPolicy",
    "AttachRolePolicy", "PutRolePolicy",
    "CreateUser", "AddUserToGroup",
    "CreateAccessKey", "UpdateAccessKey",
    "PassRole", "AssumeRole"
  ]
| sort eventTime asc
```

### Query 5 — Data access (exfiltration evidence)

```sql
fields eventTime, eventName, requestParameters.bucketName,
       requestParameters.key, sourceIPAddress
| filter userIdentity.userName = "dev-alice"
| filter eventName in ["GetObject", "ListObjectsV2", "GetSecretValue",
                        "GetParameter", "Decrypt"]
| sort eventTime asc
```

This is your exfiltration evidence — what data was accessed, when, from where.

### Query 6 — Defense evasion attempts

```sql
fields eventTime, eventName, errorCode, sourceIPAddress
| filter userIdentity.userName = "dev-alice"
| filter eventName in [
    "DeleteTrail", "StopLogging", "UpdateTrail",
    "DeleteFlowLogs", "DeleteAlarms",
    "DeleteMetricFilter", "PutEventSelectors"
  ]
| sort eventTime asc
```

Failed attempts (errorCode is not null) are still evidence — they show intent even if the action didn't succeed.

---

## Step 3 — Build the Attacker Timeline

Using your query results, construct a formal timeline:

```markdown
## Incident Timeline — IR-2024-001

All times UTC

14:03:22  ConsoleLogin — dev-alice — sourceIP: 198.51.100.42
          (First appearance of attacker IP — credentials compromised)

14:03:45  ListBuckets — dev-alice — 198.51.100.42
14:03:47  DescribeInstances — dev-alice — 198.51.100.42
14:03:49  ListUsers — dev-alice — 198.51.100.42
14:03:51  GetAccountAuthorizationDetails — dev-alice — 198.51.100.42
          (Reconnaissance phase: ~29 seconds, mapped entire account)

14:04:10  AttachUserPolicy — dev-alice — attached AdministratorAccess
          errorCode: null (SUCCEEDED — privilege escalation successful)

14:04:35  ListSecrets — dev-alice — 198.51.100.42
14:04:38  GetSecretValue — lab/database/credentials — 198.51.100.42
14:04:41  GetSecretValue — lab/api/external-service — 198.51.100.42
          (Secret exfiltration: 3 secrets accessed in 6 seconds)

14:05:12  ListObjectsV2 — lab-private-yourname-2024 — 198.51.100.42
14:05:15  GetObject × 47 — lab-private-yourname-2024 — 198.51.100.42
          (S3 exfiltration: 47 objects downloaded)

14:06:02  StopLogging — lab-audit-trail
          errorCode: AccessDenied (attempted to disable CloudTrail — FAILED)

14:06:15  CreateUser — attacker-backdoor — 198.51.100.42
14:06:18  AttachUserPolicy — attacker-backdoor — AdministratorAccess
14:06:20  CreateAccessKey — attacker-backdoor
          (Persistence: created backdoor admin user with keys)

Total dwell time before detection: 3 minutes 18 seconds
```

---

## Step 4 — Identify the Blast Radius

Determine everything the attacker touched:

### Affected resources

```sql
-- All resources the attacker interacted with
fields eventTime, eventName, resources
| filter userIdentity.userName = "dev-alice"
| filter ispresent(resources)
| sort eventTime asc
```

### Affected data

```sql
-- Every S3 object accessed
fields eventTime, requestParameters.bucketName, requestParameters.key
| filter userIdentity.userName = "dev-alice"
| filter eventName = "GetObject"
| stats count(*) as accessed by requestParameters.bucketName
```

### Credentials created (persistence mechanisms)

```sql
fields eventTime, eventName, requestParameters, responseElements
| filter userIdentity.userName = "dev-alice"
| filter eventName in ["CreateUser", "CreateAccessKey",
                        "CreateLoginProfile", "AddUserToGroup"]
```

---

## Step 5 — Correlate with VPC Flow Logs

After identifying the attacker's actions in CloudTrail, correlate with network traffic:

```sql
-- In VPC Flow Logs log group
fields @timestamp, srcaddr, dstaddr, dstport, bytes, action
| filter srcaddr = "198.51.100.42"
| sort @timestamp asc
```

This shows which instances the attacker's IP connected to directly — not just what they did via the API, but what systems they accessed over the network.

---

## Step 6 — CloudTrail Lake for Complex Investigations

For complex multi-account investigations, CloudTrail Lake SQL is more powerful:

```sql
-- Find all API calls made within 5 minutes of the initial compromise
SELECT
  eventTime,
  eventName,
  userIdentity.userName,
  sourceIPAddress,
  errorCode,
  requestParameters
FROM
  lab-event-store
WHERE
  eventTime BETWEEN '2024-01-15T14:03:00Z' AND '2024-01-15T14:08:00Z'
ORDER BY eventTime ASC;

-- Find all access keys created in the last 30 days
SELECT eventTime, requestParameters, responseElements
FROM lab-event-store
WHERE eventName = 'CreateAccessKey'
  AND eventTime > DATE_ADD('day', -30, NOW())
ORDER BY eventTime DESC;

-- Cross-account role assumptions (lateral movement detection)
SELECT
  eventTime,
  userIdentity.sessionContext.sessionIssuer.accountId as sourceAccount,
  recipientAccountId as targetAccount,
  requestParameters.roleArn,
  sourceIPAddress
FROM lab-event-store
WHERE eventName = 'AssumeRole'
ORDER BY eventTime DESC;
```

---

## Step 7 — Automate Timeline Generation

```python
import boto3
import json
from datetime import datetime, timedelta

def get_attack_timeline(username, hours_back=24):
    client = boto3.client('cloudtrail', region_name='us-east-2')
    
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=hours_back)
    
    events = []
    paginator = client.get_paginator('lookup_events')
    
    pages = paginator.paginate(
        LookupAttributes=[{
            'AttributeKey': 'Username',
            'AttributeValue': username
        }],
        StartTime=start_time,
        EndTime=end_time
    )
    
    for page in pages:
        for event in page['Events']:
            events.append({
                'time': event['EventTime'].isoformat(),
                'event': event['EventName'],
                'source_ip': json.loads(event['CloudTrailEvent'])
                             .get('sourceIPAddress', 'N/A'),
                'error': json.loads(event['CloudTrailEvent'])
                         .get('errorCode', 'SUCCESS')
            })
    
    # Sort by time ascending
    events.sort(key=lambda x: x['time'])
    
    print(f"Timeline for {username} (last {hours_back} hours):\n")
    for e in events:
        status = "✓" if e['error'] == 'SUCCESS' else f"✗ ({e['error']})"
        print(f"{e['time']}  {status}  {e['event']:40}  {e['source_ip']}")
    
    return events

# Run it
timeline = get_attack_timeline('dev-alice', hours_back=2)
```

---

## Step 8 — Write the Incident Report

A complete incident report from CloudTrail evidence:

```markdown
## Incident Report — IR-2024-001
**Classification:** Compromised IAM Credentials
**Severity:** Critical
**Status:** Contained

### Executive Summary
IAM user dev-alice credentials were compromised. The attacker accessed
secrets, exfiltrated S3 data, and created a backdoor admin user before
being detected. Total dwell time: 3 minutes 18 seconds.

### Evidence Sources
- CloudTrail: All API activity logged (integrity verified)
- VPC Flow Logs: Network connections correlated
- S3 Server Access Logs: Object-level access confirmed

### Impact Assessment
- Credentials exposed: 2 (lab/database, lab/api)
- S3 objects exfiltrated: 47 files from lab-private bucket
- Backdoor account created: attacker-backdoor (now disabled)

### Containment Actions Taken
1. Disabled dev-alice IAM user (14:06:45 UTC)
2. Deleted attacker-backdoor user and access keys (14:07:12 UTC)
3. Rotated all exposed secrets (14:10:00 UTC)
4. Reviewed all resources for additional persistence mechanisms

### Root Cause
dev-alice access key committed to public GitHub repository.
Key was active for 47 days before compromise.

### Recommendations
1. Enable GitGuardian or similar secret scanning on all repos
2. Implement mandatory 90-day access key rotation
3. Enable MFA for all IAM users
4. Implement GuardDuty impossible travel detection
```

---

## Common CLI Commands

```bash
# Look up events for a specific user
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=dev-alice \
  --start-time 2024-01-15T14:00:00Z \
  --end-time 2024-01-15T15:00:00Z

# Look up events for a specific resource
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=lab-private-yourname-2024

# Look up a specific event type
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=StopLogging

# Download and parse log files from S3
aws s3 sync s3://lab-cloudtrail-logs-yourname/AWSLogs/ ./cloudtrail-logs/
find ./cloudtrail-logs -name "*.json.gz" -exec gunzip {} \;
cat ./cloudtrail-logs/**/*.json | jq '.Records[] | select(.userIdentity.userName=="dev-alice")'
```

---

## Phase 3 Progress Tracker

- [x] EBS snapshot forensics
- [x] CloudTrail log analysis
- [ ] Memory acquisition on EC2
- [ ] Compromised IAM incident response
- [ ] S3 breach investigation
- [ ] Lambda auto-isolation

---

*Phase 3 · AWS Cybersecurity & Digital Forensics Roadmap*
