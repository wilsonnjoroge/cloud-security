# 🧭 Project Guide: From AWS Console to CI/CD

> **Purpose:** This is the map for the whole repo. It explains *why* the repo is
> structured the way it is, what each layer of the journey is for, and the
> concrete conventions agreed on for Terraform, Git, and CI/CD: so anyone
> picking this u doesn't have to reconstruct the
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

Resources reference each other's **attributes**, not hardcoded values
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


### Branch and PR workflow 

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
| `terraform-fmt-validate.yml` | `pull_request` (always runs: see "The always-trigger pattern" below) | Baseline hygiene: syntax and formatting |
| `terraform-security-scan.yml` | `pull_request` (always runs) | `tfsec`: catches insecure patterns (open SGs, unencrypted storage, over-permissive IAM) before merge |
| `terraform-plan.yml` | `pull_request` (always runs) | Shows exactly what would change in AWS, for human review before merge, via OIDC |
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

### The apply pattern chosen for this project and why

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
 the environment is explicit, chosen consciously, every time.

**Why apply is never automatic on merge, in this project specifically:**
a stray merge should never silently spin up billable AWS resources
unattended. Keeping `apply` as a manual, deliberate `workflow_dispatch`
action: even after code is merged to `main`: is the safety margin chosen
for a personal, cost-sensitive lab environment. (In a real company, with a
team and an approvals process already in place, auto-apply-on-merge to a
gated `production` environment is common and reasonable: it's a
deliberate deviation here, not an oversight.)



### The always-trigger pattern
The workflow always triggers, on every PR: and add a step that checks
internally whether *this specific matrix project* actually has `.tf`
changes:
```bash
BASE_REF="origin/${{ github.event.pull_request.base.ref }}"
DIR="${{ matrix.working-directory }}"
if git diff --name-only "$BASE_REF"...HEAD -- "$DIR" | grep -q '\.tf$'; then
  echo "changed=true" >> "$GITHUB_OUTPUT"
else
  echo "changed=false" >> "$GITHUB_OUTPUT"
fi
```
Every real step (`terraform fmt`, `tfsec`, `terraform plan`, etc.) then
carries `if: steps.tf-changes.outputs.changed == 'true'`. A final
fallback step, guarded by the opposite condition, prints a short message
and exits 0 when there's nothing relevant to check. This guarantees the
job **always** resolves to a real status: success either way: so it's
safe to mark as a required check without risking a permanent block. This
version also checks the diff **per matrix folder**, which is actually more
precise than the old repo-wide path filter: once there are multiple
Terraform projects in the matrix, a PR touching only one of them no longer
triggers a "changed" scan on the others.

`fetch-depth: 0` is required on the checkout step for this to work: the
default shallow checkout doesn't have enough history to diff against the
base branch.



### Sensitive variables : Don't let them leak into plan output

`terraform-plan.yml` posts the full `terraform plan` output as a PR
comment: genuinely useful, but a real IP address (from `my_ip_cidr`)
ended up posted in plain text on a public PR the first time this ran. A
PR comment is not a commit, but it **is** permanently visible on a public
repo: same exposure risk as committing it directly.

