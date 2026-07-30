# ⚡ Lambda Auto-Isolation — Automated Incident Response

> **Phase 3 · Document 21 of 29**  
> **Estimated cost:** ~$0.50 · **Estimated time:** 60–90 minutes  
> **Prerequisites:** `09-guardduty-setup-and-findings.md`, `19-compromised-iam-response.md`

---

## Why Automate Incident Response?

Manual incident response takes minutes to hours. Attackers move in seconds.

```
MANUAL RESPONSE:
  GuardDuty alert → analyst reviews → analyst acts → instance isolated
  Time: 15–60 minutes
  Risk: attacker exfiltrates 50GB of data while you respond

AUTOMATED RESPONSE:
  GuardDuty alert → EventBridge → Lambda → instance isolated
  Time: under 30 seconds
  Risk: minimized
```

> Automated response does not replace human judgment — it buys time. The Lambda isolates the instance automatically; the analyst investigates why afterward.

---

## The Automation Architecture

```
GuardDuty Finding (High/Critical)
      │
      ▼
EventBridge Rule (filters by severity and finding type)
      │
      ▼
Lambda Function
      ├── Isolate EC2 instance (replace security group with deny-all)
      ├── Snapshot EBS volumes (preserve evidence)
      ├── Disable IAM role (if role was compromised)
      ├── Tag instance as compromised
      └── Send detailed SNS alert with all context
```

---

## Step 1 — Create the Isolation Security Group

This is a "quarantine" security group — no inbound, no outbound. Attaching this to an instance immediately cuts all network access.

```bash
# Create the isolation security group
ISOLATION_SG=$(aws ec2 create-security-group \
  --group-name "ISOLATION-NO-ACCESS" \
  --description "Emergency isolation - no inbound or outbound traffic" \
  --vpc-id vpc-xxxxxxxx \
  --query 'GroupId' \
  --output text)

echo "Isolation SG ID: $ISOLATION_SG"

# Remove the default outbound rule (default allows all outbound)
aws ec2 revoke-security-group-egress \
  --group-id $ISOLATION_SG \
  --protocol -1 \
  --port -1 \
  --cidr 0.0.0.0/0

# Verify: no inbound, no outbound rules
aws ec2 describe-security-groups --group-ids $ISOLATION_SG
```

Tag it so it is easy to find in automation:

```bash
aws ec2 create-tags \
  --resources $ISOLATION_SG \
  --tags Key=Purpose,Value=ForensicIsolation Key=Environment,Value=Security
```

---

## Step 2 — Create the Lambda IAM Role

The Lambda function needs permissions to perform isolation actions:

**Console path:** `IAM → Roles → Create role`

| Field | Value |
|-------|-------|
| Trusted entity | AWS service — Lambda |
| Role name | `LambdaIncidentResponderRole` |

