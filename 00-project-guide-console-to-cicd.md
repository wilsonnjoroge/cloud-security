# 🧭 Project Guide: From AWS Console to CI/CD

> **Purpose:** This is the map for the whole repo. It explains *why* the repo is
> structured the way it is, what each layer of the journey is for, and the
> concrete conventions agreed on for Terraform, Git, and CI/CD: so anyone
> picking this up (including future-me) doesn't have to reconstruct the
> reasoning from scratch.

---

## The Learning Arc: Why Two Tracks Exist

This project is built in two deliberate passes, not one:

1. **AWS Console (Web GUI) first**: every lab (VPC, IAM, EC2, S3, security
   groups, etc.) is built by hand in the console first. This is where the
   *mental model* gets built: what a resource actually is, what breaks if a
   step is skipped, what the console shows you that a `.tf` file abstracts
   away.
2. **Terraform second**: once a concept is understood by hand, it gets
   rebuilt as code. Terraform is the "ship it" layer: reproducible,
   reviewable, destroyable in one command. Skipping straight to Terraform
   without the console pass risks knowing *what* to type without knowing
   *why*: which matters a lot for a security role, where the whole point is
   knowing what you're protecting.

**The guiding principle stated during this work:**
> "You cannot protect what you do not know how it works."

Terraform is the efficient, auditable way to *ship* an environment once you
understand it. It is not a substitute for understanding it.

---

## Section 1: AWS Console (Foundations)

Each numbered doc (`01-vpc-lab-exercise.md`, `02-iam-users-groups-roles.md`,
etc.) is a console-first walkthrough: click-by-click steps, screenshots,
explanations of *why* each setting matters (e.g. why a security group is
stateful and a NACL isn't, why an IGW has to be explicitly attached, not just
created).

This layer is intentionally slow and manual. The goal isn't speed: it's
building an accurate mental model that later makes the Terraform code
self-explanatory instead of magic.

---

## Section 2: Terraform (Local Workflow)

Once a concept is understood via the console, it's rebuilt as a standalone
Terraform project under `terraform-iac/aws-provisions/<doc-name>/`.

### Local commands and what they actually check

| Command | What it needs | What it does |
|---|---|---|
| `terraform init` | Internet (to download providers) | Downloads/caches the providers referenced in `versions.tf` (`aws`, `tls`, `local`, etc.) |
| `terraform validate` | Nothing (no credentials, no internet) | Checks the code is syntactically correct and internally consistent |
| `terraform fmt` | Nothing | Auto-formats `.tf` files to a consistent style |
| `terraform plan` | AWS credentials + internet | Compares your code against **real, current AWS state** and shows what would change |
| `terraform apply` | AWS credentials + internet | Actually creates/changes/destroys real AWS resources |
| `terraform destroy` | AWS credentials + internet | Tears down everything Terraform is tracking in its state file |

### Variables: `variables.tf` vs `terraform.tfvars`

- **`variables.tf`** declares that a variable exists, its type, and
  (optionally) a `default`. It's a schema, not a value.
- **`terraform.tfvars`** supplies the actual value Terraform will use. This
  file is **never committed**: a `terraform.tfvars.example` (with dummy
  placeholder values) is committed instead, so anyone cloning the repo knows
  what to fill in.
- A variable with **no default** (e.g. `my_ip_cidr`) *must* be supplied via
  `.tfvars` (or `-var`, or `TF_VAR_*` env vars) or Terraform will pause and
  ask for it interactively.
- **Precedence, highest to lowest:** `-var` flag → `*.auto.tfvars` →
  `terraform.tfvars` → `TF_VAR_*` env vars → `default` in `variables.tf`.
  A value in `.tfvars` always overrides a `default`, regardless of which
  file was written first.

### Outputs

`output` blocks don't create anything: they surface values (IDs, IPs,
generated file paths) after `apply`, retrievable any time via
`terraform output` or `terraform output -raw <name>` (the `-raw` flag strips
quoting, useful when piping into another command like `curl`).

### Resource wiring

Resources reference each other's **attributes**, not hardcoded values —
e.g. `aws_subnet.public.id` is the real AWS-assigned subnet ID, known only
*after* that resource is created, substituted in automatically by Terraform
wherever it's referenced. This is what makes Terraform resources composable
without copy-pasting IDs by hand.

---

## Section 3: Git (Repo Hygiene and Workflow)

### What gets committed vs ignored

