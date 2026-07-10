# 💰 Billing & Cost Controls: Protect Your $100

> **Phase 1 · Document 8 of 29**  
> **Estimated cost:** Free to set up · **Estimated time:** 30 minutes  
> **Do this first:** Before any other lab work

---

## Why This Document Exists

AWS can charge you real money for mistakes. A forgotten NAT Gateway costs $32/month. An idle RDS instance costs ~$25/month. A misconfigured data transfer can cost hundreds.

With $100 in credits, proper cost controls are what keep your entire 20-week roadmap funded.

---

## Step 1: Understand the Free Tier

These services are free within limits every month:

| Service | Free tier allowance |
|---------|-------------------|
| EC2 | 750 hours of t2.micro or t3.micro per month |
| S3 | 5 GB storage, 20,000 GET requests, 2,000 PUT requests |
| RDS | 750 hours of db.t2.micro, 20 GB storage |
| Lambda | 1 million requests, 400,000 GB-seconds compute |
| CloudWatch | 10 custom metrics, 10 alarms, 5 GB log ingestion |
| CloudTrail | 1 trail, management events only |
| Data transfer | 100 GB outbound per month |

> Free tier lasts 12 months from account creation. After that, all usage is billed.

---

## Step 2: Set Billing Alerts (Do This Now)

### Enable billing alerts

```
Billing → Billing preferences → Alert preferences
→ Enable AWS Free Tier alerts: ON
→ Enable CloudWatch billing alerts: ON
→ Save preferences
```

### Create budget alerts at three levels

**Console path:** `Billing → Budgets → Create budget`

#### Budget 1: Early warning at $20

| Field | Value |
|-------|-------|
| Budget type | Cost budget |
| Budget name | `lab1-warning-20` |
| Budgeted amount | $20 |
| Alert threshold | 80% actual ($16) → email |
| Alert threshold | 100% actual ($20) → email |

#### Budget 2: Serious warning at $50

| Field | Value |
|-------|-------|
| Budget name | `lab1-warning-50` |
| Budgeted amount | $50 |
| Alert threshold | 100% actual ($50) → email |

#### Budget 3: Emergency at $100

| Field | Value |
|-------|-------|
| Budget name | `lab1-emergency-100` |
| Budgeted amount | $100 |
| Alert threshold | 100% actual ($100) → email + SMS |

> Do not wait for the alert at $100 to take action. The $20 alert is your "check what is running" signal.

---

## Step 3: Enable Cost Explorer

Cost Explorer lets you see exactly what you are spending and where.

```
Billing → Cost Explorer → Enable Cost Explorer
```

It takes 24 hours to populate. Once active, use it to:
- See spending by service
- See spending by region
- Identify unexpected charges
- Forecast future spend

---

## Step 4: The Most Expensive Services to Watch

These are the services that surprise beginners with unexpected charges:

### NAT Gateway
**Cost:** ~$0.045/hour = **$32/month** + $0.045 per GB data processed  
**Trap:** Easy to create during a VPC lab and forget  
**Fix:** Delete immediately when done: `VPC → NAT Gateways → Delete`

### RDS (Relational Database)
**Cost:** db.t3.micro = ~$0.017/hour = **$12/month** (outside free tier)  
**Trap:** RDS cannot be stopped permanently, only for 7 days  
**Fix:** Delete the instance when not in use, take a final snapshot

### Elastic IP (unassociated)
**Cost:** ~$0.005/hour = **$3.60/month** per unassociated IP  
**Trap:** Created for a lab, instance terminated, IP forgotten  
**Fix:** Release all unassociated Elastic IPs after each lab

### Data Transfer
**Cost:** $0.09 per GB outbound (after 100 GB free)  
**Trap:** Large file downloads from EC2 to your laptop  
**Fix:** Keep data transfers within the same region where possible

### CloudWatch Logs
**Cost:** $0.50 per GB ingested, $0.03 per GB stored per month  
**Trap:** Verbose application logs streaming to CloudWatch  
**Fix:** Set retention periods on all log groups (7–30 days for labs)

