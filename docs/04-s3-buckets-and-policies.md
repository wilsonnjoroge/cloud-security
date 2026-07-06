# 🪣 S3 — Buckets, Policies & Security

> **Phase 1 · Document 4 of 29**  
> **Estimated cost:** ~$0.01 · **Estimated time:** 45–60 minutes  
> **Prerequisites:** `02-iam-users-groups-roles.md`

---

## What Is S3?

S3 (Simple Storage Service) is AWS object storage. Unlike EBS (a disk attached to one instance), S3 is globally accessible, infinitely scalable, and accessed over HTTP.

```
S3 Bucket (container)
  └── Objects (files + metadata)
        ├── Key (the filename/path)
        ├── Value (the actual data)
        ├── Version ID (if versioning is on)
        └── Metadata (content-type, custom tags, etc.)
```

> **Forensics relevance:** S3 is where logs live (CloudTrail, VPC Flow Logs, ALB logs), where evidence is stored, and where data exfiltration happens. S3 misconfigurations are the most common cause of large-scale data breaches.

---

## S3 Key Concepts

| Concept | What it is |
|---------|-----------|
| **Bucket** | A named container for objects — globally unique across all of AWS |
| **Object** | A file stored in a bucket (up to 5TB per object) |
| **Key** | The full path/filename of an object e.g. `logs/2024/01/file.json` |
| **Bucket policy** | JSON policy attached to the bucket controlling access |
| **ACL** | Legacy per-object access control (avoid — use bucket policies instead) |
| **Versioning** | Keeps every version of every object — enables recovery and forensics |
| **Lifecycle policy** | Automatically moves or deletes objects after a set time |
| **Block Public Access** | Account and bucket-level setting that overrides all public access grants |

---

## Step 1 — Create a Private Bucket

**Console path:** `S3 → Create bucket`

| Field | Value |
|-------|-------|
| Bucket name | `lab1-demo-s3-bucket` (must be globally unique) |
| AWS Region | `us-east-1` |
| Block all public access | **Enabled** (leave checked) |
| Bucket versioning | **Enable** |
| Default encryption | **SSE-S3** (Server-side encryption with S3 managed keys) |

Click **Create bucket**.

> **Naming rules:** Lowercase only, 3–63 characters, no underscores, globally unique across all AWS accounts worldwide. Use your name or a random suffix to ensure uniqueness.

![Create S3 Bucket](../screenshots/s3/01-create-s3-bucket-a.png)

![Create S3 Bucket](../screenshots/s3/01-create-s3-bucket-b.png)

![Create S3 Bucket](../screenshots/s3/01-create-s3-bucket-c.png)

![Create S3 Bucket](../screenshots/s3/01-create-s3-bucket-d.png)

![Create S3 Bucket](../screenshots/s3/01-create-s3-bucket-e.png)

![Create S3 Bucket](../screenshots/s3/01-create-s3-bucket-f.png)

---

## Step 2 — Upload Objects

### Via console

```
Click your bucket → Upload → Add files → select any test file → Upload
```

![Upload Object](../screenshots/s3/02-upload-data-to-the-bucket-a.png)

![Upload Object](../screenshots/s3/02-upload-data-to-the-bucket-b.png)

![Upload Object](../screenshots/s3/02-upload-data-to-the-bucket-c.png)

![Upload Object](../screenshots/s3/02-upload-data-to-the-bucket-d.png)

![Upload Object](../screenshots/s3/02-upload-data-to-the-bucket-e.png)


### Via CLI

```bash
# Upload a single file
aws s3 cp myfile.txt s3://lab1-demo-s3-bucket/

# Upload a folder recursively
aws s3 cp ./myfolder s3://lab1-demo-s3-bucket/myfolder/ --recursive

                 or

aws s3 sync ./myfolder s3://lab1-demo-s3-bucket/myfolder/ --recursive

# List bucket contents
aws s3 ls s3://lab1-demo-s3-bucket/

# Download a file
aws s3 cp s3://lab1-demo-s3-bucket/myfile.txt ./downloaded.txt
```

![Upload Object](../screenshots/s3/02-upload-data-to-the-bucket-e.png)

---

## Step 3 — Enable Versioning and Test It

Versioning keeps every version of an object — including deleted ones.

If you enabled versioning at creation, verify it:

```
Bucket → Properties → Bucket versioning → Enabled
```

![Enable Versioning](../screenshots/s3/03-enable-versioning-a.png)

![Enable Versioning](../screenshots/s3/03-enable-versioning-b.png)

![Enable Versioning](../screenshots/s3/03-enable-versioning-c.png)


