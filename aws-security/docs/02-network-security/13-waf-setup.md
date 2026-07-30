# 🧱 WAF: Web Application Firewall

> **Phase 2 · Document 13 of 29**
> **Estimated cost:** ~$5–10/month · **Estimated time:** 60 minutes
> **Prerequisites:** `03-ec2-instance-lifecycle.md`, `05-security-groups-and-nacls.md`

---

## What Is AWS WAF?

AWS WAF (Web Application Firewall) protects web applications from common exploits at the HTTP layer: SQL injection, cross-site scripting (XSS), bad bots, and more. It operates at Layer 7 (application layer), unlike security groups and NACLs which operate at Layer 3/4.

```
Internet request
      │
      ▼
[ AWS WAF ] ← inspects HTTP headers, body, URI, query strings
      │
      ├── Block → request dropped, 403 returned
      └── Allow → request passes to your application
                        │
                        ▼
               [ ALB / CloudFront / API Gateway ]
                        │
                        ▼
                  [ EC2 / Lambda ]
```

> **Security relevance:** Security groups block ports. WAF blocks attacks. A security group set to allow port 80 lets all HTTP traffic through: WAF decides which HTTP requests are legitimate.

---

## WAF Core Concepts

| Concept | What it is |
|---------|-----------|
| **Web ACL** | The top-level WAF policy: contains rules |
| **Rule** | A condition + action (allow, block, count) |
| **Rule group** | A reusable collection of rules |
| **Managed rule group** | Pre-built rules maintained by AWS or third parties |
| **IP set** | A list of IP addresses to allow or block |
| **Regex pattern set** | Patterns to match against request components |
| **Capacity units (WCU)** | A measure of rule complexity: Web ACL limit is 1500 WCU |

---

## Step 1: Create an Application Load Balancer

WAF attaches to an ALB, CloudFront, or API Gateway: not directly to EC2. Create an ALB first.

**Console path:** `EC2 → Load Balancers → Create load balancer → Application Load Balancer`

| Field | Value |
|-------|-------|
| Name | `lab1-alb` |
| Scheme | Internet-facing |
| IP address type | IPv4 |
| VPC | `lab1-vpc` |
| Subnets | Select both public subnets (need at least 2 AZs) |
| Security group | `lab1-web-server-sg ` |

![Create ALB](../screenshots/waf/01-create-alb-a.png)

![Create ALB](../screenshots/waf/01-create-alb-b.png)

![Create ALB](../screenshots/waf/01-create-alb-c.png)

![Create ALB](../screenshots/waf/01-create-alb-d.png)

### Create a target group

```
Target group name: lab1-tg
Target type:       Instances
Protocol:          HTTP
Port:              80
VPC:               lab1-vpc
```

![Create target group](../screenshots/waf/02-create-target-group-a.png)

![Create target group](../screenshots/waf/02-create-target-group-b.png)

Register your `lab1-web-server` instance as a target.

![Register instance to target group](../screenshots/waf/02-create-target-group-c-register-instance.png)

Complete the ALB creation. Note the ALB DNS name: you will use this to access your site.

---

## Step 2: Create a Web ACL

**Console path:** `WAF & Shield → Web ACLs → Create web ACL`

| Field | Value |
|-------|-------|
| Name | `lab1-web-acl` |
| Resource type | Regional resources |
| Region | us-east-2 |
| Associated resources | Select `lab1-alb` |

![Create web ACL](../screenshots/waf/03-create-web-acls-a.png)

![Create web ACL](../screenshots/waf/03-create-web-acls-b.png)

![Create web ACL](../screenshots/waf/03-create-web-acls-c.png)

---

## Step 3: Add AWS Managed Rule Groups

AWS maintains pre-built rule groups that cover the most common attacks. Add these:

**On the Add rules page → Add managed rule groups**

![Add managed rule groups](../screenshots/waf/04-create-rules-groups-a.png)

![Add managed rule groups](../screenshots/waf/04-create-rules-groups-b.png)

![Add managed rule groups](../screenshots/waf/04-create-rules-groups-c.png)

### Rule group 1: Core Rule Set (CRS)

```
AWS managed rules → Core rule set (CRS)
WCU: 700
```

Protects against:
- SQL injection
- Cross-site scripting (XSS)
- Local file inclusion (LFI)
- Remote file inclusion (RFI)
- HTTP protocol violations

