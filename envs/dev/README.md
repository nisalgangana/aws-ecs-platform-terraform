# Environment: dev

**Status:** ✅ API and admin web live, CI/CD and alarms in place · 🚧 Phase 8 (application services)

| | |
|---|---|
| AWS account | `acme-dev` (ID in Bitbucket deployment variables / local `.env.dev`) |
| OU (target) | Workloads / NonProd |
| Console colour | 🟢 green |
| Hostnames | `api-dev.example.com` (API) · `admin-dev.example.com` (admin web) · `dev.example.com` (customer web, later) |
| DNS | records in the management account's `example.com` zone (added by hand) |
| Region | ap-south-1 (Mumbai) |

First cloud environment for every merge to `main`. **Synthetic data only** — the API is public
and the OTP code is fixed (`123456`).

## First-time setup

```bash
cd envs/dev
source .env.dev
aws sso login --sso-session acme
cp -n terraform.tfvars.example terraform.tfvars   # then fill in the real Bitbucket UUIDs and addresses
terraform init -backend-config="bucket=acme-dev-tfstate-${TF_VAR_aws_account_id}"
terraform plan
```

## What is deployed

See [`main.tf`](main.tf). In short: VPC (no NAT in dev), security groups + KMS + Secrets Manager,
RDS PostgreSQL, ECR repositories, ECS Fargate services (`api`, `worker`, `scheduler`, `admin-web`),
internal ALB, CloudFront distributions with a VPC origin, ACM certificates, Bitbucket OIDC roles,
EventBridge office-hours scheduler, budget, CloudWatch alarms, an S3 uploads bucket and the
static marketing site with its contact-form Lambda.

## Files

| File | Purpose |
|---|---|
| `versions.tf` | Terraform and AWS provider versions, S3 backend |
| `providers.tf` | AWS provider: region, `allowed_account_ids`, default tags |
| `variables.tf` | inputs (account ID has no default) |
| `terraform.tfvars.example` | non-secret values for this environment with placeholder identifiers; copy to `terraform.tfvars` (git-ignored) |
| `main.tf` | module calls |
| `outputs.tf` | values other stacks or people need |
| `.env.dev` | **git-ignored** — local profile and account ID |

More: [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) · [`docs/ROADMAP.md`](../../docs/ROADMAP.md)