Create and attach this inline policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2IsolationPermissions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeSecurityGroups",
        "ec2:ModifyInstanceAttribute",
        "ec2:CreateSnapshot",
        "ec2:CreateTags",
        "ec2:StopInstances"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMDisablePermissions",
      "Effect": "Allow",
      "Action": [
        "iam:PutRolePolicy",
        "iam:PutUserPolicy",
        "iam:UpdateAccessKey",
        "iam:ListAccessKeys"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SNSAlertPermissions",
      "Effect": "Allow",
      "Action": ["sns:Publish"],
      "Resource": "*"
    },
    {
      "Sid": "LoggingPermissions",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
```

---

## Step 3 — Create the Lambda Function

**Console path:** `Lambda → Create function`

| Field | Value |
|-------|-------|
| Function name | `IncidentResponder-IsolateEC2` |
| Runtime | Python 3.12 |
| Execution role | `LambdaIncidentResponderRole` |
| Timeout | 60 seconds |
| Memory | 256 MB |

Paste this code:

```python
import boto3
import json
import os
from datetime import datetime

ec2 = boto3.client('ec2')
iam = boto3.client('iam')
sns = boto3.client('sns')

ISOLATION_SG = os.environ['ISOLATION_SG_ID']
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']

def lambda_handler(event, context):
    """
    Automated incident response for GuardDuty High/Critical findings.
    Isolates EC2 instance, snapshots volumes, and sends alert.
    """
    
    print(f"Received event: {json.dumps(event, default=str)}")
    
    # Parse GuardDuty finding
    finding = event['detail']['findings'][0]
    finding_id = finding['Id']
    finding_type = finding['Type']
    severity = finding['Severity']['Label']
    title = finding['Title']
    
    # Extract affected resource
    resource = finding['Resources'][0]
    resource_type = resource['Type']
    
    actions_taken = []
    
    # ===== EC2 ISOLATION =====
    if resource_type == 'AwsEc2Instance':
        instance_id = resource['Id'].split('/')[-1]
        
        print(f"Isolating EC2 instance: {instance_id}")
        
        # Get current security groups (for audit record)
        instance_info = ec2.describe_instances(InstanceIds=[instance_id])
        instance = instance_info['Reservations'][0]['Instances'][0]
        original_sgs = [sg['GroupId'] for sg in instance['SecurityGroups']]
        
        # Tag instance as compromised BEFORE isolation
        ec2.create_tags(
            Resources=[instance_id],
            Tags=[
                {'Key': 'SecurityStatus', 'Value': 'COMPROMISED'},
                {'Key': 'IsolatedAt', 'Value': datetime.utcnow().isoformat()},
                {'Key': 'FindingId', 'Value': finding_id},
                {'Key': 'OriginalSGs', 'Value': ','.join(original_sgs)},
                {'Key': 'IsolatedBy', 'Value': 'AutomatedIR-Lambda'}
            ]
        )
        
        # Replace all security groups with isolation SG
        ec2.modify_instance_attribute(
            InstanceId=instance_id,
            Groups=[ISOLATION_SG]
        )
        
        actions_taken.append(f"Isolated {instance_id}: replaced SGs {original_sgs} with {ISOLATION_SG}")
        
        # Snapshot all attached EBS volumes
        for mapping in instance.get('BlockDeviceMappings', []):
            if 'Ebs' in mapping:
                volume_id = mapping['Ebs']['VolumeId']
                device = mapping['DeviceName']
                
                snapshot = ec2.create_snapshot(
                    VolumeId=volume_id,
                    Description=f"FORENSIC-{instance_id}-{device}-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}",
                    TagSpecifications=[{
                        'ResourceType': 'snapshot',
                        'Tags': [
                            {'Key': 'Purpose', 'Value': 'ForensicEvidence'},
                            {'Key': 'SourceInstance', 'Value': instance_id},
                            {'Key': 'FindingId', 'Value': finding_id},
                            {'Key': 'CaseID', 'Value': f"IR-AUTO-{datetime.utcnow().strftime('%Y%m%d')}"}
                        ]
                    }]
                )
                
                actions_taken.append(f"Snapshot created: {snapshot['SnapshotId']} for {volume_id} ({device})")
    
    # ===== IAM USER ISOLATION =====
    elif resource_type == 'AwsIamUser':
        username = resource.get('Details', {}).get('AwsIamUser', {}).get('UserName', '')
        
        if username:
            print(f"Disabling IAM user: {username}")
            
            # Disable all access keys
            keys = iam.list_access_keys(UserName=username)
            for key in keys['AccessKeyMetadata']:
                iam.update_access_key(
                    UserName=username,
                    AccessKeyId=key['AccessKeyId'],
                    Status='Inactive'
                )
                actions_taken.append(f"Disabled access key {key['AccessKeyId']} for {username}")
            
            # Attach emergency deny policy
            deny_policy = json.dumps({
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Deny",
                    "Action": "*",
                    "Resource": "*"
                }]
            })
            
            iam.put_user_policy(
                UserName=username,
                PolicyName='EMERGENCY-DENY-ALL',
                PolicyDocument=deny_policy
            )
            
            actions_taken.append(f"Attached deny-all policy to {username}")
    
    # ===== SEND ALERT =====
    alert_message = f"""
🚨 AUTOMATED INCIDENT RESPONSE TRIGGERED 🚨

Finding Type: {finding_type}
Severity: {severity}
Title: {title}
Finding ID: {finding_id}
Time: {datetime.utcnow().isoformat()} UTC

Actions Taken Automatically:
{chr(10).join(f"  ✓ {action}" for action in actions_taken)}

REQUIRED: Human analyst must now:
  1. Review the finding in GuardDuty/Security Hub
  2. Confirm isolation was appropriate
  3. Begin forensic investigation
  4. Open incident ticket
  5. Restore service when cleared

GuardDuty Console: https://console.aws.amazon.com/guardduty/home#/findings
Security Hub: https://console.aws.amazon.com/securityhub/home#/findings
    """
    
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"[CRITICAL] Auto-IR: {finding_type} - {severity}",
        Message=alert_message
    )
    
    print(f"Incident response complete. Actions: {actions_taken}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'finding_id': finding_id,
            'actions_taken': actions_taken
        })
    }
```

### Set environment variables

```
Lambda → Configuration → Environment variables
  ISOLATION_SG_ID = sg-xxxxxxxxxx  (the isolation SG from Step 1)
  SNS_TOPIC_ARN   = arn:aws:sns:us-east-2:ACCOUNT-ID:lab-security-alerts