![Core rule set](../screenshots/waf/04-create-rules-groups-core-rule-sets.png)

### Rule group 2: Known Bad Inputs

```
AWS managed rules → Known bad inputs
WCU: 200
```

Protects against:
- Log4Shell (Log4j JNDI injection)
- SSRF attempts via request body
- JavaDeserializationExploits

![Known bad inputs](../screenshots/waf/04-create-rules-groups-known-bad-inputs.png)

### Rule group 3: Amazon IP Reputation List

```
AWS managed rules → Amazon IP reputation list
WCU: 25
```

Blocks requests from:
- IPs associated with botnets
- IPs used in prior attacks (AWS threat intelligence)
- Tor exit nodes

![IP reputation list](../screenshots/waf/04-create-rules-groups-ip-reputation-list.png)

### Rule group 4: Anonymous IP List

```
AWS managed rules → Anonymous IP list
WCU: 50
```

Blocks requests from:
- VPN providers
- Proxies
- Tor

> This is useful for blocking anonymized attack traffic. Be careful: it may also block legitimate users using VPNs.

![Anonymous IP list](../screenshots/waf/04-create-rules-groups-anonymous-ip-list.png)

**Default action:** Allow (traffic not matching any block rule passes through)

Click **Create web ACL**.

---

## Step 4: Create Custom Rules

![Create custom rules](../screenshots/waf/05-create-custom-rules-a.png)

![Create custom rules](../screenshots/waf/05-create-custom-rules-b.png)

### Rule 1: Block a specific country

```
WAF → lab1-web-acl → Rules → Add rule → Rule builder

Name:       block-specific-country
Type:       Regular rule
Statement:
  Inspect:  Originates from a country
  Country:  Select countries you want to block
Action:     Block
Priority:   1
```

> Use this carefully: geo-blocking affects legitimate users. More useful as an incident response measure: "Block all traffic from country X while we contain an attack."

![Block certain countries](../screenshots/waf/05-create-custom-rules-block-certain-countries.png)

### Rule 2: Rate limiting (brute force protection)

```
Name:       rate-limit-per-ip
Type:       Rate-based rule
Rate limit: 1000 requests per 5 minutes per IP
Action:     Block
Priority:   2
```

Any single IP sending more than 1000 requests in 5 minutes gets blocked automatically. This stops brute-force attacks and scraping.

![Rate limit rule](../screenshots/waf/05-create-custom-rules-rte-limit.png)

### Rule 3: Block bad user agents

```
Name:       block-bad-bots
Type:       Regular rule
Statement:
  Inspect:    Single header → User-Agent
  Match type: Contains string
  Value:      sqlmap
Action:     Block
Priority:   3
```

Add multiple conditions for common attack tools: `sqlmap`, `nikto`, `masscan`, `nmap`.

### Rule 4: Allow only specific paths

For an API that should only serve `/api/` paths:

```
Name:       allow-only-api-path
Type:       Regular rule
Statement:
  Inspect:    URI path
  Match type: Doesn't start with
  Value:      /api/
Action:     Block
Priority:   4
```

---

## Step 5: Enable WAF Logging

WAF can log every request: allowed and blocked: to CloudWatch, S3, or Kinesis Firehose.

```
WAF → lab1-web-acl → Logging and metrics → Enable logging
  Logging destination: CloudWatch Logs
  Log group: aws-waf-logs-lab1-web-acl
```

![Enable logging](../screenshots/waf/06-enable-logging-a.png)

![Enable logging](../screenshots/waf/06-enable-logging-b.png)

![Enable logging](../screenshots/waf/06-enable-logging-c.png)

### Query WAF logs

```sql
-- Top blocked IPs
fields httpRequest.clientIp, action
| filter action = "BLOCK"
| stats count(*) as blocks by httpRequest.clientIp
| sort blocks desc
| limit 20

-- SQL injection attempts
fields httpRequest.clientIp, httpRequest.uri, terminatingRuleId
| filter terminatingRuleId like /SQLi/
| sort @timestamp desc

-- Rate limited IPs
fields httpRequest.clientIp, @timestamp
| filter terminatingRuleId = "rate-limit-per-ip"
| stats count(*) as hits by httpRequest.clientIp
| sort hits desc
```