Now test it:

Via Console

![Enable Versioning](../screenshots/s3/04-test-versioning-in-console-a.png)

![Enable Versioning](../screenshots/s3/04-test-versioning-in-console-b.png)


```bash
# Upload a file
echo "version 1" > test.txt
aws s3 cp test.txt s3://lab1-demo-s3-bucket/test.txt

# Overwrite it
echo "version 2" > test.txt
aws s3 cp test.txt s3://lab1-demo-s3-bucket/test.txt

# List versions
aws s3api list-object-versions --bucket lab1-demo-s3-bucket
```

![Enable Versioning](../screenshots/s3/04-test-versioning-a.png)

![Enable Versioning](../screenshots/s3/04-test-versioning-b.png)


You will see both versions with different `VersionId` values. You can restore v1 at any time.

> **Forensics use:** Versioning is your evidence preservation layer for S3. Even if an attacker deletes objects, the versions remain (unless they also delete the versions — covered in `20-s3-breach-investigation.md`).


---

## Step 4 — Write a Bucket Policy

Bucket policies are JSON documents that control who can access your bucket and what they can do.

**Console path:** `Bucket → Permissions → Bucket policy → Edit`

### Policy 1 — Deny all non-HTTPS access

Always enforce encryption in transit:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyHTTP",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::lab1-demo-s3-bucket",
        "arn:aws:s3:::lab1-demo-s3-bucket/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

> This denies any request that does not use HTTPS. HTTP requests carry data in plaintext — unacceptable for any sensitive data.

![Policy 1](../screenshots/s3/05-create-policy-deny-non-https-a.png)

![Policy 1](../screenshots/s3/05-create-policy-deny-non-https-b.png)


### Policy 2 — Allow a specific IAM user read access

Add a second statement to the same policy:

```json
{
  "Sid": "AllowDevAliceRead",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::YOUR-ACCOUNT-ID:user/dev-willy"
  },
  "Action": [
    "s3:GetObject",
    "s3:ListBucket"
  ],
  "Resource": [
    "arn:aws:s3:::lab1-demo-s3-bucket",
    "arn:aws:s3:::lab1-demo-s3-bucket/*"
  ]
}
```

Replace `YOUR-ACCOUNT-ID` with your 12-digit AWS account number (found in the top-right of the console).

![Policy 1](../screenshots/s3/05-create-policy-to-allow-specific-user-a.png)

---

## Step 5 — Create a Logging Bucket

Every S3 bucket should have server access logging enabled. This records every request made to the bucket.

### Create the log bucket

```
S3 → Create bucket
  Name:                 lab1-logs-s3-bucket
  Region:               us-east-1
  Block all public access: Enabled
  Versioning:           Disabled (logs don't need versioning)
```

![Create a Logging Bucket](../screenshots/s3/06-create-lab1-logs-s3-bucket.png)

### Enable logging on the main bucket

```
lab1-demo-s3-bucket → Properties → Server access logging → Edit
  Logging status: Enable
  Target bucket:  lab1-logs-s3-bucket
  Target prefix:  s3-access-logs/
```

![Enable Logging](../screenshots/s3/07-enable-logging-on-main-bucket-a.png)

![Enable Logging](../screenshots/s3/07-enable-logging-on-main-bucket-b.png)

![Enable Logging](../screenshots/s3/07-enable-logging-on-main-bucket-c.png)

![Enable Logging](../screenshots/s3/07-enable-logging-on-main-bucket-d.png)

> After a few minutes, access your main bucket a few times, then check the log bucket. You will see log entries showing every request — requestor IP, operation, response code, bytes transferred. This is your S3 forensic audit trail.

![Confirm Logging is working](../screenshots/s3/08-check-if-logging-works-a.png)

![Confirm Logging is working](../screenshots/s3/08-check-if-logging-works-b.png)

![Confirm Logging is working](../screenshots/s3/08-check-if-logging-works-c.png)

---

## Step 6 — Lifecycle Policy

Automatically manage object aging:

```
Bucket → Management → Create lifecycle rule
  Rule name:    lab-lifecycle
  Apply to all objects: Yes
```

![Create Lifecycle Policy](../screenshots/s3/09-create-life-cycle-policy-a.png)

![Create Lifecycle Policy](../screenshots/s3/09-create-life-cycle-policy-b.png)

![Create Lifecycle Policy](../screenshots/s3/09-create-life-cycle-policy-c.png)


Configure transitions:

| Days after creation | Action |
|--------------------|--------|
| 30 days | Move to S3 Standard-IA (infrequent access — cheaper) |
| 90 days | Move to S3 Glacier Instant Retrieval (archival — very cheap) |
| 365 days | Expire (delete) |

