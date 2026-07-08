# 📊 CloudWatch: Monitoring, Alarms & Dashboards

> **Phase 1 · Document 7 of 29**  
> **Estimated cost:** ~$1–2/month · **Estimated time:** 45–60 minutes  
> **Prerequisites:** `03-ec2-instance-lifecycle.md`, `06-cloudtrail-setup.md`

---

## What Is CloudWatch?

CloudWatch is AWS's monitoring and observability service. It collects metrics, logs, and events from across your AWS environment and lets you visualize, alert, and react to them.

```
AWS Services → emit metrics/logs → CloudWatch
                                        │
                    ┌───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼
               Dashboards           Alarms             Log Insights
            (visualize)           (alert)              (query)
```

> **Security relevance:** CloudWatch is how you detect anomalies in real time CPU spikes from cryptomining, failed login attempts, unusual API call volumes, network traffic changes.

---

## Core CloudWatch Concepts

| Concept | What it is |
|---------|-----------|
| **Metric** | A time-series data point (e.g. CPUUtilization, NetworkIn) |
| **Namespace** | A container for metrics (e.g. `AWS/EC2`, `AWS/S3`) |
| **Dimension** | A label that scopes a metric (e.g. InstanceId=i-xxx) |
| **Alarm** | A rule that triggers when a metric crosses a threshold |
| **Log group** | A container for log streams from one source |
| **Log stream** | The actual sequence of log events from one resource |
| **Dashboard** | A custom visualization of multiple metrics |

---

## Step 1 Explore Default EC2 Metrics

**Console path:** `CloudWatch → Metrics → All metrics → AWS/EC2`

Select your `lab1-web-server  instance ID` and browse available metrics:

| Metric | What it shows | Security relevance |
|--------|--------------|-------------------|
| `CPUUtilization` | % CPU in use | Sudden spike may indicate cryptomining |
| `NetworkIn` | Bytes received | Large spike may indicate data download |
| `NetworkOut` | Bytes sent | Large spike may indicate data exfiltration |
| `StatusCheckFailed` | Instance health | Sudden failure may indicate tampering |
| `DiskReadOps` | Disk read operations | Unusual activity may indicate data staging |

---

## Step 2 Create a CPU Alarm

High CPU on a server that should be idle is a common indicator of compromise cryptomining, brute-force tools, or malware.

**Console path:** `CloudWatch → Alarms → Create alarm`

```
Select metric → EC2 → Per-Instance Metrics → CPUUtilization
Select your instance ID → Select metric
```

| Field | Value |
|-------|-------|
| Statistic | Average |
| Period | 5 minutes |
| Threshold type | Static |
| Condition | Greater than 80 |
| Datapoints to alarm | 2 out of 3 |

### Set up SNS notification

```
Alarm state trigger: In alarm
Create new SNS topic: `Lab1_CloudWatch_Alarms_Topic`
Email endpoint: your email address
```

Confirm the subscription email AWS sends you.


### Enter the Alarm name and description

```
Alarm Name: lab1-web-server-CPU-utilization  
Description: Alarm for cpu utilization above 80%
```


> **Datapoints to alarm 2 out of 3:** This means CPU must exceed 80% in 2 of the last 3 five-minute periods before the alarm fires. This prevents false alerts from brief legitimate spikes.

---

## Step 3 Create a Network Anomaly Alarm

Unusual outbound traffic is a key indicator of data exfiltration.

```
CloudWatch → Alarms → Create alarm
→ EC2 → NetworkOut → select instance
```
lab1-web-server-CPU-utilization

| Field | Value |
|-------|-------|
| Name | lab1-web-server-data-exfiltration |
| Statistic | Average |
| Period | 5 minutes |
| Threshold | Greater than 10000000 (10 MB per 5 min) |
| Action | Send to `Lab1_CloudWatch_Alarms_Topic` SNS topic |

> Adjust the threshold based on what is normal for your workload. A web server with low traffic sending 10MB in 5 minutes is suspicious. A file server doing backups might send gigabytes that would be normal.

---

## Step 4 Install the CloudWatch Agent on EC2

The default EC2 metrics don't include memory usage or disk space the agent adds these.

SSH into your instance and run:

```bash
# Download and install the agent
sudo yum install -y amazon-cloudwatch-agent

# Create the config file
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard
```

Answer the wizard prompts:
- OS: Linux
- EC2: Yes
- StatsD daemon: No
- CollectD: No
- CPU metrics: Yes
- **Memory metrics: Yes** ← this is what we need
- **Disk metrics: Yes** ← this too
- Log files: Yes → add `/var/log/secure` (SSH auth logs)

```bash
Alternatively, run the following:

sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json >/dev/null <<'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}"
    },
    "metrics_collected": {
      "cpu": {
        "resources": ["*"],
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "totalcpu": true
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ]
      },
      "disk": {
        "resources": ["*"],
        "measurement": [
          "used_percent"
        ],
        "ignore_file_system_types": [
          "sysfs",
          "devtmpfs",
          "tmpfs"
        ]
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/secure",
            "log_group_name": "/var/log/secure",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF


Then apply with this command:

sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s


Confirm Validation:

sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.d/file_amazon-cloudwatch-agent.json -s

```

Start the Agent:

```bash


sudo systemctl restart amazon-cloudwatch-agent && sudo systemctl status amazon-cloudwatch-agent --no-pager

```

Now check `CloudWatch → Metrics → CWAgent` for memory and disk metrics.

