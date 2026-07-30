# 🧠 Memory Acquisition on EC2 — Live Memory Forensics

> **Phase 3 · Document 18 of 29**  
> **Estimated cost:** ~$1–2 · **Estimated time:** 90 minutes  
> **Prerequisites:** `16-ebs-snapshot-forensics.md`

---

## Why Memory Forensics in the Cloud?

Disk forensics (EBS snapshots) tells you what was stored. Memory forensics tells you what was running — active processes, network connections, encryption keys in use, malware that lives only in RAM and leaves no disk trace.

```
DISK FORENSICS (EBS):          MEMORY FORENSICS (RAM):
Persistent artifacts            Volatile artifacts
Files, logs, config            Running processes
Deleted file recovery          Active network connections
Registry/cron jobs             Decrypted data in memory
Malware dropped to disk        Fileless malware
```

> **Critical:** Memory is volatile — when the instance stops, RAM contents are gone permanently. Memory acquisition must happen on a **running** instance, which conflicts with the principle of not touching a live compromised system. The compromise is: acquire memory first, then stop for disk acquisition.

---

## Memory Acquisition Order of Operations

```
Incident detected
      │
      ▼
DO NOT stop the instance yet
      │
      ▼
Step 1: Capture network connections (netstat/ss) — fastest
Step 2: Capture running process list (ps, lsof)
Step 3: Acquire full memory dump (LiME)
Step 4: THEN stop the instance
Step 5: Take EBS snapshot (document 16)
Step 6: Analyze both memory and disk
```

---

## Step 1 — Quick Triage Without LiME

Before acquiring full memory, grab volatile data quickly via SSH or Session Manager. This takes seconds and captures the most time-sensitive evidence.

SSH into the running compromised instance:

```bash
# ===== NETWORK CONNECTIONS =====
# Active connections (attacker's C2 channel may be here)
ss -tnap > /tmp/forensic-netstat.txt
netstat -tnap >> /tmp/forensic-netstat.txt 2>/dev/null

# DNS resolution cache
cat /etc/resolv.conf >> /tmp/forensic-netstat.txt
systemd-resolve --statistics >> /tmp/forensic-netstat.txt 2>/dev/null

# ===== PROCESSES =====
# Full process tree with parent-child relationships
ps auxef > /tmp/forensic-processes.txt
pstree -p >> /tmp/forensic-processes.txt

# Processes with open network connections
lsof -i -n -P > /tmp/forensic-lsof-network.txt

# All open files (malware often has deleted files still open)
lsof -n > /tmp/forensic-lsof-all.txt

# ===== USERS AND SESSIONS =====
w > /tmp/forensic-sessions.txt
who >> /tmp/forensic-sessions.txt
last >> /tmp/forensic-sessions.txt

# ===== SCHEDULED TASKS =====
crontab -l > /tmp/forensic-cron.txt 2>/dev/null
cat /etc/crontab >> /tmp/forensic-cron.txt
ls -la /etc/cron.* >> /tmp/forensic-cron.txt

# ===== LOADED KERNEL MODULES =====
lsmod > /tmp/forensic-modules.txt

# ===== ENVIRONMENT VARIABLES (may contain secrets) =====
env > /tmp/forensic-env.txt

# Copy triage data to your S3 evidence bucket
aws s3 cp /tmp/forensic-*.txt s3://lab-private-yourname-2024/forensics/IR-2024-001/triage/
```

---

## Step 2 — Install LiME (Linux Memory Extractor)

LiME is a kernel module that captures a full memory image from a running Linux system. It is the standard tool for Linux memory acquisition.

On the forensic workstation (NOT the compromised instance):

```bash
# Install build dependencies
sudo apt install -y build-essential linux-headers-$(uname -r) git

# Clone LiME
git clone https://github.com/504ensicsLabs/LiME.git
cd LiME/src

# Compile LiME — must match kernel version of the TARGET instance
make
ls -la lime-*.ko
```

> **Important:** The LiME kernel module must be compiled against the same kernel version as the instance you want to acquire memory from. Check the target instance kernel: `uname -r`

---

## Step 3 — Transfer LiME to the Compromised Instance

