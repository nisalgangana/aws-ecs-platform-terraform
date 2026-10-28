# Environment: preprod

**Status:** ⏳ not started (account not created yet)

| | |
|---|---|
| AWS account | `acme-preprod` (ID in Bitbucket deployment variables / local `.env.preprod`) |
| OU (target) | Workloads / NonProd |
| Console colour | 🟠 orange |
| Domain | `preprod.example.com` |
| Region | ap-south-1 (Mumbai) |

Production layout at small size: UAT, staff training, k6 load tests, chaos tests and release rehearsal. Synthetic data at prod volume.

## Configuration summary

| Item | Value |
|---|---|
| VPC | 10.30.0.0/16 — 2 AZs, production layout |
| Outbound | 1 NAT gateway + Elastic IP (allow-listed by UAT providers) |
| Edge | CloudFront + WAF (prod rule set + allow-list) → internal ALB (VPC origin) |
| ECS Fargate (ARM64) | api 0.5 vCPU × 2 (one per AZ), worker × 1, scheduler × 1; prod sizes on test days; k6 runner on demand |
| RDS PostgreSQL 16 | db.t4g.medium, Single-AZ (Multi-AZ switched on for rehearsals), gp3 100 GB, 7-day backups |
| Schedule | weekdays 07:00–21:00 |
| Deploy | QA approval in the pipeline |
| Budget alert | $250 / month |
| Cost | ≈ $174 / month |

## Run

Changes to **preprod** go through the Bitbucket pipeline only (manual deployment step).
No `apply` from laptops.

## Files

| File | Purpose |
|---|---|
| `versions.tf` | Terraform and AWS provider versions |
| `providers.tf` | AWS provider: region, `allowed_account_ids`, default tags |
| `variables.tf` | inputs (account ID has no default) |
| `terraform.tfvars` | non-secret values for this environment |
| `main.tf` | module calls |
| `outputs.tf` | values other stacks or people need |
| `.env.preprod` | **git-ignored** — local profile and account ID |

More: [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) · [`docs/ROADMAP.md`](../../docs/ROADMAP.md)
