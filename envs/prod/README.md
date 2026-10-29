# Environment: prod

**Status:** 🧩 Terraform complete and validated · ⏳ AWS account not created yet (Control Tower step)

| | |
|---|---|
| AWS account | `acme-prod` (ID in Bitbucket deployment variables / local `.env.prod`) |
| OU (target) | Workloads / Prod |
| Console colour | 🔴 red |
| Hostnames | `api.example.com` (API) · `admin.example.com` (admin web) · `app.example.com` (customer web, later) · `example.com` / `www` (marketing site, once moved here) |
| DNS | records in the management account's `example.com` zone (added by hand) |
| Region | ap-south-1 (Mumbai) · DR backups in ap-south-2 (Hyderabad) |

Live service, **real customer data**. Highly available across 2 AZs, 24/7.

## What is different from dev

| Area | dev | prod |
|---|---|---|
| ECS tasks | public subnet, public IP, AZ a only | private-app subnets, both AZs, **2 NAT gateways** (one per AZ; both Elastic IPs allow-listed by the SMS and payment gateways) |
| Sizes | api 0.5 vCPU × 1 | api 1 vCPU / 2 GB × 2 → **max 8**, floor 4 during the 15:30–17:30 peak; worker 2 → 3; admin web 2 → 4; scheduler × 1 |
| Scaling | fixed `desired_count` | **Application Auto Scaling** on CPU 60 % + scheduled peak floor (`modules/ecs-autoscaling`) |
| Edge | CloudFront only | CloudFront + **WAF** per distribution: rate limit, IP reputation, common, known-bad-inputs and SQLi managed rules in block mode |
| RDS | t4g.micro Single-AZ | **t4g.large Multi-AZ**, gp3 100 GB, **35-day PITR**, deletion protection, final snapshot, changes in the maintenance window |
| DR | – | **cross-Region automated backups to Hyderabad** (RPO ≈ 5 min, RTO ≤ 4 h) with their own KMS key (`modules/db-dr-backups`) |
| Office hours | stopped at night | none: runs 24/7 |
| Retention | 7-day logs | 90-day logs, Container Insights enhanced, uploads deleted after 90 days, 50 images per ECR repo |
| Protection | – | ALB deletion protection, 30-day KMS and secret recovery windows |
| Budget | $100 | $1,000 (≈ $859/month after launch, ≈ $239 before) |
| Marketing site | `example.com` served from dev | `landing_site_enabled = true` at launch (the hostname can be on one distribution only: retire the dev one first) |

Everything else (modules, services, secrets layout, OIDC roles, alarms) is identical to dev.

## First-time bootstrap (once, from a laptop)

The only time `apply` runs outside the pipeline. Afterwards: pipeline only, two approvals.

```bash
cd envs/prod
cat > .env.prod <<'EOF'               # git-ignored
export AWS_PROFILE=acme-prod
export TF_VAR_aws_account_id=<12 digits>
EOF
source .env.prod
aws sso login --sso-session acme
cp terraform.tfvars.example terraform.tfvars   # fill in the Bitbucket UUIDs and e-mail addresses

# 1. State bucket (versioning, encryption, public access blocked) — same commands as preprod
#    with acme-prod-tfstate-$TF_VAR_aws_account_id
terraform init -backend-config="bucket=acme-prod-tfstate-${TF_VAR_aws_account_id}"

# 2. Certificates first: request them, add the CNAMEs from the output in the example.com zone
terraform apply -target=module.cert_cloudfront -target=module.cert_alb -target=module.cert_alb_admin
terraform output acm_validation_records
#    → set certificates_validated = true in terraform.tfvars once the CNAMEs exist

# 3. Secrets (write-only, never in state) and the first full apply.
#    ALB accepts the CloudFront prefix list for now (vpc_origin_sg_ready = false).
export TF_VAR_app_secret_values='{"DATABASE_URL":"...","REDIS_URL":"","CUSTOMER_JWT_SECRET":"...","CUSTOMER_OTP_HMAC_KEY":"...","STRIPE_SECRET_KEY":"sk_live_...","STRIPE_WEBHOOK_SECRET":"whsec_..."}'
export TF_VAR_admin_web_secret_values='{"SESSION_SECRET":"..."}'
terraform apply                      # ~25 min: Multi-AZ RDS + CloudFront VPC origin + DR replication

# 4. CloudFront has now created CloudFront-VPCOrigins-Service-SG in the VPC:
#    set vpc_origin_sg_ready = true → ALB accepts the VPC origin only
terraform apply

# 5. DNS: ALIAS api / admin → the two *_cdn_domain_name outputs
# 6. NAT Elastic IPs (output nat_public_ips) → SMS gateway and payment gateway allow-lists
# 7. Bitbucket: copy the role ARNs from `terraform output` into the repos and deployments
#    (ECR_PUSH_ROLE_ARN, ECS_DEPLOY_ROLE_ARN, PROD_TF_PLAN_ROLE_ARN, TF_APPLY_ROLE_ARN)
# 8. Backend pipeline: push images, run `db-ops` (app user, PostGIS), deploy to prod
# 9. Launch day: landing_site_enabled = true + landing_env_uuids, delete the dev landing
#    distribution, move the example.com ALIAS records
```

## Run (after bootstrap)

Changes to **prod** go through the Bitbucket pipeline only: `plan` on every PR, manual
`Apply (prod)` after `Apply (preprod)`, two approvals, admins only, no deploys 16:00–10:00
(Bitbucket → Deployments → prod). The prod plan step **refuses to save a plan that replaces or
destroys the RDS instance**. From a laptop: `plan` only.

```bash
cd envs/prod && source .env.prod && aws sso login --sso-session acme
cp -n terraform.tfvars.example terraform.tfvars
terraform init -backend-config="bucket=acme-prod-tfstate-${TF_VAR_aws_account_id}"
terraform plan
```

## Disaster recovery (Region loss)

1. In `ap-south-2`: *Automated backups → replicated → Restore to point in time* (needs
   `dr_backup_kms_key_arn`). ≈ 30–60 min for 100 GB.
2. `terraform apply` this root with `aws_region = "ap-south-2"` and a new state key, pointing
   `DATABASE_URL` at the restored instance (secrets version bump).
3. Move the Route 53 ALIAS records. RTO target ≤ 4 h; drill quarterly (roadmap).

## Files

| File | Purpose |
|---|---|
| `versions.tf` | Terraform and AWS provider versions, S3 backend (`prod/terraform.tfstate`) |
| `providers.tf` | AWS provider: ap-south-1 + us-east-1 (CloudFront, WAF) + DR Region, `allowed_account_ids`, default tags |
| `variables.tf` | inputs (account ID has no default) |
| `terraform.tfvars.example` | non-secret values for this environment with placeholder identifiers; copy to `terraform.tfvars` (git-ignored) |
| `main.tf` | module calls |
| `outputs.tf` | values other stacks or people need |
| `.env.prod` | **git-ignored** — local profile and account ID |

More: [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) · [`docs/ROADMAP.md`](../../docs/ROADMAP.md)
