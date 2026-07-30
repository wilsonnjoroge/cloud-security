# lab2 VPC — Terraform

A three-tier VPC: public Web tier fronting two private tiers (App, DB), with
security-group chaining, defense-in-depth NACLs, SSM-only access to the
private tiers (no NAT Gateway, no direct SSH to App/DB), and least-privilege
IAM roles per tier.

## Architecture

```
Internet
   │
   ▼
Internet Gateway (lab2-IG1)
   │
   ▼
┌───────────────────────────── VPC: 10.2.0.0/16 ─────────────────────────────┐
│                                                                            │
│  ┌── Public subnet (us-east-1a) ──┐   ┌── Private subnet (us-east-1b) ──┐  │
│  │  10.2.2.0/24                   │   │  10.2.1.0/24                    │  │
│  │                                │   │                                 │  │
│  │  [Web-Server1] :80             │   │  [App-Server1] :5050            │  │
│  │  Web-Server-SG                 │──▶│  App-Server-SG                  │  │
│  │  (80/443 public, 22 from you)  │   │  (5050 from Web-SG only)        │  │
│  │                                │   │           │                     │  │
│  │  NACL: public-NACL1            │   │           ▼                     │  │
│  └────────────────────────────────┘   │  [Db-Server1] :3306             │  │
│                                        │  Db-Server-SG                   │  │
│                                        │  (3306 from App-SG only)        │  │
│                                        │                                 │  │
│                                        │  VPC Endpoints (ssm/ssmmessages/│  │
│                                        │  ec2messages) -- SSM access,    │  │
│                                        │  no internet route needed       │  │
│                                        │                                 │  │
│                                        │  NACL: private-NACL1            │  │
│                                        │  (VPC-CIDR only, both dirs)      │  │
│                                        └─────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘
```

## Resource map

| Console name | Terraform resource | File |
|---|---|---|
| `lab2-VPC1` | `aws_vpc.this` | `vpc.tf` |
| `lab2-public-subnet1` | `aws_subnet.public` | `vpc.tf` |
| `lab2-private-subnet1` | `aws_subnet.private` | `vpc.tf` |
| `lab2-IG1` | `aws_internet_gateway.this` | `vpc.tf` |
| `lab2-public-rt1` | `aws_route_table.public` | `vpc.tf` |
| `lab2-private-rt1` | `aws_route_table.private` | `vpc.tf` |
| `lab2-public-NACL1` | `aws_network_acl.public` | `nacls.tf` |
| `lab2-private-NACL1` | `aws_network_acl.private` | `nacls.tf` |
| `lab2-Web-Server-SG` | `aws_security_group.web` | `security_groups.tf` |
| `lab2-App-Server-SG` | `aws_security_group.app` | `security_groups.tf` |
| `lab2-Db-Server-SG` | `aws_security_group.db` | `security_groups.tf` |
| `lab2-VPC-Endpoints-Server-SG` | `aws_security_group.vpc_endpoints` | `security_groups.tf` |
| `lab2-web-server-role` | `aws_iam_role.web_server` | `iam.tf` |
| `lab2-app-server-role` | `aws_iam_role.app_server` | `iam.tf` |
| `lab2-db-server-role` | `aws_iam_role.db_server` | `iam.tf` |
| `lab1-s3-readonly-policy` | `aws_iam_policy.lab1_s3_readonly` | `iam.tf` |
| SSM interface endpoints | `aws_vpc_endpoint.ssm/ssmmessages/ec2messages` | `vpc_endpoints.tf` |
| `lab2-Web-Server1` | `aws_instance.web` | `ec2.tf` |
| `lab2-App-Server1` | `aws_instance.app` | `ec2.tf` |
| `lab2-Db-Server1` | `aws_instance.db` | `ec2.tf` |

## Decisions and gaps resolved during design

- **No NAT Gateway.** The private subnet's route table has no `0.0.0.0/0`
  route. App/DB reach AWS APIs (specifically SSM) only through the three
  interface endpoints. There's no S3 gateway endpoint since nothing in this
  stack pulls from S3 from the private tier.
- **Private NACL added for defense-in-depth.** Functionally redundant today
  (no route out means no direct exposure regardless of NACL), but it means a
  future route-table mistake doesn't silently open App/DB to the internet.
  Scoped to VPC CIDR only, both directions.
- **Public NACL outbound includes the ephemeral range (1024-65535)** in
  addition to 80/443, because NACLs are stateless — inbound requests on
  80/443/22 need their return traffic to have an outbound rule too.
- **SSH removed from the AWS-managed CIDR** that was originally on the Web
  SG; only your IP (`my_ip_cidr`) is allowed in.
- **Termination protection removed** (`disable_api_termination = false`) on
  all three instances so `terraform destroy` doesn't fail partway through.
- **`lab1-s3-readonly-policy` is created by Terraform**, scoped to
  `arn:aws:s3:::lab1-*` and `arn:aws:s3:::lab1-*/*`, read-only
  (`GetObject`, `ListBucket`).
- **App/DB roles get `AmazonSSMManagedInstanceCore` only.** Web role also
  gets `CloudWatchAgentServerPolicy` and the custom S3 read-only policy.

## Prerequisites

- Terraform >= 1.5
- AWS credentials for an account/profile you intend to deploy into
- Your public IP: `curl -s https://checkip.amazonaws.com`

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set my_ip_cidr to YOUR.IP/32

terraform init
terraform plan -out="tfplan"
terraform apply "tfplan"
```

Outputs include the web URL, SSH command, and the private IPs of the app/db
tiers (reachable via SSM Session Manager, not directly from your machine):

```bash
terraform output web_url
terraform output ssh_command_web
```

To reach the App or DB instance for testing, use SSM Session Manager (via
the console, or `aws ssm start-session --target <instance-id>`) rather than
SSH — there's no route or SG rule that allows direct SSH to those tiers.

## Operational conventions (credentials & profile safety)

These aren't Terraform-specific, but matter every time you run this config:

- **Check which identity you're about to deploy as, every time**, before
  `terraform apply`:
  ```bash
  aws sts get-caller-identity
  ```
  This confirms the account and IAM identity Terraform will use, based on
  whatever `AWS_PROFILE` is currently exported in that terminal.

- **`provider "aws" {}` in `versions.tf` intentionally has no `profile`
  set.** If it did, that value would override `AWS_PROFILE` silently,
  regardless of what you've exported in your shell — a common source of
  "it deployed to the wrong account" confusion. Leave it unset and control
  the target account entirely through `AWS_PROFILE`.

- **`aws configure --profile X` writes two files**, not one:
  - `~/.aws/credentials` — section named `[X]`
  - `~/.aws/config` — section named `[profile X]` (note the prefix — a
    common hand-editing mistake if you ever touch these files directly
    instead of using `aws configure`)

- **Prefer scoped IAM users/roles over `AdministratorAccess`** for whatever
  identity runs this Terraform. The resources here only need VPC, EC2, IAM
  (role/policy/instance-profile), and VPC-endpoint permissions — not
  account-wide admin.

- **Consider `aws configure sso`** instead of a static access key for the
  profile that runs this, once you're past initial testing — same
  short-lived-credential benefit for Terraform as `aws login` gives your
  interactive CLI use.

## Cleanup

```bash
terraform destroy
```

Termination protection has been left off on all three instances
specifically so this completes in one step.