**Fix:** mark the variable `sensitive = true` in `variables.tf`:
```hcl
variable "my_ip_cidr" {
  type      = string
  sensitive = true
}
```
Terraform then redacts it (and, conservatively, the *entire resource
block* it's used inside) as `(sensitive value)` in all output: plan,
apply, and anything that captures that output, including a CI-posted PR
comment. This is enforced by Terraform itself, not by the workflow, so it
protects the value no matter where the output ends up.

**Limitation worth knowing:** `sensitive = true` only affects *displayed
output*. The real value is still stored in plaintext inside the state
file: which is exactly why state must never be committed or made public
(see the remote backend section below for where state actually lives now).

**Working rule going forward:** any variable holding something personally
identifying, or credential-like, defaults to `sensitive = true` the moment
it's going to touch a pipeline that posts output anywhere shared.

### OIDC: How CI authenticates to AWS without a stored key

Every credential method used so far (`aws configure`, `AWS_PROFILE`) is a
long-lived key sitting on disk. That's fine on a personal laptop; it's a
real liability inside a public repo's CI pipeline: a static key stored as
a GitHub secret is valid indefinitely until someone notices and rotates
it. **OIDC (OpenID Connect) federation** replaces this: GitHub proves its
identity cryptographically, per run, and AWS hands back credentials that
expire on their own (~1 hour), with nothing persisted anywhere.

**The mechanism:**
1. GitHub Actions can request a signed identity token from its own OIDC
   endpoint on every run: built in, no setup on GitHub's side.
2. AWS is told to trust that endpoint, once, by creating an
   **OIDC Identity Provider** (`IAM → Identity providers`):
   `https://token.actions.githubusercontent.com`, audience
   `sts.amazonaws.com`.
3. An **IAM role** is created with a trust policy scoped to a specific
   repo (and ideally a specific event type or branch: see below), using
   `sts:AssumeRoleWithWebIdentity`.
4. In the workflow: `permissions: id-token: write` lets the job request a
   token; `aws-actions/configure-aws-credentials@v4` with
   `role-to-assume: <role-arn>` performs the actual handshake: request a
   token from GitHub, present it to AWS, receive short-lived credentials.

**Two separate roles, not one: because `plan` and `apply` need genuinely
different permission levels:**

| Role | Trust policy `sub` condition | Permissions |
|---|---|---|
| `github-actions-terraform-plan` | `repo:<owner>/<repo>:pull_request` | Read-only (`Describe*`, `Get*`, `List*`): can never modify anything |
| `github-actions-terraform-apply` | `repo:<owner>/<repo>:ref:refs/heads/main` | Write-scoped to only what the project actually provisions |

Using one role for both would let a `plan`-only trigger (which fires on
*every* PR, including ones from a mistake) actually change AWS: defeating
the reason `plan` exists as a safe preview step.


**Repo access and AWS access are two entirely separate systems.**
Someone with clone/fork access to this repo gets none of its secrets or
IAM roles: secrets never travel via `git clone` (they live in GitHub's
own store, not in any tracked file), and a forked repo's OIDC tokens carry
a different `sub` value (`repo:their-username/their-repo:...`), which the
trust policy simply won't match. GitHub also withholds secrets and
`id-token: write` by default from workflows triggered by PRs originating
from forks, as a second, independent layer of protection. The only way
someone could actually run `apply` against this AWS account is by having
real IAM credentials issued directly in this account: which is a
decision made deliberately, per person, not something that leaks via Git.

**On IAM privilege escalation, if collaborators are ever added:** the
risk isn't "an admin can read another user's existing access key": AWS
never allows that, for anyone, even root; a secret key is shown exactly
once at creation and never again. The real risk is `iam:CreateAccessKey`
(and similar: `iam:CreateLoginProfile`, `iam:AttachUserPolicy`,
`iam:PutUserPolicy`): any identity with that permission can mint a
**new** key for a more-privileged user and authenticate as them. Any
collaborator IAM user should have an explicit `Deny` on these actions,
which overrides any broader `Allow` even if one gets attached later by
mistake.

### Remote state backend : Why local state breaks CI

A GitHub Actions runner is a fresh, temporary VM every run: it has no
access to a laptop's disk. With no backend configured, Terraform defaults
to writing state **locally**, meaning an `apply` run from CI would create
real AWS resources, then lose all record of them the instant the runner is
destroyed at the end of the job. The next run: local or CI: would start
from empty state and either try to recreate everything (hitting
`EntityAlreadyExists` collisions, as happened earlier with IAM roles) or
simply lose track of infrastructure that's still real and still billable.

**Fix: an S3 bucket + native S3 locking, created once, manually, and kept
completely separate from any project's own Terraform code** (never define
the state bucket as a resource *inside* the project that uses it as a
backend: that's a circular dependency: state storage depending on state
storage existing first).

```hcl
# versions.tf
terraform {
  backend "s3" {
    bucket       = "wilsonnjoroge-terraform-state"
    key          = "vpc-lab/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true  # newer, simpler than the older dynamodb_table
    encrypt      = true  # state can contain sensitive values even when
                          # plan *output* is redacted
  }
  # ...
}
```
`bucket` cannot be a variable: the backend block is read before the rest
of the configuration (including `variables.tf`) is parsed, so it must be a
literal string. This is a hard Terraform limitation, not a security
choice: the bucket name itself isn't sensitive (same reasoning as an IAM
role ARN: knowing it grants no access on its own).

