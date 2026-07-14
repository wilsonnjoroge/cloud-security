# ⚙️ AWS Config: Configuration Tracking & Drift Detection

> **Phase 2 · Document 11 of 29**  
> **Estimated cost:** ~$2–3/month · **Estimated time:** 45–60 minutes  
> **Prerequisites:** `04-s3-buckets-and-policies.md`, `06-cloudtrail-setup.md`

---

## What Is AWS Config?

AWS Config continuously records the configuration state of your AWS resources. Every time a resource changes: a security group rule is added, an S3 bucket policy is modified, an EC2 instance is stopped: Config records the before and after state.

```
Resource changes
      │
      ▼
AWS Config records configuration snapshot
      │
      ├──→ Configuration history (what changed, when)
      ├──→ Compliance rules (is this configuration allowed?)
      └──→ Drift detection (does this match the expected state?)
```

> **Forensics relevance:** Config lets you reconstruct the exact state of any resource at any point in time. In an incident, you can answer: "What did this security group look like 3 hours before the breach?" CloudTrail tells you who made changes: Config tells you exactly what changed.

---

## CloudTrail vs AWS Config: Key Difference

| | CloudTrail | AWS Config |
|-|-----------|-----------|
| Records | API calls (actions) | Resource states (configurations) |
| Answers | Who did what and when | What did a resource look like at time X |
| Use in IR | Attacker timeline | Resource state reconstruction |
| Analogy | Activity log | Photograph of every resource, taken continuously |

> You need both. CloudTrail = the verbs. Config = the nouns.

---

## Step 1: Enable AWS Config

**Console path:** `AWS Config → Get started`

| Field | Value |
|-------|-------|
| Record all resources | Yes |
| Include global resources (IAM) | Yes |
| S3 bucket | Create new → `lab1-config-logs` |
| SNS topic | Create new → `lab1-config-alerts` |
| AWS Config role | Create new role |


On the rules, select the following:


| Rule | What it flags | Why it matters here |
|---|---|---|
| `s3-bucket-public-read-prohibited` | Any S3 bucket becoming publicly readable | Directly checks the exact misconfiguration named in `04-s3-buckets-and-policies.md` as the leading cause of cloud data breaches |
| `s3-bucket-public-write-prohibited` | Any S3 bucket becoming publicly writable | Same reasoning; write access is the more severe case |
| `s3-bucket-versioning-enabled` | Versioning turned off on a bucket that had it enabled | Confirms the versioning discipline from doc 04 stays intact over time |
| `restricted-ssh` | Any security group allowing SSH from `0.0.0.0/0` | Catches accidental security-group drift back toward the exact misconfiguration doc 05 was built to prevent |
| `iam-user-mfa-enabled` | IAM users without MFA enabled | Ties directly to the IAM discipline established in doc 02 |
| `iam-root-access-key-check` | A root account access key existing at all | Should always show compliant, given the root-account setup in doc 02 — flags immediately if that ever changes |
| `cloudtrail-enabled` | CloudTrail disabled or misconfigured | A second, independent layer watching the same "attacker disables logging to cover tracks" scenario already alerted on via CloudWatch in doc 06 |
| `guardduty-enabled-centralized` | GuardDuty disabled | Confirms the detection enabled in doc 09 doesn't silently lapse |
| `vpc-flow-logs-enabled` | Flow logs turned off on a VPC | Confirms the network evidence trail from doc 10 stays enforced going forward |
| `ec2-instance-no-public-ip` | EC2 instances with a public IP, scoped to ones that shouldn't have one | Relevant specifically for private-tier instances (e.g. the app server), which should never have a public IP |


Click **Confirm**.


---

## Step 2: Explore the Resource Inventory

```
AWS Config → Resources inventory
```

Browse the resources Config has discovered:
- EC2 instances
- Security groups
- VPCs and subnets
- S3 buckets
- IAM users, roles, and policies

Click on any resource to see its **configuration timeline**: a history of every change ever made to it.

---

## Step 3: View Configuration Timeline

Click on your `lab1-web-server` EC2 instance in the resource inventory.

The timeline shows every configuration change:
- When the instance was launched
- When security groups were attached/detached
- When the IAM role was modified
- When the instance was stopped or started

Click **Changes** on any timeline entry to see exactly what changed:

```json
// Before change:
"securityGroups": ["sg-web-server"]

// After change:
"securityGroups": ["sg-web-server", "sg-unknown-new-group"]
```

> In an incident, this is how you find backdoor security groups added by an attacker. The change is timestamped and tied to a CloudTrail event.

---

## Step 4: Create a Custom Config Rule

Custom rules use Lambda functions to evaluate resources.

Example: flag any EC2 instance not tagged with `Environment`:

**Console path:** `Lambda → Create function`

```python
import boto3
import json

def lambda_handler(event, context):
    config = boto3.client('config')
    
    invoking_event = json.loads(event['invokingEvent'])
    configuration_item = invoking_event['configurationItem']
    
    # Check if Environment tag exists
    tags = configuration_item.get('tags', {})
    
    if 'Environment' in tags:
        compliance = 'COMPLIANT'
    else:
        compliance = 'NON_COMPLIANT'
    
    config.put_evaluations(
        Evaluations=[{
            'ComplianceResourceType': configuration_item['resourceType'],
            'ComplianceResourceId': configuration_item['resourceId'],
            'ComplianceType': compliance,
            'OrderingTimestamp': configuration_item['configurationItemCaptureTime']
        }],
        ResultToken=event['resultToken']
    )
```

