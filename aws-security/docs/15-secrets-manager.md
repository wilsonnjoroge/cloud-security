# 🔒 Secrets Manager: Secure Credential Storage

> **Phase 2 · Document 15 of 29**  
> **Estimated cost:** ~$0.40/secret/month · **Estimated time:** 45 minutes  
> **Prerequisites:** `02-iam-users-groups-roles.md`, `14-kms-encryption-basics.md`

---

## What Is Secrets Manager?

AWS Secrets Manager stores, rotates, and manages credentials: database passwords, API keys, OAuth tokens, SSH keys: so your applications never hardcode sensitive values in source code or config files.

```
WITHOUT Secrets Manager:               WITH Secrets Manager:
  config.py:                             config.py:
    DB_PASSWORD = "P@ssw0rd!"              # no password here
    API_KEY = "sk-abc123..."
                                         At runtime:
  Result: password in Git forever          secret = get_secret("db/prod")
          leaked in logs                   DB_PASSWORD = secret["password"]
          visible to all devs
```

> **Forensics relevance:** Hardcoded credentials are found in nearly every cloud breach investigation. Understanding Secrets Manager means you can both prevent credential exposure and identify when an attacker has extracted secrets from an environment.

---

## Secrets Manager vs Parameter Store

| Feature | Secrets Manager | SSM Parameter Store |
|---------|----------------|-------------------|
| Cost | $0.40/secret/month | Free (standard tier) |
| Automatic rotation | Yes (built-in) | No (manual only) |
| Cross-account access | Yes | Limited |
| Versioning | Yes | Yes |
| Encryption | KMS (always) | KMS (optional) |
| Best for | Passwords, API keys, certificates | Config values, feature flags |

> Use Secrets Manager for anything that rotates or is highly sensitive. Use Parameter Store for non-sensitive config values.

---

## Step 1: Store a Database Credential

**Console path:** `Secrets Manager → Store a new secret`

### Secret type

Select: **Credentials for Amazon RDS database**  
(Even without a real RDS instance, this shows the full flow)

| Field | Value |
|-------|-------|
| Username | `admin` |
| Password | `P@ssW0rD!-Lab-2024` |
| Database | Select your RDS instance (or skip for now) |

### Secret name and description

| Field | Value |
|-------|-------|
| Secret name | `lab1/database/credentials` |
| Description | `Production database admin credentials` |
| Tags | Environment=Lab, Project=CyberSecRoadmap |

### Encryption key

Select `lab-main-key` (your KMS key from document 14).

### Rotation

Leave disabled for now: we configure it in Step 4.

Click **Store**.

---

## Step 2: Store an API Key

Store a second secret: an API key:

```
Secrets Manager → Store a new secret
  Type: Other type of secret
  Key/value pairs:
    api_key:    sk-lab1-test-key-abc123
    api_secret: super-secret-value-xyz
    endpoint:   https://api.example.com

  Secret name: lab1/api/external-service
```

---

## Step 3: Retrieve Secrets Programmatically

### From Python (inside EC2)

```python
import boto3
import json

def get_secret(secret_name):
    client = boto3.client('secretsmanager', region_name='us-east-2')
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])

# Usage
db_creds = get_secret('lab/database/credentials')
db_password = db_creds['password']
db_username = db_creds['username']

# Connect to database: password never hardcoded
connection = connect(
    host='db.example.com',
    user=db_username,
    password=db_password
)
```

### From bash (inside EC2)

```bash
# Retrieve the secret
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id lab/database/credentials \
  --query SecretString \
  --output text)

# Parse with jq
DB_PASSWORD=$(echo $SECRET | jq -r '.password')
DB_USERNAME=$(echo $SECRET | jq -r '.username')

echo "Username: $DB_USERNAME"
# Never echo the password: it will appear in logs
```

### From application startup (environment variable injection)

```bash
# Inject secret as environment variable at startup
export DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id lab/database/credentials \
  --query 'SecretString' \
  --output text | jq -r '.password')
```

> **Important:** Even injecting to environment variables is risky: they can be read by any process on the instance and appear in crash dumps. The safest approach is to retrieve the secret at the moment it is needed and not store it anywhere.

---

## Step 4: Configure Automatic Rotation

Automatic rotation changes the secret value on a schedule and updates the actual database password to match: without any application downtime.

```
Secrets Manager → lab/database/credentials → Rotation → Edit rotation
  Automatic rotation: Enable
  Rotation schedule: 30 days
  Rotation function: Create a new Lambda function
  Lambda function name: SecretsManagerRDSRotation
```

How rotation works:

```
Day 1:   Secret = "OldPassword123"
         Database password = "OldPassword123"

Day 30:  Secrets Manager generates "NewPassword456"
         Lambda updates database password to "NewPassword456"
         Lambda updates secret to "NewPassword456"

Day 30+: Applications retrieve new secret automatically
         Old password no longer works
```

> **Security impact of rotation:** If a credential is compromised, rotation limits the attacker's window. A 30-day rotation means stolen credentials stop working within 30 days at most: without you manually changing anything.

---