### Secrets Manager
**Cost:** $0.40 per secret per month  
**Trap:** Creating many secrets during testing  
**Fix:** Delete test secrets immediately

---

## Step 5: Cost Allocation Tags

Tags let you track spending by project, environment, or team.

**Console path:** `Billing → Cost allocation tags → Activate`

Activate these tags:
- `Environment`
- `Project`
- `Sub-Project`
- `Owner`

Then tag every resource you create:

```bash
# Tag an EC2 instance
aws ec2 create-tags \
  --resources i-1234567890abcdef0 \
  --tags Key=Environment Value=Development, Key=Project,Value=CyberSecRoadmap, Key=Sub-Project,Value=Lab1

# Tag an S3 bucket
aws s3api put-bucket-tagging \
  --bucket my-bucket \
  --tagging 'TagSet=[{Key=Environment,Value=Lab}]'
```

After 24 hours, Cost Explorer will show spending broken down by tag: you can see exactly which lab exercise cost what.

---

## Step 6: AWS Trusted Advisor

Trusted Advisor checks your account for cost savings, security issues, and performance problems.

```
Trusted Advisor → Cost optimization
```

Free tier checks include:
- Idle EC2 instances (running but doing nothing)
- Unassociated Elastic IPs
- Underutilized EBS volumes
- S3 buckets without versioning (security check)

Run this after every lab session to catch forgotten resources.

---

## Step 7: End-of-Lab Cleanup Checklist

Run through this after every lab session:


**EC2:**
- [x] Terminate all lab instances (not just stop: terminate)
- [x] Delete unattached EBS volumes
- [x] Release all unassociated Elastic IPs
- [x] Delete unused AMIs
- [x] Delete old snapshots

**VPC:**
- [x] Delete NAT Gateways
- [x] Delete unused Elastic IPs
- [x] Delete VPC endpoints you are not using

**S3:**
- [x] Empty and delete test buckets
- [x] Check bucket storage size

**RDS:**
- [x] Delete lab databases (take snapshot first if needed)

**CloudWatch:**
- [x] Check log group retention periods are set

**Other:**
- [x] Check Secrets Manager for unused secrets
- [x] Check any running Load Balancers


---

## Step 8: Check Your Bill Weekly

Make this a habit:

```
Billing → Bills → current month
```

Look at each service line. Anything unexpected, investigate immediately. Small charges left unchecked become large bills.

The AWS Cost Anomaly Detection service can automate this:

```
Billing → Cost Anomaly Detection → Create monitor
  Monitor type: AWS services
  Alert threshold: $5 anomaly
  Notification: your email
```

This sends an alert whenever spending on any service deviates significantly from your normal pattern.

---

## Quick Reference: Hourly Costs

| Resource | Cost per hour | Cost if left running 1 month |
|----------|--------------|------------------------------|
| t2.micro EC2 | $0.0116 | ~$8.50 |
| t3.small EC2 | $0.0208 | ~$15 |
| NAT Gateway | $0.045 | ~$32 |
| db.t3.micro RDS | $0.017 | ~$12 |
| Application Load Balancer | $0.008 | ~$5.80 |
| Elastic IP (unassociated) | $0.005 | ~$3.60 |

> **Rule of thumb:** If you are not actively using it, delete it. This lab roadmap uses ephemeral resources: build, learn, delete.

---

## Phase 1 Complete 🎉

You now have all foundational AWS skills:

- [x] VPC from scratch
- [x] IAM users, groups, roles, policies
- [x] EC2 instance lifecycle
- [x] S3 buckets and policies
- [x] Security groups and NACLs
- [x] CloudTrail setup
- [x] CloudWatch alarms
- [x] Billing and cost controls

**Next:** Phase 2: Security & Blue Team  
Start with: `09-guardduty-setup-and-findings.md`

---

*Phase 1 · AWS Cybersecurity & Digital Forensics Roadmap*
