# 🪣 S3 Breach Investigation — Data Exfiltration Analysis

> **Phase 3 · Document 20 of 29**  
> **Estimated cost:** Free · **Estimated time:** 60 minutes  
> **Prerequisites:** `04-s3-buckets-and-policies.md`, `17-cloudtrail-log-analysis.md`

---

## S3 Breach Scenarios

S3 breaches happen in three main ways:

```
1. PUBLIC BUCKET
   Bucket misconfigured as public → anyone downloads data
   Detection: Macie finding, Config rule, access logs

2. COMPROMISED IAM CREDENTIALS
   Attacker uses stolen keys → authenticated access to private bucket
   Detection: CloudTrail GetObject from unusual IP

3. BUCKET POLICY MISCONFIGURATION
   Overly permissive bucket policy → unintended access
   Detection: Access Analyzer finding, audit
```

---

## Step 1 — Simulate a Breach

Create evidence to investigate:

```bash
# Upload sensitive test data
echo "Name,SSN,CreditCard" > sensitive.csv
echo "Alice,123-45-6789,4111111111111111" >> sensitive.csv
echo "Bob,987-65-4321,5500005555555554" >> sensitive.csv
aws s3 cp sensitive.csv s3://lab-private-yourname-2024/data/sensitive.csv

# Simulate attacker access (from dev-alice credentials)
# List objects
aws s3 ls s3://lab-private-yourname-2024/

# Download all objects (exfiltration simulation)
aws s3 sync s3://lab-private-yourname-2024/ /tmp/exfil-data/

# Delete objects (destruction simulation)
aws s3 rm s3://lab-private-yourname-2024/data/sensitive.csv

# Check if public access works
curl http://lab-private-yourname-2024.s3.amazonaws.com/data/sensitive.csv
```

Wait 10–15 minutes for logs to populate.

---

## Step 2 — Detect the Breach

### Check Macie findings

```
Macie → Findings
```

If Macie is enabled and scanned the bucket, you'll see findings like:
- `SensitiveData:S3Object/Credentials` — passwords, API keys
- `SensitiveData:S3Object/Personal` — PII (SSN, credit cards)
- `SensitiveData:S3Object/Financial` — financial data

### Check CloudTrail for suspicious S3 access

```sql
-- All S3 GetObject events from external IPs
fields eventTime, userIdentity.userName, sourceIPAddress,
       requestParameters.bucketName, requestParameters.key, errorCode
| filter eventName = "GetObject"
| filter not sourceIPAddress like /^10\./
| filter not sourceIPAddress like /^172\./
| filter not sourceIPAddress like /^192\.168\./
| sort eventTime desc
| limit 100
```

### Check S3 server access logs

```
S3 → lab-logs-yourname-2024 → browse log files
```

Each line in the access log:

```
bucket-owner bucket-name time remote-ip requester request-uri
http-status error-code bytes-sent object-size total-time
turn-around-time referrer user-agent version-id host-id
sig-version cipher-suite auth-type host-header tls-version
```

---

## Step 3 — Determine What Was Accessed

### Via CloudTrail

```sql
-- Every object accessed by the attacker
fields eventTime, requestParameters.key, requestParameters.bucketName,
       userIdentity.userName, sourceIPAddress
| filter userIdentity.userName = "dev-alice"
| filter eventName = "GetObject"
| sort eventTime asc
```

### Count total data exfiltrated

```sql
-- Bytes transferred per object
fields eventTime, requestParameters.key, responseElements.contentLength
| filter userIdentity.userName = "dev-alice"
| filter eventName = "GetObject"
| stats sum(responseElements.contentLength) as totalBytes,
         count(*) as objectCount
```

### Via S3 server access logs (Athena)

```sql
CREATE EXTERNAL TABLE s3_access_logs (
  bucket_owner string, bucket string, request_datetime string,
  remote_ip string, requester string, request_id string,
  operation string, key string, request_uri string,
  http_status int, error_code string, bytes_sent bigint,
  object_size bigint, total_time int, turn_around_time int,
  referrer string, user_agent string, version_id string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.RegexSerDe'
WITH SERDEPROPERTIES (
  'serialization.format' = '1',
  'input.regex' = '([^ ]*) ([^ ]*) \\[(.*?)\\] ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) (\"[^\"]*\"|-) (-|[0-9]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) (\"[^\"]*\"|-) ([^ ]*).*$'
)
LOCATION 's3://lab-logs-yourname-2024/s3-access-logs/';

-- Total data accessed by remote IP
SELECT remote_ip, count(*) as requests, sum(bytes_sent) as total_bytes
FROM s3_access_logs
WHERE operation LIKE '%GET%'
GROUP BY remote_ip
ORDER BY total_bytes DESC;
```

---

## Step 4 — Determine if Deletion Occurred

```sql
-- Objects deleted during the incident
fields eventTime, userIdentity.userName, requestParameters.key,
       requestParameters.bucketName
| filter eventName in ["DeleteObject", "DeleteObjects", "DeleteBucket"]
| sort eventTime asc
```

### Recover deleted objects (if versioning was enabled)

```bash
# List all deleted objects (delete markers)
aws s3api list-object-versions \
  --bucket lab-private-yourname-2024 \
  --query 'DeleteMarkers[*].{Key:Key,VersionId:VersionId,Date:LastModified}'

# Remove the delete marker to restore the object
aws s3api delete-object \
  --bucket lab-private-yourname-2024 \
  --key data/sensitive.csv \
  --version-id <delete-marker-version-id>

# Verify restoration
aws s3 ls s3://lab-private-yourname-2024/data/
```