| Commit | Ignore (`.gitignore`) |
|---|---|
| `*.tf` files | `*.tfvars` (real values: IPs, secrets) |
| `terraform.tfvars.example` | `*.tfstate`, `*.tfstate.*` (can contain sensitive resolved values) |
| `.terraform.lock.hcl` (pins provider versions: recommended by HashiCorp) | `.terraform/` (local provider cache, regenerable via `init`) |
| `README.md` per project | `*.pem` (generated SSH private keys) |

A `.gitignore` pattern with **no slash** (e.g. `*.tfvars`) matches at any
depth in the repo automatically: it doesn't need to be repeated per
subfolder.

### Lesson learned: large files in history

A 194MB `.mp4` was committed, then deleted in a later commit: but deletion
in a later commit does **not** remove a file from git history; the blob
stays in every earlier commit that included it, and GitHub hard-rejects any
push containing a file over 100MB anywhere in that push's history.

**Fix used:** since the problem was contained to exactly two commits (one
that added the file, one that deleted it) and neither had reached
`origin` yet, an **interactive rebase** (`git rebase -i <parent-commit>`,
dropping both commits) was sufficient: no need for the heavier
`git filter-repo` tool, which is reserved for cases where a large file is
scattered across many commits or has already been pushed to a shared
remote.

**Working rule going forward:** never commit large binaries (videos,
archives) into a repo meant to stay small and clonable. Screenshots are
fine; multi-hundred-MB media is not.

### Branch and PR workflow (the practice being built)

```
git checkout -b add-<something>
[edit, commit]
git push -u origin add-<something>
→ open a Pull Request into main
→ CI runs automatically (fmt, security scan, plan): see Section 4
→ review the plan output + any security findings
→ merge PR into main
```

Merging a PR only updates the *code* on `main`: it does **not**
automatically provision anything in AWS. `apply` remains a deliberate,
separate action (see Section 4).

---

## Section 4: CI/CD (GitHub Actions)

### Why several workflow files, not one

Each workflow file represents a distinct **security control**, not just a
build step: this is deliberate, and worth stating explicitly given the
security-engineering focus of this project:

| File | Trigger | Purpose |
|---|---|---|
| `terraform-fmt-validate.yml` | `pull_request` | Baseline hygiene: syntax and formatting |
| `terraform-security-scan.yml` | `pull_request` | `tfsec`/`checkov`: catches insecure patterns (open SGs, unencrypted storage, over-permissive IAM) before merge |
| `terraform-plan.yml` | `pull_request` | Shows exactly what would change in AWS, for human review before merge |
| `terraform-apply.yml` | `workflow_dispatch` (manual) | Actually provisions: deliberately **not** triggered by merge, see below |

`.github/workflows/` always sits at the **repo root**: GitHub only
discovers workflows there: but each workflow can target any subfolder
inside the repo via a path filter or `working-directory`.

### Trigger path vs execution scope: these are two different things

- **Trigger path** (`on: pull_request: paths: - 'terraform-iac/**/*.tf'`) —
  one broad pattern, written once, automatically covers every future project
  added under that path. Never needs editing as new projects are added.
- **Execution scope** (`matrix.working-directory: [vpc-lab, iam-lab, ...]`)
 : each Terraform project has its own state, so `init`/`plan` must run
  *inside* that specific folder. **This list does get a new line added**
  each time a new project (e.g. an IAM Terraform project) is built.

### Runners