```bash
# From your forensic workstation
scp -i lab-key.pem lime-$(uname -r).ko ec2-user@<compromised-instance-ip>:/tmp/

# Alternatively, upload to S3 and download from the instance
aws s3 cp lime-$(uname -r).ko s3://lab-private-yourname-2024/tools/
```

On the compromised instance:

```bash
sudo aws s3 cp s3://lab-private-yourname-2024/tools/lime-$(uname -r).ko /tmp/
```

---

## Step 4 — Acquire Memory with LiME

On the compromised instance:

```bash
# Load LiME and stream memory over TCP to forensic workstation
# (avoids writing to disk on the compromised instance)
sudo insmod /tmp/lime-$(uname -r).ko \
  "path=tcp:4444 format=lime timeout=0"
```

On the forensic workstation — receive the memory stream:

```bash
# Receive and save the memory dump
nc <compromised-instance-private-ip> 4444 > /home/ubuntu/memory-IR-2024-001.lime

# Hash the memory image immediately
sha256sum /home/ubuntu/memory-IR-2024-001.lime > /home/ubuntu/memory-hash.txt
```

> **TCP streaming** means memory is transferred directly from RAM to the forensic workstation without ever touching the compromised instance's disk — preserving evidence integrity.

For local dump (if you prefer to write to disk first):

```bash
sudo insmod /tmp/lime-$(uname -r).ko \
  "path=/tmp/memory.lime format=lime"

# Then copy to S3
aws s3 cp /tmp/memory.lime s3://lab-private-yourname-2024/forensics/IR-2024-001/
```

---

## Step 5 — Set Up Volatility 3 for Analysis

Volatility is the standard memory analysis framework.

On the forensic workstation:

```bash
# Install Volatility 3
pip3 install volatility3

# Or from source
git clone https://github.com/volatilityfoundation/volatility3.git
cd volatility3
pip3 install -r requirements.txt

# Verify installation
python3 vol.py --help
```

---

## Step 6 — Memory Analysis with Volatility 3

```bash
# Set the memory image path for convenience
MEMDUMP="/home/ubuntu/memory-IR-2024-001.lime"

# ===== SYSTEM INFORMATION =====
python3 vol.py -f $MEMDUMP banners.Banners
# Shows: kernel version, hostname, distribution

# ===== PROCESS ANALYSIS =====

# List all processes (like ps)
python3 vol.py -f $MEMDUMP linux.pslist.PsList

# Process tree (parent-child relationships — spot unusual parents)
python3 vol.py -f $MEMDUMP linux.pstree.PsTree

# Processes with suspicious parent-child relationships
# e.g., httpd spawning /bin/bash → web shell indicator
python3 vol.py -f $MEMDUMP linux.psaux.PsAux

# Find hidden processes (rootkit detection)
# Compares process list from multiple sources — discrepancies = hiding
python3 vol.py -f $MEMDUMP linux.check_idt.Check_idt

# ===== NETWORK ANALYSIS =====

# Active network connections in memory
python3 vol.py -f $MEMDUMP linux.netstat.Netstat

# Socket information
python3 vol.py -f $MEMDUMP linux.sockstat.Sockstat

# ===== FILE ANALYSIS =====

# Files open by each process
python3 vol.py -f $MEMDUMP linux.lsof.Lsof

# Recover file contents from memory (files deleted from disk but still open)
python3 vol.py -f $MEMDUMP linux.recover_filesystem

# ===== MALWARE DETECTION =====

# Find processes with suspicious memory regions (injected code)
python3 vol.py -f $MEMDUMP linux.malfind.Malfind

# Check for rootkit hooks in system call table
python3 vol.py -f $MEMDUMP linux.check_syscall.Check_syscall

# Loaded kernel modules (compare against known good)
python3 vol.py -f $MEMDUMP linux.lsmod.Lsmod

# ===== CREDENTIALS IN MEMORY =====

# Find bash history in memory (even if cleared on disk)
python3 vol.py -f $MEMDUMP linux.bash.Bash

# Environment variables (may contain API keys, passwords)
python3 vol.py -f $MEMDUMP linux.envars.Envars

# SSH private keys in memory
python3 vol.py -f $MEMDUMP linux.pslist.PsList | grep ssh
```

