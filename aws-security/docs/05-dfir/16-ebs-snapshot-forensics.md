# 🖥️ EBS Snapshot Forensics: Disk Image Acquisition

> **Phase 3 · Document 16 of 29**
> **Estimated cost:** ~$2–5 · **Estimated time:** 90 minutes
> **Prerequisites:** All Phase 1 and Phase 2 documents complete

---

## The Cloud Forensics Mindset

Traditional forensics: pull the hard drive, image it, analyze offline.
Cloud forensics: the disk is a virtual EBS volume: you snapshot it, create a new volume, mount it on a forensic instance, analyze without ever touching the live system.

```
TRADITIONAL:                    CLOUD:
Compromised machine             Compromised EC2 instance
      │                               │
      ▼                               ▼
Remove hard drive               Snapshot EBS volume (non-destructive)
      │                               │
      ▼                               ▼
Write-block and image           Create new volume from snapshot
      │                               │
      ▼                               ▼
Analyze on forensic workstation Attach to forensic EC2 instance
                                      │
                                      ▼
                                Analyze (mount read-only)
```

> **Evidence preservation rule (same as traditional forensics):** Never analyze a live compromised instance directly. Always work from a copy. The original must remain unchanged.

---

## Step 1: Simulate a Compromised Instance

First, create a "compromised" instance with evidence planted on it.

Launch an EC2 instance (`lab11-compromised`) in your VPC.

![Launch compromised instance](../screenshots/snapshot-forensics/01-launch-compromised-instance.png)

SSH in and plant some evidence:

```bash
# Simulate attacker activity
sudo su -
echo "attacker_backdoor" > /tmp/backdoor.sh
echo "exfil_data_here" > /home/ubuntu/stolen_data.txt
history -w /root/.bash_history

# Create a suspicious cron job
echo "*/5 * * * * curl http://198.51.100.42/beacon" >> /etc/crontab

# Create a hidden directory
mkdir -p /var/tmp/.hidden
echo "C2 config data" > /var/tmp/.hidden/config

# Write to auth log (simulate failed logins)
logger -p auth.info "Failed password for root from 198.51.100.42 port 4444 ssh2"
logger -p auth.info "Accepted password for root from 198.51.100.42 port 4444 ssh2"
```

![Simulate attack](../screenshots/snapshot-forensics/02-simulate-attack.png)

Now **stop the instance**: never take a snapshot of a running instance for forensics (data may be inconsistent).

```
EC2 → Instances → lab11-compromised → Instance state → Stop instance
```

---

## Step 2: Acquire - Create an EBS Snapshot

This is your evidence acquisition step. The snapshot is your forensic image.

```
EC2 → Instances → lab11-compromised → Storage tab
→ Click on the root volume ID → Actions → Create snapshot

  Description: FORENSIC-COPY-lab11-compromised-[date]-[time]
  Tags:
    Purpose = ForensicEvidence
    CaseID  = IR-2024-001
    Analyst = YourName
    Hash    = (you will add this after verification)
```

![Create snapshot - select volume](../screenshots/snapshot-forensics/03-create-snapshot-a.png)
![Create snapshot - description and tags](../screenshots/snapshot-forensics/03-create-snapshot-b.png)
![Create snapshot - confirmation](../screenshots/snapshot-forensics/03-create-snapshot-c.png)

Note the snapshot ID: `snap-xxxxxxxxxxxxxxxxx`

> **Chain of custody:** Record the snapshot ID, creation time, and the IAM identity that created it in your incident log. This is your evidence intake record.

### Verify the snapshot

```bash
aws ec2 describe-snapshots \
  --snapshot-ids snap-xxxxxxxxxxxxxxxxx \
  --query 'Snapshots[0].{ID:SnapshotId,State:State,StartTime:StartTime,VolumeSize:VolumeSize}'
```

Wait for `State: completed` before proceeding.

![Verify snapshot details](../screenshots/snapshot-forensics/04-verify-snapshot-details.png)

---

## Step 3: Set Up a Forensic Workstation

Create a clean, isolated EC2 instance that has never been connected to the compromised environment.

```
EC2 → Launch instance

  Name:           lab1-forensic-workstation
  AMI:            Ubuntu 22.04 LTS
  Instance type:  t3.medium (more RAM for analysis tools)
  VPC:            lab1-vpc
  Subnet:         lab1-public-subnet
  Security group: Create new → sg-forensic
                    Inbound: SSH port 22 from your IP only
                    Outbound: All traffic
```

![Launch forensic workstation](../screenshots/snapshot-forensics/05-launch-forensics-instance.png)

### Install forensic tools

SSH into the forensic workstation and install tools:

```bash
sudo apt update && sudo apt upgrade -y

# Core forensics tools
sudo apt install -y \
  sleuthkit \
  autopsy \
  foremost \
  testdisk \
  binwalk \
  strings \
  xxd \
  hexdump \
  file \
  exiftool \
  yara \
  volatility3 \
  python3-pip \
  jq \
  awscli

# Python forensics libraries
pip3 install dfvfs plaso
```