---

## Step 6: WAF in Count Mode (Testing)

Before switching rules to Block mode, run them in Count mode first. This logs what would have been blocked without actually blocking: lets you validate rules won't break legitimate traffic.

```
WAF → lab1-web-acl → Rules → select a rule → Edit
  Action: Count (instead of Block)
```

![WAF in count mode for testing](../screenshots/waf/07-waf-in-count-mode-for-testing.png)

After 24–48 hours of count mode, review the logs. If no legitimate traffic is being counted, switch to Block.

---

## Step 7: AWS Shield (DDoS Protection)

Shield Standard is automatically enabled on all AWS accounts: it protects against common Layer 3/4 DDoS attacks at no cost.

Shield Advanced ($3,000/month) adds:
- Layer 7 DDoS protection with WAF
- 24/7 DDoS response team access
- Cost protection (AWS credits if DDoS causes scaling charges)

For your lab: Shield Standard is sufficient.

```
WAF & Shield → AWS Shield → Activate Shield Advanced (skip for lab)
```

---

## Step 8: Test Your WAF

### Test SQL injection blocking

```bash
# This should be blocked by the CRS rule group
curl -G \
  --data-urlencode "id=1' OR '1'='1" \
  "<ALB-DNS>/page"

# Expected response: 403 Forbidden
```

![Testing SQL injection](../screenshots/waf/08-testing-sqlinjection.png)

### Test XSS blocking

```bash

  curl -G \
  --data-urlencode "q=<script>alert(1)</script>" \
  "http://<ALB-DNS>/search"
# Expected response: 403 Forbidden
```

![Testing XSS](../screenshots/waf/08-testing-cxx.png)

### Test rate limiting

```bash
# Send 1001 requests rapidly
for i in {1..1001}; do curl -s -o /dev/null http://<ALB-DNS>/; done

# After 1000 requests: 403 Forbidden
```

### Verify in WAF logs

```
CloudWatch → Logs Insights → aws-waf-logs-lab1-web-acl
```

You should see BLOCK entries for your test requests with the matching rule ID.

![Confirm from CloudWatch logs](../screenshots/waf/09-confirm-from-cloudwatch-logs.png)

---

## WAF Rule Priority: Order Matters

Rules are evaluated top to bottom. First match wins.

```
Priority 1: IP reputation list (block known bad IPs first)
Priority 2: Rate limiting (block floods)
Priority 3: Geo-blocking (block specific countries)
Priority 4: Managed rule groups (block known attack patterns)
Priority 5: Custom rules (application-specific)
Priority 6: Default action (Allow)
```

> Put your most specific, highest-confidence rules at the top. Broad managed rule groups go below targeted custom rules.

---

## Forensics Use Case

After an application attack, WAF logs give you:
- Exact timestamp of every request
- Attacker's IP address
- What URI they targeted
- Which WAF rule blocked them (or what got through before WAF was enabled)
- User agent string (tool fingerprinting)
- Full request headers

Cross-reference WAF logs with VPC Flow Logs and CloudTrail to build a complete attack timeline.

---

## Common CLI Commands

```bash
# List all Web ACLs
aws wafv2 list-web-acls --scope REGIONAL --region us-east-2

# Get Web ACL details
aws wafv2 get-web-acl \
  --name lab1-web-acl \
  --scope REGIONAL \
  --id <web-acl-id>

# Add an IP to a block list
aws wafv2 update-ip-set \
  --name lab-block-list \
  --scope REGIONAL \
  --id <ip-set-id> \
  --addresses "198.51.100.42/32" \
  --lock-token <lock-token>
```

---

## Cleanup

```
# WAF charges:
# $5/month per Web ACL
# $1/month per rule
# $0.60 per million requests

WAF → Web ACLs → lab1-web-acl → Disassociate ALB → Delete Web ACL
EC2 → Load Balancers → Delete lab1-alb
EC2 → Target Groups → Delete lab1-tg
```

---

## Phase 2 Progress Tracker

- [x] GuardDuty setup and findings
- [x] VPC Flow Logs and analysis
- [x] AWS Config and drift detection
- [x] Security Hub overview
- [x] WAF setup
- [ ] KMS encryption basics
- [ ] Secrets Manager

---

*Phase 2 · AWS Cybersecurity & Digital Forensics Roadmap*