**S3 bucket settings:** versioning enabled (recoverability if state is
ever overwritten), default encryption enabled, all four "Block Public
Access" boxes checked.

**Migrating existing local state:** run `terraform init` after adding the
backend block; Terraform detects the change and asks whether to copy
existing state into the new backend: answer yes.

**Confirming it's working:** a `Releasing state lock. This may take a few
moments...` message at the end of a `plan`/`apply` run confirms the S3
lockfile mechanism engaged correctly. `plan` alone never writes a state
object to S3: it only reads. The state object only appears after a real
`apply`.


### `terraform-apply.yml`: the actual design used

**Deliberately simpler than an early draft that considered passing a
saved `-out=tfplan` artifact between a separate `plan` job and a separate
`apply` job.** That pattern adds real value at scale (guarantees the
exact reviewed diff is what gets applied) but requires artifact
upload/download across jobs and a clear rule for "which of several open
PRs' plans applies." For this project, `apply` instead **always
re-plans immediately before applying, against current real state on
`main`**: sidestepping the "which plan" ambiguity entirely, since there
is only ever one, freshly computed, immediately consumed plan per run.

```yaml
on:
  workflow_dispatch:
    inputs:
      project:
        type: choice
        options: [vpc-lab]
      target_environment:
        type: choice
        options: [production]

permissions:
  id-token: write
  contents: read

jobs:
  apply:
    runs-on: ubuntu-latest
    environment: ${{ inputs.target_environment }}   # approval gate lives here
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<account-id>:role/github-actions-terraform-apply
          aws-region: us-east-1
      - uses: hashicorp/setup-terraform@v3
      - run: terraform init -input=false
      - run: terraform plan -no-color -input=false -out=tfplan
        env:
          TF_VAR_my_ip_cidr: ${{ secrets.TF_VAR_MY_IP_CIDR }}
      - run: terraform show -no-color tfplan   # printed to the job log for review
      - run: terraform apply -input=false -auto-approve tfplan
```

- **`workflow_dispatch` only**: never triggered by a merge or a push.
  Nothing in AWS changes unless this is deliberately clicked and run.
- **`environment: production`** is what makes GitHub's **Required
  reviewers** setting (Settings → Environments → production) actually
  pause the job for a manual approval click: the CI equivalent of typing
  `yes` at a local `terraform apply` prompt, just moved to a formal,
  logged gate instead of a terminal prompt.
- **`-input=false` everywhere**: a runner has no terminal to answer an
  interactive prompt. Without this, a missing required variable (like
  `my_ip_cidr`, which has no default) causes the job to **hang** rather
  than fail: burning CI minutes silently until a timeout, instead of
  failing fast with a clear error. Any variable with no default needs a
  matching `secrets.*` entry supplied via `env:` before this can be
  removed as a risk.
- **`TF_VAR_<name>` naming** is how a GitHub secret becomes a Terraform
  variable value automatically: no code change needed beyond passing it
  through the job's `env:` block.

**Secrets scope:** `TF_VAR_MY_IP_CIDR` is a **repository-level** secret,
not an environment-level one: it doesn't need to differ per environment
(an IP is the same regardless of which AWS environment is being deployed
to). Environment-level secrets exist for values that genuinely *should*
differ per environment (e.g. a different AWS role ARN if `dev` and `prod`
were ever separate AWS accounts): not needed here yet.

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
- The capstone's own build script needs the following and will updated as the dec evolve:
    - A hardcoded RDS password (should be `random_password` + Secrets Manager,
  never plaintext in code).
    - A hardcoded/stale AMI ID (should be a  `data "aws_ami"` lookup, as already done in the VPC lab).
    - Account-wide   singleton services (GuardDuty, Security Hub, Config) that can only be enabled once per account: worth building as an optional, toggleable
  module rather than bundling them into the first apply.

---

*Prepared by : Wilson Wanderi*