![Install forensic tools](../screenshots/snapshot-forensics/06-install-tools.png)

---

## Step 4: Create a Volume from the Snapshot

```
EC2 → Snapshots → select your forensic snapshot → Actions → Create volume from snapshot

  Volume type:        gp3
  Size:               same as original
  Availability Zone:  us-east-2a  ← must match forensic workstation's AZ
  Encryption:         Enable → lab1-main-key
  Tags:
    Purpose = ForensicEvidence
    CaseID  = IR-2024-001
```

![Create volume from snapshot - configuration](../screenshots/snapshot-forensics/07-create-volume-from-compromised-snapshot-a.png)
![Create volume from snapshot - confirmation](../screenshots/snapshot-forensics/07-create-volume-from-compromised-snapshot-b.png)

Note the new volume ID: `vol-xxxxxxxxxxxxxxxxx`

---

## Step 5: Attach the Evidence Volume

```
EC2 → Volumes → select the evidence volume → Actions → Attach volume
  Instance:    lab1-forensic-workstation
  Device name: /dev/sdf
```

![Attach volume to forensic instance - selection](../screenshots/snapshot-forensics/08-attach-volume-to-forensics-instance-a.png)
![Attach volume to forensic instance - confirmation](../screenshots/snapshot-forensics/08-attach-volume-to-forensics-instance-b.png)

---

## Step 6: Mount Read-Only and Verify

SSH into the forensic workstation. The attached volume appears as `/dev/nvme1n1` (AWS renames `/dev/sdf`).

```bash
# Verify the device is present
lsblk

# Check the partition table
sudo fdisk -l /dev/nvme1n1

# Create a mount point
sudo mkdir -p /mnt/evidence

# Mount READ-ONLY: critical for evidence preservation
sudo mount -o ro,noload,noexec,nosuid /dev/nvme1n1p1 /mnt/evidence

# Verify mount options (must show ro)
mount | grep evidence
```

![Mount evidence volume as read-only](../screenshots/snapshot-forensics/09-mount-as-read-only.png)

> **Read-only mount is non-negotiable.** Writing to evidence changes it. `ro` flag ensures no accidental modifications. `noexec` prevents accidental execution of malicious binaries. `nosuid` prevents privilege escalation via setuid files.

### Generate hash for integrity verification

```bash
# Hash the entire raw device before analysis
sudo md5sum /dev/nvme1n1 > /home/ubuntu/evidence-hash-md5.txt
sudo sha256sum /dev/nvme1n1 >> /home/ubuntu/evidence-hash-sha256.txt

cat /home/ubuntu/evidence-hash-sha256.txt
# Record this hash in your case notes: it proves the evidence was not modified
```

---

## Step 7: File System Analysis

```bash
# List all files (including hidden)
find /mnt/evidence -type f -ls 2>/dev/null | head -100

# Find recently modified files (last 24 hours)
find /mnt/evidence -type f -newer /mnt/evidence/etc/passwd -ls 2>/dev/null

# Find files modified in a specific time range
find /mnt/evidence -type f \
  -newer /mnt/evidence/tmp \
  -not -newer /mnt/evidence/var \
  -ls 2>/dev/null

# Find SUID/SGID files (privilege escalation candidates)
find /mnt/evidence -perm /4000 -type f -ls 2>/dev/null

# Find world-writable files
find /mnt/evidence -perm -002 -type f -ls 2>/dev/null

# Find hidden files and directories
find /mnt/evidence -name ".*" -ls 2>/dev/null
```

![File system analysis - directory listing](../screenshots/snapshot-forensics/10-file-system-analysis-a.png)
![File system analysis - recently modified files](../screenshots/snapshot-forensics/10-file-system-analysis-b.png)
![File system analysis - SUID/SGID files](../screenshots/snapshot-forensics/10-file-system-analysis-c.png)
![File system analysis - world-writable files](../screenshots/snapshot-forensics/10-file-system-analysis-d.png)
![File system analysis - hidden files](../screenshots/snapshot-forensics/10-file-system-analysis-e.png)

---

## Step 8: Log Analysis

```bash
# Auth log: login activity
cat /mnt/evidence/var/log/auth.log | grep -E "(Accepted|Failed|Invalid)"

# Bash history: command history
cat /mnt/evidence/root/.bash_history
cat /mnt/evidence/home/ubuntu/.bash_history

# Cron jobs: persistence mechanisms
cat /mnt/evidence/etc/crontab
ls -la /mnt/evidence/etc/cron.*
cat /mnt/evidence/var/spool/cron/crontabs/* 2>/dev/null

# System log
cat /mnt/evidence/var/log/syslog | tail -200

# Web server logs (if applicable)
cat /mnt/evidence/var/log/apache2/access.log 2>/dev/null
cat /mnt/evidence/var/log/nginx/access.log 2>/dev/null
```