```

---

## Step 4 — Create the EventBridge Rule

**Console path:** `EventBridge → Rules → Create rule`

| Field | Value |
|-------|-------|
| Name | `guardduty-auto-isolate-high` |
| Event bus | default |
| Rule type | Rule with an event pattern |

Event pattern:

```json
{
  "source": ["aws.guardduty"],
  "detail-type": ["GuardDuty Finding"],
  "detail": {
    "findings": {
      "Severity": {
        "Label": ["HIGH", "CRITICAL"]
      }
    }
  }
}
```

Target: Lambda function → `IncidentResponder-IsolateEC2`

---

## Step 5 — Test the Automation

### Test with GuardDuty sample findings

```
GuardDuty → Settings → Sample findings → Generate sample findings
```

This triggers the EventBridge rule → Lambda → you should receive an SNS email within 30 seconds.

### Test with a real simulation

Trigger a GuardDuty finding by querying the test domain:

```bash
# SSH into lab-web-server
curl http://guarddutyc2activityb.com
```

Wait 5–15 minutes. GuardDuty generates `Backdoor:EC2/C&CActivity.B` (High severity).

EventBridge catches it → Lambda runs → security group replaced → EBS snapshot taken → email sent.

Verify isolation:

```bash
# Try to SSH into the instance — should time out
ssh -i lab-key.pem ec2-user@<public-ip>
# Expected: Connection timed out (isolation worked)

# Check the security group that is now attached
aws ec2 describe-instances \
  --instance-ids <instance-id> \
  --query 'Reservations[0].Instances[0].SecurityGroups'
# Expected: only ISOLATION-NO-ACCESS
```

---

## Step 6 — Restore After Investigation

Once investigation is complete and the instance is cleared:

```bash
INSTANCE_ID="i-xxxxxxxxxxxxxxxxx"

# Get the original security groups from the tag
ORIGINAL_SGS=$(aws ec2 describe-tags \
  --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=OriginalSGs" \
  --query 'Tags[0].Value' --output text)

# Convert comma-separated string to array
IFS=',' read -ra SGS <<< "$ORIGINAL_SGS"

# Restore original security groups
aws ec2 modify-instance-attribute \
  --instance-id $INSTANCE_ID \
  --groups "${SGS[@]}"

# Update the security status tag
aws ec2 create-tags \
  --resources $INSTANCE_ID \
  --tags Key=SecurityStatus,Value=CLEARED \
         Key=ClearedAt,Value=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
         Key=ClearedBy,Value=analyst-yourname

echo "Instance $INSTANCE_ID restored to normal operation"
```

---

## Step 7 — Extend to IAM Compromise

Add a second Lambda for IAM-specific response:

```python
def respond_to_iam_compromise(username, finding_id):
    """Automatically contain a compromised IAM user."""
    
    # 1. Disable all access keys
    keys = iam.list_access_keys(UserName=username)
    for key in keys['AccessKeyMetadata']:
        iam.update_access_key(
            UserName=username,
            AccessKeyId=key['AccessKeyId'],
            Status='Inactive'
        )
    
    # 2. Delete console login profile (disable console access)
    try:
        iam.delete_login_profile(UserName=username)
    except iam.exceptions.NoSuchEntityException:
        pass  # No console access configured
    
    # 3. Attach deny-all policy
    iam.put_user_policy(
        UserName=username,
        PolicyName=f'EMERGENCY-DENY-{finding_id[:8]}',
        PolicyDocument=json.dumps({
            "Version": "2012-10-17",
            "Statement": [{"Effect": "Deny", "Action": "*", "Resource": "*"}]
        })
    )
    
    return f"IAM user {username} fully locked down"
```

---

## Automation Coverage Matrix

| Finding Type | Automated Action | Human Follow-up |
|-------------|-----------------|----------------|
| EC2/SSHBruteForce | Isolate instance | Review auth logs |
| EC2/CryptoCurrency | Isolate instance, snapshot | Malware analysis |
| IAMUser/AnomalousBehavior | Disable user, deny policy | Full IAM audit |
| S3/AnomalousBehavior | Restrict bucket policy | Review access logs |
| EC2/UnauthorizedAccess | Isolate instance | Forensic investigation |
| Stealth/CloudTrailLogging | Re-enable CloudTrail, alert | Investigate who disabled |

---

## Phase 3 Complete 🎉

You now have full cloud forensics and incident response capabilities:

- [x] EBS snapshot forensics — disk evidence acquisition
- [x] CloudTrail log analysis — attacker timeline reconstruction
- [x] Memory acquisition — RAM evidence capture
- [x] Compromised IAM response — credential incident playbook
- [x] S3 breach investigation — data exfiltration analysis
- [x] Lambda auto-isolation — automated first response

**Next:** Phase 4 — Red Team & Adversary Simulation  
Start with: `22-cloudgoat-lab-setup.md`

---

## Cleanup

```
Lambda → Functions → delete IncidentResponder-IsolateEC2
EventBridge → Rules → delete guardduty-auto-isolate-high
EC2 → Security Groups → delete ISOLATION-NO-ACCESS
IAM → Roles → delete LambdaIncidentResponderRole
```

---

*Phase 3 · AWS Cybersecurity & Digital Forensics Roadmap*