> If versioning was NOT enabled, deleted objects are permanently gone. This is why enabling versioning is non-negotiable for any bucket containing important data.

---

## Step 5 — Check for Public Access Configuration Changes

```sql
-- Was the bucket made public?
fields eventTime, userIdentity.userName, requestParameters
| filter eventName in [
    "PutBucketAcl",
    "PutBucketPolicy",
    "DeletePublicAccessBlock",
    "PutPublicAccessBlock"
  ]
| filter requestParameters.bucketName = "lab-private-yourname-2024"
| sort eventTime asc
```

### Check current bucket policy and ACL

```bash
# Current bucket policy
aws s3api get-bucket-policy --bucket lab-private-yourname-2024

# Current ACL
aws s3api get-bucket-acl --bucket lab-private-yourname-2024

# Public access block settings
aws s3api get-public-access-block --bucket lab-private-yourname-2024

# CORS configuration (may allow cross-origin data access)
aws s3api get-bucket-cors --bucket lab-private-yourname-2024 2>/dev/null
```

---

## Step 6 — Investigate Presigned URL Abuse

Attackers with S3 read access can generate presigned URLs to exfiltrate data — these requests appear in CloudTrail as coming from the legitimate IAM identity, not the attacker's external IP.

```sql
-- Find presigned URL usage (characterized by query-based auth)
fields eventTime, sourceIPAddress, requestParameters.key, userAgent
| filter eventName = "GetObject"
| filter userAgent not like /aws-cli/
| filter userAgent not like /boto/
| filter userAgent not like /aws-sdk/
| sort eventTime asc
```

Presigned URL requests typically come from:
- Browser user agents (someone opened the URL in a browser)
- Unusual user agents
- External IPs different from the key holder's normal IP

---

## Step 7 — Check for Cross-Account Access

An attacker may have modified the bucket policy to grant access to their own AWS account:

```bash
# Check bucket policy for external account principals
aws s3api get-bucket-policy --bucket lab-private-yourname-2024 \
  --query 'Policy' --output text | \
  python3 -c "import sys,json; policy=json.load(sys.stdin); \
  [print(s) for s in policy['Statement'] if 'arn:aws:iam' in str(s.get('Principal',''))]"
```

Look for any `Principal` with an AWS account ID different from yours — that is an unauthorized cross-account grant.

---

## Step 8 — Containment Actions

```bash
# === Immediately restrict bucket access ===

# Block all public access
aws s3api put-public-access-block \
  --bucket lab-private-yourname-2024 \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Apply deny-all bucket policy as emergency measure
aws s3api put-bucket-policy \
  --bucket lab-private-yourname-2024 \
  --policy '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::lab-private-yourname-2024",
        "arn:aws:s3:::lab-private-yourname-2024/*"
      ],
      "Condition": {
        "StringNotEquals": {
          "aws:PrincipalArn": "arn:aws:iam::ACCOUNT-ID:user/admin-yourname"
        }
      }
    }]
  }'

# Disable the compromised IAM identity
aws iam update-access-key \
  --user-name dev-alice \
  --access-key-id AKIAIOSFODNN7EXAMPLE \
  --status Inactive
```

---

## Step 9 — Assess Breach Notification Requirements

Based on your findings, determine notification obligations:

```markdown
## Data Classification Assessment

Data types found in accessed objects:
  [ ] PII (names, addresses, dates of birth) → GDPR/CCPA may apply
  [ ] Financial data (credit cards, bank accounts) → PCI DSS notification
  [ ] Health information → HIPAA breach notification
  [ ] Government ID numbers → varies by jurisdiction
  [ ] Credentials (passwords, API keys) → rotate immediately, notify affected services
  [ ] Confidential business data → contractual obligations may apply

Notification timeline:
  GDPR:   72 hours to supervisory authority if risk to individuals
  HIPAA:  60 days to affected individuals, HHS
  PCI:    Immediately to card brands and acquiring bank
  CCPA:   Expedient to affected consumers

Kenya Data Protection Act 2019:
  Notify Data Commissioner and affected individuals
  Expedient notification required
```

---

## S3 Breach Investigation Checklist

```
Evidence Collection:
  [ ] CloudTrail logs downloaded and integrity verified
  [ ] S3 server access logs downloaded
  [ ] VPC Flow Logs for the incident period downloaded
  [ ] Macie report exported

Scope Determination:
  [ ] Every accessed object identified and listed
  [ ] Total data volume calculated
  [ ] Time range of unauthorized access determined
  [ ] Attacker's IP addresses and user agents recorded
  [ ] Determine if data was deleted (versioning saved it or not)

Containment:
  [ ] Block public access re-enabled
  [ ] Bucket policy restricted
  [ ] Compromised IAM credentials revoked
  [ ] All presigned URLs invalidated (revoke the IAM key that created them)

Recovery:
  [ ] Deleted objects recovered from versions (if versioning was on)
  [ ] Bucket policy restored to known good state
  [ ] Access logging verified still running
  [ ] Macie re-scan initiated

Documentation:
  [ ] Data inventory of what was exfiltrated
  [ ] Breach notification assessment completed
  [ ] Timeline of events documented
  [ ] Root cause identified
  [ ] Remediation steps documented
```

---

## Phase 3 Progress Tracker

- [x] EBS snapshot forensics
- [x] CloudTrail log analysis
- [x] Memory acquisition on EC2
- [x] Compromised IAM incident response
- [x] S3 breach investigation
- [ ] Lambda auto-isolation

---

*Phase 3 · AWS Cybersecurity & Digital Forensics Roadmap*