![Log analysis - auth log](../screenshots/snapshot-forensics/11-log-analysis-a.png)
![Log analysis - bash history](../screenshots/snapshot-forensics/11-log-analysis-b.png)
![Log analysis - cron jobs](../screenshots/snapshot-forensics/11-log-analysis-c.png)
![Log analysis - system log](../screenshots/snapshot-forensics/11-log-analysis-d.png)

---

## Step 9: Artifact Recovery with Sleuth Kit

```bash
# File system information
sudo fsstat /dev/nvme1n1

# List all files including deleted ones
sudo fls -r -d /dev/nvme1n1 | head -50

# Recover a deleted file by inode number
sudo icat /dev/nvme1n1 <inode-number> > /home/ubuntu/recovered_file

# Timeline of all file system activity
sudo fls -r -m / /dev/nvme1n1 > /home/ubuntu/bodyfile.txt
sudo mactime -b /home/ubuntu/bodyfile.txt -d > /home/ubuntu/timeline.csv

# View the timeline
head -50 /home/ubuntu/timeline.csv
```

The timeline shows every file creation, modification, and access with timestamps: your forensic timeline of what happened on disk.

---

## Step 10: Search for Indicators of Compromise

```bash
# Search for IP addresses in all files
grep -r "198.51.100.42" /mnt/evidence/ 2>/dev/null

# Search for base64 encoded payloads (common in malware)
grep -r "[A-Za-z0-9+/]\{50,\}={0,2}" /mnt/evidence/tmp/ 2>/dev/null

# Search for reverse shell indicators
grep -rE "(bash -i|/dev/tcp|nc -e|python.*socket)" /mnt/evidence/ 2>/dev/null

# Find recently installed packages
cat /mnt/evidence/var/log/dpkg.log | grep "install"

# Check for SSH authorized keys (backdoors)
find /mnt/evidence -name "authorized_keys" -exec cat {} \;

# Find unusual binaries in /tmp (common malware staging)
find /mnt/evidence/tmp -type f -executable -ls
```

![Indicators of compromise - IP and payload search](../screenshots/snapshot-forensics/12-indicators-of-comromise-a.png)
![Indicators of compromise - backdoor and persistence](../screenshots/snapshot-forensics/12-indicators-of-compromise-b.png)

---

## Step 11: YARA Scanning

YARA scans files against malware signatures:

```bash
# Download some YARA rules
wget https://github.com/Yara-Rules/rules/archive/refs/heads/master.zip
unzip master.zip

# Scan the evidence volume
sudo yara -r yara-rules-master/malware/*.yar /mnt/evidence/ 2>/dev/null
```

![Scan with YARA](../screenshots/snapshot-forensics/13-scan-with-yara.png)

---

## Step 12: Document Findings

Create a structured forensic report:

```bash
cat > /home/ubuntu/forensic-report-IR-2024-001.md << 'EOF'
# Forensic Analysis Report

## Case Information
- Case ID:       IR-2024-001
- Instance ID:   i-xxxxxxxxxxxxxxxxx
- Snapshot ID:   snap-xxxxxxxxxxxxxxxxx
- Evidence Hash (SHA256): [hash from Step 6]
- Analyst:       Your Name
- Date:          $(date)

## Acquisition
- Original volume acquired at: [timestamp]
- Snapshot creation time: [timestamp]
- Evidence volume attached read-only: verified

## Findings

### Timeline of Compromise
- [TIME]: Attacker connected via SSH from 198.51.100.42
- [TIME]: Privilege escalation to root
- [TIME]: Backdoor script dropped in /tmp/backdoor.sh
- [TIME]: Cron job installed for C2 beacon
- [TIME]: Data exfiltrated to external server

### Indicators of Compromise
- Malicious IP: 198.51.100.42
- Backdoor file: /tmp/backdoor.sh
- Persistence: /etc/crontab entry
- Exfiltrated data: /home/ubuntu/stolen_data.txt

### Evidence Integrity
- Hash verified before and after analysis: MATCH
- No modifications made to evidence volume

## Recommendations
1. Isolate all instances that communicated with 198.51.100.42
2. Rotate all IAM credentials on the account
3. Review CloudTrail for lateral movement
4. Check VPC Flow Logs for other exfiltration
EOF
```

![Document the findings](../screenshots/snapshot-forensics/14-document-the-findings.png)

---

## Cleanup

```
1. Unmount the evidence volume:
   sudo umount /mnt/evidence

2. Detach the evidence volume:
   EC2 → Volumes → select evidence volume → Detach

3. Keep the snapshot as long as the case is open (it is evidence)

4. Terminate the forensic workstation when done:
   EC2 → Instances → lab1-forensic-workstation → Terminate

5. Terminate the compromised instance:
   EC2 → Instances → lab11-compromised → Terminate
```

---

## Phase 3 Progress Tracker

- [x] EBS snapshot forensics
- [ ] CloudTrail log analysis
- [ ] Memory acquisition on EC2
- [ ] Compromised IAM incident response
- [ ] S3 breach investigation
- [ ] Lambda auto-isolation

---

*Phase 3 · AWS Cybersecurity & Digital Forensics Roadmap*