`runs-on: ubuntu-latest` provisions a **brand-new, temporary VM** for every
single run, and destroys it completely when the job finishes. No leftover
state between runs, nothing to patch or maintain. This is a GitHub-hosted
runner: free to use, no setup required, appropriate for everything in this
project. (Self-hosted runners exist but aren't needed here.)

### Environments (sit / uat / production)

Configured in **GitHub repo Settings → Environments**, not in code. Each
environment can define:
- Required reviewers (a human must approve before a job targeting it runs)
- Which branches are allowed to deploy to it
- Its own separate secrets (e.g. a different AWS role ARN per environment)

A workflow references an environment by name:
```yaml
jobs:
  apply:
    environment: production
```

### Branch protection: making failing checks actually block a merge

By default, a failing `fmt`/`validate`/`security-scan` check on a PR is
**only informational**: GitHub shows a red ❌ on the PR, but nothing stops
anyone from clicking "Merge" anyway. To make failing checks *actually*
block a merge, a **Branch Protection Rule** has to be configured once:

```
Repo → Settings → Branches → Add branch protection rule → main
  ☑ Require status checks to pass before merging
      → select: terraform-fmt-validate, terraform-security-scan, terraform-plan
```

With this on, the **"Merge pull request" button is greyed out** until every
required check is green: enforced by GitHub at the UI level, not just a
warning someone can ignore.

### What actually happens when a check fails

1. The check shows red ❌ on the PR, with full logs available (for `fmt`, a
   diff of what's misformatted; for `validate`, the exact Terraform error).
2. The PR itself is **not** closed or rejected: it just sits open,
   showing failing status, until fixed.
3. If branch protection is on, the merge button stays disabled until it's
   fixed.
4. Fixing it is a normal commit-and-push, on the **same branch**:
   ```bash
   terraform fmt -recursive     # auto-fixes formatting in place
   # fix any validate errors by hand in the flagged .tf file
   git add .
   git commit -m "Fix formatting / fix invalid argument in ec2.tf"
   git push
   ```
5. Pushing a new commit to the same branch **automatically re-triggers**
   every workflow watching that PR: no need to close/reopen anything, and
   if multiple checks were failing, they all re-run together on the new
   commit, not one at a time.

**The practical loop:**

```
Push to feature branch
     │
     ▼
PR checks run: fmt ❌   scan ✅   plan ✅
     │
     ▼
Merge button: greyed out (branch protection requires fmt to pass)
     │
     ▼
terraform fmt -recursive  →  git commit  →  git push
     │
     ▼
Checks re-run automatically: fmt ✅   scan ✅   plan ✅
     │
     ▼
Merge button: now clickable
```

### The apply pattern chosen for this project: and why

**Rejected pattern:** one branch per environment (`develop` → sit,
`staging` → uat, `main` → production), auto-applying on every push to that
branch. This is a legitimate enterprise pattern, but adds branch-management
overhead with no real benefit for a solo learning project.

**Pattern adopted:** a single `main` branch, plus `workflow_dispatch` with
an input dropdown to explicitly choose the target environment at trigger
time:
```yaml
on:
  workflow_dispatch:
    inputs:
      target_environment:
        type: choice
        options: [sit, uat, production]
jobs:
  apply:
    environment: ${{ inputs.target_environment }}
```
This means: go to the **Actions** tab → **Run workflow** → pick an
environment from the dropdown → **Run**. Nothing is inferred from a branch
— the environment is explicit, chosen consciously, every time.

**Why apply is never automatic on merge, in this project specifically:**
a stray merge should never silently spin up billable AWS resources
unattended. Keeping `apply` as a manual, deliberate `workflow_dispatch`
action: even after code is merged to `main`: is the safety margin chosen
for a personal, cost-sensitive lab environment. (In a real company, with a
team and an approvals process already in place, auto-apply-on-merge to a
gated `production` environment is common and reasonable: it's a
deliberate deviation here, not an oversight.)

### Corrected mental model (a live course-correction worth keeping)

An earlier assumption was: *"I'll add the IAM project's path, merge to
main, then run apply."* The correction: **merging and applying are two
separate, deliberate actions**, not one flowing automatically into the
other. Merge only updates what `main` says the infrastructure *should*
look like. Apply is always a conscious, separate step: a click on
"Run workflow," not a side effect of clicking "Merge."

---

## Section 5: Where This Is Headed

- Each numbered doc (01–29) gets its own console walkthrough, then its own
  standalone Terraform project (`terraform-iac/aws-provisions/<name>/`),
  independently apply/destroy-able.
- Docs 27–29 are the **capstone**: a composed, enterprise-style
  environment (VPC, IAM, KMS, Secrets Manager, RDS, ALB, WAF, CloudTrail,
  GuardDuty, Security Hub, Config, Lambda auto-isolation) built from the
  same fictional company (AcmeFintech Ltd) used in the source curriculum.
- **Long-term structure decision:** individual doc projects should expose
  module-friendly variables (e.g. accept a `vpc_id` as input rather than
  always creating their own VPC) so the capstone can eventually **call them
  as Terraform modules** instead of duplicating logic: composition over
  copy-paste, once enough of the individual pieces exist.
- The capstone's own build script contains a few issues worth fixing
  rather than translating literally when it's built in Terraform: a
  hardcoded RDS password (should be `random_password` + Secrets Manager,
  never plaintext in code), a hardcoded/stale AMI ID (should be a
  `data "aws_ami"` lookup, as already done in the VPC lab), and account-wide
  singleton services (GuardDuty, Security Hub, Config) that can only be
  enabled once per account: worth building as an optional, toggleable
  module rather than bundling them into the first apply.

---

*This guide is a living document: update it as conventions evolve, rather
than letting the reasoning behind them live only in chat history.*