---

## Step 7 — String Analysis

Strings extracts human-readable text from the memory dump — useful for finding hardcoded credentials, URLs, and C2 addresses:

```bash
# Extract all strings (min 8 chars)
strings -n 8 $MEMDUMP > /home/ubuntu/strings-output.txt

# Search for IP addresses
grep -E "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" /home/ubuntu/strings-output.txt | \
  sort -u | grep -v "^10\." | grep -v "^172\." | grep -v "^192\.168\."

# Search for URLs
grep -E "https?://[^\s]+" /home/ubuntu/strings-output.txt | sort -u

# Search for AWS credentials in memory (credential exposure check)
grep -E "AKIA[A-Z0-9]{16}" /home/ubuntu/strings-output.txt
grep -E "aws_secret_access_key\s*=\s*[A-Za-z0-9/+]{40}" /home/ubuntu/strings-output.txt

# Search for common C2 patterns
grep -E "(beacon|c2|payload|implant|shell)" /home/ubuntu/strings-output.txt -i | head -50

# Search for base64 encoded data
grep -E "[A-Za-z0-9+/]{50,}={0,2}" /home/ubuntu/strings-output.txt | head -20 | \
  while read line; do echo "$line" | base64 -d 2>/dev/null; echo; done
```

---

## Step 8 — Process Memory Dump (Targeted Acquisition)

Instead of acquiring full memory, target a specific suspicious process:

```bash
# On the compromised instance — dump a specific process memory
PID=$(pgrep suspicious-process-name)

# Create a core dump of the process
sudo gcore -o /tmp/process-dump $PID

# Or use /proc for raw memory
sudo cat /proc/$PID/mem > /tmp/process-mem.bin 2>/dev/null

# Copy to S3
aws s3 cp /tmp/process-dump.$PID s3://lab-private-yourname-2024/forensics/
```

---

## Step 9 — Fileless Malware Detection

Fileless malware exists only in memory — no file on disk. Common indicators:

```bash
# Find processes where the executable has been deleted from disk
# (process running but file no longer exists)
python3 vol.py -f $MEMDUMP linux.pslist.PsList | grep "(deleted)"

# OR on live system:
ls -la /proc/*/exe 2>/dev/null | grep "(deleted)"

# Find processes injected into legitimate processes
# (e.g., malicious code injected into /usr/bin/httpd)
python3 vol.py -f $MEMDUMP linux.malfind.Malfind

# Check for LD_PRELOAD hijacking (malicious library injected at load time)
python3 vol.py -f $MEMDUMP linux.envars.Envars | grep LD_PRELOAD

# Detect process hollowing (legitimate process name, malicious code)
# Compare memory maps against on-disk binaries
python3 vol.py -f $MEMDUMP linux.proc_maps.Maps
```

---

## Memory Acquisition Checklist

```
Before acquiring memory:
  [ ] Confirm instance is still running (memory exists)
  [ ] Document instance state: uptime, running processes (quick triage)
  [ ] Ensure forensic workstation is isolated from the compromised network
  [ ] LiME module compiled for correct kernel version
  [ ] Evidence S3 bucket ready with versioning enabled

During acquisition:
  [ ] Use TCP streaming where possible (no disk write on suspect machine)
  [ ] Hash the memory image immediately after capture
  [ ] Record: acquisition time, instance ID, analyst name

After acquisition:
  [ ] Verify hash
  [ ] Stop the instance
  [ ] Take EBS snapshot (document 16)
  [ ] Begin analysis on forensic workstation only
  [ ] Never run tools on the compromised instance itself
```

---

## Cleanup

```bash
# On the compromised instance — remove LiME module
sudo rmmod lime

# Terminate compromised instance
EC2 → Instances → lab-compromised → Terminate

# Keep forensic workstation while analysis is ongoing
# Terminate when investigation is complete
```

---

## Phase 3 Progress Tracker

- [x] EBS snapshot forensics
- [x] CloudTrail log analysis
- [x] Memory acquisition on EC2
- [ ] Compromised IAM incident response
- [ ] S3 breach investigation
- [ ] Lambda auto-isolation

---

*Phase 3 · AWS Cybersecurity & Digital Forensics Roadmap*