```bash
Incase the log group isnt created in Cloudwatc, follow the following:  

sudo dnf install -y rsyslog && sudo systemctl enable --now rsyslog

sudo tee /etc/rsyslog.d/sshd.conf >/dev/null <<'EOF'
authpriv.*    /var/log/secure
EOF

sudo systemctl restart rsyslog

sudo ls -l /var/log/secure

sudo systemctl restart amazon-cloudwatch-agent

sudo tail -20 /var/log/secure

```

---

## Step 5 Set Up Log Monitoring for SSH Failures

Failed SSH login attempts are logged in `/var/log/secure`. Stream them to CloudWatch and alert on them.

### Create a metric filter

```
CloudWatch → Log groups → find your /var/log/secure log group
→ Metric filters → Create metric filter
```

Filter pattern:
```
[Mon, day, timestamp, ip, id, msg1="Failed", msg2="password", ...]
```

| Field | Value |
|-------|-------|
| Metric namespace | `SecurityMetrics` |
| Metric name | `SSHFailedLogins` |
| Metric value | `1` |
| Default value | `0` |

Create an alarm on this metric: threshold ≥ 5 in 5 minutes → alert.

> 5 failed SSH logins in 5 minutes is a brute-force attempt. Alert immediately.

---

## Step 6 Create a Security Dashboard

A dashboard gives you a single pane of glass for your security posture.

**Console path:** `CloudWatch → Dashboards → Create dashboard`

Name: `lab1-security-dashboard`

Add these widgets:

| Widget | Metric | Why |
|--------|--------|-----|
| Line graph | CPUUtilization (all instances) | Spot cryptomining |
| Line graph | NetworkOut (all instances) | Spot exfiltration |
| Number | StatusCheckFailed | Instance health at a glance |
| Line graph | SSHFailedLogins (custom metric) | Spot brute force |
| Alarm status | All alarms | Current security state |
| Log table | CloudTrail errors (Log Insights widget) | Recent failures |

---

## Step 7 CloudWatch Logs Query SSH Auth Log

With `/var/log/secure` streaming to CloudWatch, you can query it:

**Console path:** `CloudWatch → Logs Insights`

### Find all successful SSH logins

```sql
fields @timestamp, @message
| filter @message like /Accepted password/
| sort @timestamp desc
| limit 20
```

### Find all failed SSH logins with source IPs

```sql
fields @timestamp, @message
| filter @message like /Failed password/
| parse @message "from * port" as sourceIP
| stats count(*) as attempts by sourceIP
| sort attempts desc
```

### Find sudo usage (privilege escalation detection)

```sql
fields @timestamp, @message
| filter @message like /sudo/
| sort @timestamp desc
| limit 50
```

---

## Step 8 CloudWatch Anomaly Detection

Instead of setting a static threshold, anomaly detection learns what is normal and alerts on deviations.

```
CloudWatch → Alarms → Create alarm
→ Select metric: CPUUtilization
→ Threshold type: Anomaly detection
→ Anomaly detection threshold: 2 (standard deviations)
```

CloudWatch builds a model of your instance's normal CPU pattern (including daily/weekly cycles) and alerts when it deviates significantly.

> This is more powerful than static thresholds for detecting subtle attacks that stay under a fixed limit but are still abnormal for that specific workload.

---

## Step 9 EventBridge Rules (Automated Response)

CloudWatch alarms can trigger EventBridge rules which can trigger Lambda functions for automated response.

Example automatically isolate an instance when CPU spikes:

```
CloudWatch Alarm (CPU > 80%) 
    → EventBridge rule 
    → Lambda function 
    → Modify security group (remove all inbound rules)
    → Send alert
```

This is covered in detail in `21-lambda-auto-isolation.md`.

---

## Useful Metrics Reference

### EC2 security-relevant metrics

| Metric | Namespace | Alarm threshold |
|--------|-----------|----------------|
| CPUUtilization | AWS/EC2 | > 80% |
| NetworkOut | AWS/EC2 | Anomaly detection |
| StatusCheckFailed | AWS/EC2 | >= 1 |
| SSHFailedLogins | SecurityMetrics (custom) | >= 5 in 5 min |

### S3 security-relevant metrics

| Metric | What to watch for |
|--------|------------------|
| `NumberOfObjects` | Sudden large increase may indicate data staging |
| `BucketSizeBytes` | Unusual decrease may indicate deletion |
| `AllRequests` | Spike may indicate enumeration attack |

---

## Common CLI Commands

```bash
# List all alarms and their state
aws cloudwatch describe-alarms --state-value ALARM

# Get metric statistics
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=i-1234567890abcdef0 \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Average

# Put a custom metric data point
aws cloudwatch put-metric-data \
  --namespace SecurityMetrics \
  --metric-name TestAlert \
  --value 1
```

---

## Cleanup

```
# CloudWatch logs incur storage costs
# Reduce retention on log groups you don't need long-term:
CloudWatch → Log groups → select group → Actions → Edit retention → 7 days

# Delete test alarms:
CloudWatch → Alarms → select alarms → Actions → Delete

# Dashboards are free keep them
```

---

## Phase 1 Progress Tracker

- [x] VPC from scratch
- [x] IAM users, groups, roles, policies
- [x] EC2 instance lifecycle
- [x] S3 buckets and policies
- [x] Security groups and NACLs
- [x] CloudTrail setup
- [x] CloudWatch alarms
- [ ] Billing and cost controls

---

*Phase 1 · AWS Cybersecurity & Digital Forensics Roadmap*
