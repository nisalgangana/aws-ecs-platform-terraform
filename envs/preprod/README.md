# Environment: preprod

**Status:** 🧩 Terraform complete and validated · ⏳ AWS account not created yet (Control Tower step)

| | |
|---|---|
| AWS account | `acme-preprod` (ID in Bitbucket deployment variables / local `.env.preprod`) |
| OU (target) | Workloads / NonProd |
| Console colour | 🟠 orange |
| Hostnames | `api-preprod.example.com` (API) · `admin-preprod.example.com` (admin web) · `preprod.example.com` (customer web, later) |
| DNS | records in the management account's `example.com` zone (added by hand) |
| Region | ap-south-1 (Mumbai) |

Production layout at small size: UAT, staff training, k6 load tests, chaos tests and release
rehearsal. **Synthetic data at prod volume**, fixed OTP code, Stripe test keys.

## What is different from dev

| Area | dev | preprod |
|---|---|---|
| ECS tasks | public subnet, public IP, AZ a only | private-app subnets, both AZs, **1 NAT gateway** (Elastic IP allow-listed by the UAT sandboxes) |
| Scaling | fixed `desired_count` | **Application Auto Scaling** on CPU: api 2–4, worker 1–2, admin web 1–2 |
| Office hours | EventBridge Scheduler sets desired count | scheduled scaling actions set min/max to 0/0 at 21:00 and back at 07:00; RDS stops 21:15, starts 06:40 (`modules/env-scheduler`) |
| Edge | CloudFront only | CloudFront + **WAF** per distribution: rate limit, AWS managed rules (count mode first), admin panel **restricted to the office allow-list** |
| RDS | t4g.micro, 1-day backups | t4g.medium, gp3 100 GB, 7-day backups, deletion protection, final snapshot, changes in the maintenance window |
| Retention | 7-day logs, 7-day KMS/secret recovery | 30-day logs, 30-day KMS and secret recovery windows |
| Budget | $100 | $250 (≈ $174/month expected) |

Everything else (modules, services, secrets layout, OIDC roles, alarms) is identical to dev.

## First-time bootstrap (once, from a laptop)

The only time `apply` runs outside the pipeline. Afterwards: pipeline only.

```bash
cd envs/preprod
cat > .env.preprod <<'EOF'            # git-ignored
export AWS_PROFILE=acme-preprod
export TF_VAR_aws_account_id=<12 digits>
EOF
source .env.preprod
aws sso login --sso-session acme
cp terraform.tfvars.example terraform.tfvars   # fill in the Bitbucket UUIDs, office IPs, e-mail addresses

# 1. State bucket (versioning, encryption, public access blocked)
aws s3api create-bucket --bucket acme-preprod-tfstate-$TF_VAR_aws_account_id \
  --region ap-south-1 --create-bucket-configuration LocationConstraint=ap-south-1
aws s3api put-bucket-versioning --bucket acme-preprod-tfstate-$TF_VAR_aws_account_id \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket acme-preprod-tfstate-$TF_VAR_aws_account_id \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket acme-preprod-tfstate-$TF_VAR_aws_account_id \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

terraform init -backend-config="bucket=acme-preprod-tfstate-${TF_VAR_aws_account_id}"

# 2. Certificates first: request them, add the CNAMEs from the output in the example.com zone
terraform apply -target=module.cert_cloudfront -target=module.cert_alb -target=module.cert_alb_admin
terraform output acm_validation_records
#    → set certificates_validated = true in terraform.tfvars once the CNAMEs exist

# 3. Secrets (write-only, never in state) and the first full apply.
#    ALB accepts the CloudFront prefix list for now (vpc_origin_sg_ready = false).
export TF_VAR_app_secret_values='{"DATABASE_URL":"...","REDIS_URL":"","CUSTOMER_JWT_SECRET":"...","CUSTOMER_OTP_HMAC_KEY":"...","STRIPE_SECRET_KEY":"sk_test_...","STRIPE_WEBHOOK_SECRET":"whsec_..."}'
export TF_VAR_admin_web_secret_values='{"SESSION_SECRET":"..."}'
terraform apply                      # ~20 min: RDS + CloudFront VPC origin

# 4. CloudFront has now created CloudFront-VPCOrigins-Service-SG in the VPC:
#    set vpc_origin_sg_ready = true → ALB accepts the VPC origin only
terraform apply

# 5. DNS: ALIAS api-preprod / admin-preprod → the two *_cdn_domain_name outputs
# 6. Bitbucket: copy the role ARNs from `terraform output` into the repos and deployments
#    (ECR_PUSH_ROLE_ARN, ECS_DEPLOY_ROLE_ARN, PREPROD_TF_PLAN_ROLE_ARN, TF_APPLY_ROLE_ARN)
# 7. Backend pipeline: push images, run `db-ops` (app user, PostGIS), deploy to preprod
# 8. After two quiet weeks: waf.managed_rules_mode = "block" (read the WAF logs first)
```

## Run (after bootstrap)

Changes to **preprod** go through the Bitbucket pipeline only: `plan` on every PR, manual
`Apply (preprod)` after merge, restricted to the QA lead and DevOps in Bitbucket → Deployments.
From a laptop: `plan` only.

```bash
cd envs/preprod && source .env.preprod && aws sso login --sso-session acme
cp -n terraform.tfvars.example terraform.tfvars
terraform init -backend-config="bucket=acme-preprod-tfstate-${TF_VAR_aws_account_id}"
terraform plan
```

Test days: raise `services.*` to the prod sizes and `db.multi_az = true` in a PR, apply, run the
k6 suite, revert in a second PR.

## Files

| File | Purpose |
|---|---|
| `versions.tf` | Terraform and AWS provider versions, S3 backend (`preprod/terraform.tfstate`) |
| `providers.tf` | AWS provider: ap-south-1 + us-east-1 (CloudFront, WAF), `allowed_account_ids`, default tags |
| `variables.tf` | inputs (account ID has no default) |
| `terraform.tfvars.example` | non-secret values for this environment with placeholder identifiers; copy to `terraform.tfvars` (git-ignored) |
| `main.tf` | module calls |
| `outputs.tf` | values other stacks or people need |
| `.env.preprod` | **git-ignored** — local profile and account ID |

More: [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) · [`docs/ROADMAP.md`](../../docs/ROADMAP.md)