> For a log archive bucket in a real environment you would set: 90 days Standard → 365 days Glacier → never expire (compliance requirement).

---

## Step 7 — Block Public Access (Account Level)

This is the most important S3 security control. Set it at the account level so no bucket can accidentally become public.

```
S3 → Block Public Access settings for this account → Edit
→ Block all public access: ON → Save
```

![Block Public IP Access](../screenshots/s3/10-block-public-access-a.png)

![Block Public IP Access](../screenshots/s3/10-block-public-access-b.png)

![Block Public IP Access](../screenshots/s3/10-block-public-access-c.png)


> **This is the control that prevents the classic S3 data breach.** A developer creates a bucket and accidentally makes it public. If account-level Block Public Access is on, that mistake is impossible.

---

## Step 8 — Presigned URLs

A presigned URL grants temporary access to a private object without changing any permissions.

```bash
# Generate a presigned URL valid for 1 hour (3600 seconds)
aws s3 presign s3://lab1-demo-s3-bucket/myfile.txt --expires-in 3600
```

Output is a long URL anyone can paste into a browser to download the file — for exactly 1 hour.

![Pre-Signed URL](../screenshots/s3/11-presigned-url-a.png)

![Pre-Signed URL](../screenshots/s3/11-presigned-url-a.png)

> **Security relevance:** Presigned URLs are widely used in applications. They are also a common attack vector — attackers with S3 read permissions can generate presigned URLs to exfiltrate data without triggering bucket policy alerts (the request looks like it comes from an authorized IAM identity). Covered in `25-s3-misconfiguration-attacks.md`.

---

## Step 9 — Cross-Region Replication (Optional)

Replication keeps a live copy of your bucket in another region — used for disaster recovery and evidence preservation.

```
Bucket → Management → Replication rules → Create replication rule
  Source:      lab1-demo-s3-bucket
  Destination: create a bucket in us-west-2
  IAM role:    Create new role
```

> In forensic evidence preservation, you replicate evidence buckets to a separate account entirely — not just a different region. This ensures an attacker who compromises the main account cannot tamper with the evidence copy.

---

## S3 Security Checklist

| Control | Status |
|---------|--------|
| Block Public Access enabled (account level) | ✅ Step 7 |
| Block Public Access enabled (bucket level) | ✅ Step 1 |
| Versioning enabled | ✅ Step 1 |
| Server access logging enabled | ✅ Step 5 |
| HTTPS-only bucket policy | ✅ Step 4 |
| Default encryption enabled | ✅ Step 1 |
| No public ACLs | ✅ via Block Public Access |
| Lifecycle policy configured | ✅ Step 6 |

---

## Common S3 CLI Commands

```bash
# Create a bucket
aws s3 mb s3://my-bucket-name --region us-east-1

# Sync a local folder to S3
aws s3 sync ./local-folder s3://my-bucket-name/remote-folder/

# Remove an object
aws s3 rm s3://my-bucket-name/file.txt

# Remove all objects in a bucket
aws s3 rm s3://my-bucket-name/ --recursive

# Get bucket policy
aws s3api get-bucket-policy --bucket my-bucket-name

# Check block public access settings
aws s3api get-public-access-block --bucket my-bucket-name
```

---

## Forensics Challenge

1. Upload 10 files to your bucket
2. Delete 3 of them
3. Using the S3 console, recover the deleted files using versioning
4. Check the server access logs — can you see the delete operations?
5. Run this CLI command and interpret the output:

```bash
aws s3api list-object-versions \
  --bucket lab1-demo-s3-bucket \
  --query 'DeleteMarkers[*].{Key:Key,Date:LastModified}'
```

> Delete markers are how S3 versioning records deletions. In an investigation, delete markers tell you exactly what was deleted and when — even if the objects appear gone.

---

## Cleanup

```
1. Empty the bucket first (S3 won't delete non-empty buckets)
   aws s3 rm s3://lab1-demo-s3-bucket/ --recursive

2. Delete the bucket
   aws s3 rb s3://lab1-demo-s3-bucket/

3. Repeat for lab1-logs-s3-bucket
```

---

## Phase 1 Progress Tracker

- [x] VPC from scratch
- [x] IAM users, groups, roles, policies
- [x] EC2 instance lifecycle
- [x] S3 buckets and policies
- [ ] Security groups and NACLs
- [ ] CloudTrail setup
- [ ] CloudWatch alarms
- [ ] Billing and cost controls

---

*Phase 1 · AWS Cybersecurity & Digital Forensics Roadmap*