## Step 5: Access Control for Secrets

By default only the secret creator can access it. Grant access via IAM policy:

### IAM policy: allow EC2 to read one specific secret

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowReadSpecificSecret",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-2:ACCOUNT-ID:secret:lab1/database/credentials-*"
    }
  ]
}
```

Attach this policy to `lab-ec2-s3-read-role` so your EC2 instance can retrieve the secret.

### Resource-based policy on the secret

You can also attach a policy directly to the secret:

```
Secrets Manager → lab1/database/credentials → Resource permissions → Edit
```

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT-ID:role/lab-ec2-s3-read-role"
      },
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "*"
    }
  ]
}
```

---

## Step 6: Secret Versioning

Every time a secret is rotated or updated, Secrets Manager creates a new version with staging labels.

| Label | Meaning |
|-------|---------|
| `AWSCURRENT` | The current active version |
| `AWSPENDING` | New version during rotation (not yet active) |
| `AWSPREVIOUS` | The version before the last rotation |

Retrieve a specific version:

```bash
# Get current version
aws secretsmanager get-secret-value \
  --secret-id lab1/database/credentials \
  --version-stage AWSCURRENT

# Get previous version (useful if rotation broke something)
aws secretsmanager get-secret-value \
  --secret-id lab1/database/credentials \
  --version-stage AWSPREVIOUS
```

---

## Step 7: Audit Secret Access via CloudTrail

Every `GetSecretValue` call is logged in CloudTrail.

```
CloudTrail → Event history → filter: Event name = GetSecretValue
```

CloudWatch Logs Insights query: who accessed your secrets:

```sql
fields eventTime, userIdentity.userName, requestParameters.secretId, sourceIPAddress
| filter eventName = "GetSecretValue"
| sort eventTime desc
| limit 50
```

Alert on unexpected secret access:

```
CloudWatch → Metric filter
Pattern: { ($.eventName = "GetSecretValue") &&
           ($.requestParameters.secretId = "lab/database/credentials") }
Metric: SecretAccess
Alarm: > 10 accesses in 5 minutes (anomalous retrieval)
```

> In a breach, attackers often enumerate and dump all secrets from Secrets Manager after gaining IAM access. Unusual `GetSecretValue` volume across multiple secrets is a key indicator of credential harvesting.

---

## Step 8: Cross-Account Secret Sharing

Share a secret with another AWS account without copying it:

```json
{
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::OTHER-ACCOUNT-ID:root"
  },
  "Action": "secretsmanager:GetSecretValue",
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "aws:PrincipalAccount": "OTHER-ACCOUNT-ID"
    }
  }
}
```

> Used in enterprise environments where a shared secrets account distributes credentials to application accounts: a clean separation of duties.

---

## Forensics Scenario: Secret Exfiltration

**Indicators:**
- CloudTrail: `ListSecrets` followed by `GetSecretValue` for multiple secrets from an unusual IP
- The IAM identity making calls is an EC2 instance role (unusual: applications typically access one secret)
- Source IP is an external cloud provider (attacker's exfiltration server)

**Response:**
1. Identify which secrets were accessed: `ListSecrets` + `GetSecretValue` events
2. Rotate all accessed secrets immediately
3. Revoke the compromised IAM credentials
4. Notify owners of affected systems (database, APIs, etc.)
5. Check CloudTrail for what the attacker did with the credentials

---

## Common CLI Commands

```bash
# List all secrets
aws secretsmanager list-secrets

# Get a secret value
aws secretsmanager get-secret-value --secret-id lab/database/credentials

# Create a secret
aws secretsmanager create-secret \
  --name lab/api/new-service \
  --description "New API credentials" \
  --secret-string '{"api_key":"abc123","api_secret":"xyz789"}'

# Update a secret value
aws secretsmanager put-secret-value \
  --secret-id lab/database/credentials \
  --secret-string '{"username":"admin","password":"NewPassword456"}'

# Delete a secret (with 7 day recovery window)
aws secretsmanager delete-secret \
  --secret-id lab/api/new-service \
  --recovery-window-in-days 7

# Force immediate deletion (no recovery)
aws secretsmanager delete-secret \
  --secret-id lab/api/new-service \
  --force-delete-without-recovery
```

---

## Phase 2 Complete 🎉

You now have a full blue team / security operations skill set:

- [x] GuardDuty: threat detection
- [x] VPC Flow Logs: network forensics
- [x] AWS Config: drift detection and compliance
- [x] Security Hub: centralized posture
- [x] WAF: application layer protection
- [x] KMS: encryption key management
- [x] Secrets Manager: credential security

**Next:** Phase 3: Cloud Forensics & Incident Response  
Start with: `16-ebs-snapshot-forensics.md`

---

## Cleanup

```
# Secrets cost $0.40/month each
Secrets Manager → select secret → Actions → Delete secret
  Recovery window: 7 days

# To delete immediately (no recovery possible):
aws secretsmanager delete-secret \
  --secret-id lab/database/credentials \
  --force-delete-without-recovery
```

---

*Phase 2 · AWS Cybersecurity & Digital Forensics Roadmap*