Then in AWS Config:

```
Rules → Add rule → Create custom Lambda rule
  Name:       ec2-requires-environment-tag
  Lambda ARN: arn:aws:lambda:us-east-2:ACCOUNT:function:CheckEnvironmentTag
  Trigger:    Configuration changes → EC2 instance
```

---

## Step 6: Conformance Packs

Conformance packs bundle multiple Config rules into a single deployable package. AWS provides packs for common compliance frameworks.

```
AWS Config → Conformance packs → Deploy conformance pack
```

Useful packs:

| Pack name | Framework |
|-----------|----------|
| `AWS-BestPractices` | AWS general security best practices |
| `NIST-800-53-rev5` | NIST 800-53 Rev 5 |
| `PCI-DSS` | Payment Card Industry DSS |
| `CIS-AWS-Foundations-Benchmark` | CIS AWS Foundations |

> For your cybersecurity career, familiarity with CIS Benchmarks and NIST 800-53 is essential. Config makes compliance measurable and continuous rather than a point-in-time audit.

---

## Step 7: Drift Detection with Config

Drift is when a resource's actual configuration diverges from its expected (baseline) configuration.

### Establish a baseline

After completing your VPC setup:

```
AWS Config → Resources → select lab-vpc
→ Configuration timeline → note the current configuration
```

Save this as your baseline. This is what the VPC should look like.

### Simulate drift

Add an unexpected inbound rule to your security group:

```
EC2 → Security Groups → lab-web-sg → Edit inbound rules
→ Add: All traffic, source 0.0.0.0/0 (simulating a misconfiguration)
```

### Detect the drift

Within minutes, the `restricted-ssh` Config rule should flag as NON_COMPLIANT.

Also check:

```
AWS Config → Resources → lab-web-sg → Configuration timeline
```

You'll see the before and after: exactly what rule was added.

### Automated remediation

Config can auto-remediate findings:

```
AWS Config → Rules → restricted-ssh → Actions → Manage remediation
  Remediation action: AWS-DisablePublicAccessForSecurityGroup
  Auto remediation: Enable
  Retry attempts: 3
```

Now if an unauthorized rule is added, Config automatically removes it.

---

## Step 8: Config Aggregator (Multi-Account View)

In enterprise environments, Config aggregates compliance data from all accounts:

```
AWS Config → Aggregators → Create aggregator
  Name:    enterprise-aggregator
  Source:  Add individual accounts or entire AWS Organization
```

The aggregator gives a single compliance dashboard across hundreds of accounts: essential for enterprise security operations.

---

## Forensics Use Case: Reconstruct Security Group State

**Scenario:** A breach occurred. You need to know what the security group looked like at the time of the incident.

```
AWS Config → Resources → select the security group
→ Configuration timeline → navigate to the timestamp of the incident
```

You see the exact inbound rules that were active at that moment: including any rules an attacker may have added or removed to facilitate access.

Cross-reference with CloudTrail:

```
CloudTrail → Event history
→ filter: Event name = AuthorizeSecurityGroupIngress
→ filter: Time range = around the incident time
```

Now you have both: what the rules were (Config) and who changed them and when (CloudTrail).

---

## Common CLI Commands

```bash
# Get the configuration of a resource at a point in time
aws configservice get-resource-config-history \
  --resource-type AWS::EC2::SecurityGroup \
  --resource-id sg-xxxxxxxx \
  --limit 10

# List all non-compliant resources
aws configservice describe-compliance-by-resource \
  --compliance-types NON_COMPLIANT

# List all Config rules and their compliance status
aws configservice describe-config-rules

# Trigger a re-evaluation of a rule
aws configservice start-config-rules-evaluation \
  --config-rule-names restricted-ssh
```

---

## Config Rule Compliance Dashboard

**Console path:** `AWS Config → Dashboard`

The dashboard shows:
- Total resources tracked
- Compliant vs non-compliant resources
- Rules with most violations
- Recently changed resources

> Make it a habit to check this dashboard weekly. A new non-compliance finding that appeared overnight is worth investigating: it may be unauthorized change or an attacker's fingerprint.

---

## Cleanup

```
# Config costs ~$0.003 per configuration item recorded
# For a small lab: ~$2-3/month

# To stop charges:
AWS Config → Settings → Edit → uncheck "Record all resources"

# Keep the S3 bucket (evidence archive) but set lifecycle to expire after 90 days
```

---

## Phase 2 Progress Tracker

- [x] GuardDuty setup and findings
- [x] VPC Flow Logs and analysis
- [x] AWS Config and drift detection
- [ ] Security Hub overview
- [ ] WAF setup
- [ ] KMS encryption basics
- [ ] Secrets Manager

---

*Phase 2 · AWS Cybersecurity & Digital Forensics Roadmap*
