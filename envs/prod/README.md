# Environment: prod

**Status:** ⏳ not started (account not created yet)

| | |
|---|---|
| AWS account | `acme-prod` (ID in Bitbucket deployment variables / local `.env.prod`) |
| OU (target) | Workloads / Prod |
| Console colour | 🔴 red |
| Domain | `example.com` |
| Region | ap-south-1 (Mumbai) |

Live service. Highly available across 2 AZs with DR copies to Hyderabad.

## Configuration summary

| Item | Value |
|---|---|
| VPC | 10.20.0.0/16 — 2 AZs |
| Outbound | 2 NAT gateways (one per AZ), 2 Elastic IPs allow-listed by the SMS gateway and the payment gateway |
| Edge | CloudFront + WAF (managed + rate rules) → internal ALB (VPC origin) |
| ECS Fargate (ARM64) | api 1 vCPU / 2 GB: 2 → 4 at 15:30–17:30 → max 8; worker 2 → 3; scheduler × 1 |
| RDS PostgreSQL 16 | db.t4g.large Multi-AZ, gp3 100 GB, 35-day PITR, deletion protection; archive DB t4g.small |
| DR | RDS cross-Region automated backups + AWS Backup copy to ap-south-2 (RPO ≈ 5 min, RTO ≤ 4 h) |
| Day-2 (on trigger) | read replica t4g.medium, ElastiCache t4g.small, r7g.large |
| Deploy | 2 approvals, canary 10% → 100%, freeze 16:00–10:00 |
| Budget alert | $1,000 / month |
| Cost | ≈ $859 / month after launch (≈ $239 before launch) |

## Run

Changes to **prod** go through the Bitbucket pipeline only (manual deployment step).
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
| `.env.prod` | **git-ignored** — local profile and account ID |

More: [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) · [`docs/ROADMAP.md`](../../docs/ROADMAP.md)
