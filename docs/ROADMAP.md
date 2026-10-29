# Roadmap

Tick a box when the step is done. Each phase ends with: `fmt` → `validate` → `plan` → commit →
push → Pull Request to `main` → pipeline plan → review → merge (pipeline applies).

**Goal of the whole roadmap:** a developer merges to `main`, the pipeline deploys the API to dev,
and it answers at `https://api-dev.example.com`; the admin panel opens at `https://admin-dev.example.com`.
✅ **Reached** (backend and admin web deploy on merge to `development`; this repo
plans on PRs and applies on merge to `main`).

---

## Phase 0 — AWS accounts and access ✅
- [x] Management account created, root MFA, budget alert
- [x] AWS Organizations created
- [x] Dev account `acme-dev` created from Organizations
- [x] IAM Identity Center (ap-south-1, single-Region), user, `DevOps` group, `AdministratorAccess`
- [x] Access portal `your-org.awsapps.com/start`; CLI profile `acme-dev` via `aws configure sso`
- [ ] Remove the root CLI profile (`aws logout --profile acme-management`, delete from `~/.aws/config`)
- [ ] Account colour set: dev = green

## Phase 1 — Terraform foundation ✅
- [x] `envs/dev/.env.dev` (git-ignored): `AWS_PROFILE`, `TF_VAR_aws_account_id`
- [x] `envs/dev/versions.tf`
- [x] `envs/dev/variables.tf` (account ID with validation, region, environment, project)
- [x] `envs/dev/providers.tf` (region, allowed_account_ids, default_tags)
- [x] `envs/dev/terraform.tfvars.example` (non-secret values only; copied to the git-ignored `terraform.tfvars`)
- [x] `terraform init` → `plan` shows **No changes**
- [x] Guard test: wrong account ID → plan fails
- [x] Commit (incl. `.terraform.lock.hcl`), PR `feature/setup` → `main`

## Phase 2 — Remote state ✅
- [x] Create the state bucket with the AWS CLI (versioning, encryption, block public access)
- [x] `backend "s3"` block (bucket name passed with `-backend-config`, not hard-coded)
- [x] Migrate local state → S3; delete local `terraform.tfstate`
- [x] Commit, PR

## Phase 3 — Network module ✅
- [x] `modules/network`: VPC
- [x] Public + private-app + private-data subnets across 2 AZs
- [x] Internet gateway, route tables, associations
- [x] NAT gateways controlled by `nat_gateway_count` (dev = 0)
- [x] S3 gateway endpoint
- [x] Outputs; module README
- [x] Call from `envs/dev`; apply; check in console

## Phase 4 — Security ✅
- [x] Security groups: ALB, app, database, admin web (no database access)
- [x] KMS key for the environment
- [x] Secrets Manager, values set with write-only arguments (never in state):
  - [x] `acme-dev/app/integrations` — API and worker (6 keys; `ADMIN_SETUP_TOKEN` removed)
  - [x] `acme-dev/admin-web/app` — `SESSION_SECRET` only

## Phase 5 — Database ✅
- [x] `modules/database` (RDS PostgreSQL 18 + PostGIS, t4g.micro in dev, TLS forced, IAM auth)
- [x] Upgrade 16 → 18 (new parameter group, `create_before_destroy`)
- [x] Connect test: migrations run from an ECS one-off task (Phase 6)
- [x] App DB user `acme_app` (owns the schema) in `DATABASE_URL`; the master password rotates on
      its own every 7 days without affecting the app
- [x] `db-ops` one-off psql task (master user from the RDS secret) for admin SQL

## Phase 6 — Containers ✅
- [x] ECR repository (KMS, immutable tags, lifecycle policy)
- [x] Backend pipeline: build ARM64 image → Trivy scan + SBOM → push to ECR (Bitbucket OIDC)
- [x] ECS cluster; task execution and task roles; secrets injected from Secrets Manager
- [x] `api` service behind the ALB (health check `/api/v1/health/ready`)
- [x] `worker` service (OTP and payment jobs, no load balancer)
- [x] Migrations as a one-off task (`migrate up`); since Phase 10 run by the deploy pipeline
- [x] Internal ALB, target group, HTTPS listener

## Phase 7 — DNS and edge ✅
- [x] ACM certificates (us-east-1 for CloudFront, ap-south-1 for ALB); validation CNAMEs in the
      management account's `example.com` zone (no delegated `dev.example.com` zone)
- [x] ALB: HTTPS only; inbound 443 only from the CloudFront VPC origin security group
      (prefix-list rule kept optional for new environments)
- [x] CloudFront distribution with VPC origin → internal ALB (`api-dev.example.com`, HTTPS only)
- [x] ALIAS A/AAAA `api-dev` in the management `example.com` zone; tested over the real name
- [x] Admin web (`admin-dev.example.com`, Next.js BFF on ECS):
  - [x] ECR repo + Bitbucket OIDC push role (`ci-oidc` refactored to a repo map with `moved` blocks)
  - [x] Secret `acme-dev/admin-web/app` (`SESSION_SECRET`) and a security group without DB access
  - [x] ALB: `admin-dev` certificate (SNI), target group, host-header rule
  - [x] ECS service `admin-web` (distroless Node, `server.js` on 8080), on the office-hours schedule
  - [x] Own CloudFront distribution sharing the API's VPC origin; `/_next/static/*` cached
  - [x] ALIAS A/AAAA `admin-dev`; login works end to end (browser and curl)
- [x] Super admin created; `ADMIN_SETUP_TOKEN` removed from the tasks and the secret
- WAF: **not in dev** (cost); preprod and prod get geo allow-list, rate and managed rules

## Phase 8 — Application services
- [ ] Backend team: SendGrid (e-mail) and the SMS gateway support merged; env var names agreed
      (Cognito not needed: the app has its own admin and customer auth)
- [ ] Secrets in `acme-dev/app/integrations` (write-only, version bump); config in `app_environment`
- [ ] SendGrid domain authentication: CNAMEs + DMARC in the `example.com` zone
- [ ] SMS gateway: source IP whitelisting needed? If yes → NAT gateway + Elastic IP (cost decision)
- [ ] S3 bucket for uploads (if the app needs them): file types, max size, how long to keep;
      presigned URLs valid minutes, not days (task role credentials expire)

## Phase 9 — Operations ✅
- [x] EventBridge Scheduler: RDS 07:40 → ECS 08:00 / ECS 20:00 → RDS 20:15, weekdays (local time zone);
      api, worker and admin-web. After-hours test: start RDS first, stop ECS first
- [x] Budget $100 / month (50, 80, 100 % actual; 100 % forecast)
- [x] CloudWatch alarms → SNS topic `acme-dev-alerts` → e-mail (`modules/alarms`): ALB target
      and ELB 5xx, unhealthy targets (api, admin-web), RDS CPU and free storage, ERROR log count
      (api, worker, admin-web). Missing data = OK (dev is off at night). Within the free tier
- [ ] Job queue delay alarm: needs the worker to log `oldest_available_seconds` (backend change)

## Phase 10 — CI/CD ✅
- [x] Bitbucket OIDC identity provider in `acme-dev`
- [x] Admin web repo: Dockerfile (distroless), pipeline (lint/typecheck/test, Trivy, SBOM, ECR push)
- [x] Separate roles per repo: ECR push (build step, repository variable `ECR_PUSH_ROLE_ARN`) and
      ECS deploy (only from the `dev` deployment, `ECS_DEPLOY_ROLE_ARN`);
      OIDC `sub` = `{repo}:{env}:{step}` (verified from a real token)
- [x] Deploy step in both pipelines (`scripts/deploy-ecs.sh`, `amazon/aws-cli:2.37.10`):
      register task definition → run migrations (backend) → update ECS service → wait, fail on
      rollback. Terraform ignores `task_definition`; `*_image_tag` in `terraform.tfvars` is the
      first image only
- [x] Old `AWS_ROLE_ARN` / `IMAGE_NAME` removed from the `dev` deployments
- [x] "Require passing builds" on `development` and `main` in backend and admin web
- [x] Terraform pipeline (this repo): PR → fmt, validate, plan (read-only role);
      merge to `main` → plan + apply the saved plan (admin role, `dev` deployment only).
      Variables `DEV_AWS_ACCOUNT_ID`, `DEV_TF_PLAN_ROLE_ARN` (repository), `TF_APPLY_ROLE_ARN` (dev)
- [x] `main` protected (PR only, passing build); merge strategy: merge commit
- Rule from now on: **dev changes only through the pipeline**; a laptop runs `plan`, not `apply`
- [ ] Small cleanups: delete the commented debug lines in backend `deploy-ecs.sh`; update the
      `aws-cli` image comments

## Phase 11 — Pre-prod and prod root modules ✅ (code) · ⏳ (accounts)
- [x] `modules/waf`: WAFv2 web ACL for CloudFront (allow-list, geo, rate limit, 4 AWS managed
      rule groups, count/block switch, logs with redacted headers)
- [x] `modules/ecs-autoscaling`: target tracking (CPU, memory, requests per target) + scheduled
      min/max actions; `ecs-service` untouched (it already ignores `desired_count`)
- [x] `modules/db-dr-backups`: RDS cross-Region automated backups + KMS key in `ap-south-2`
- [x] `envs/preprod`: private subnets, 1 NAT, auto scaling 2–4, office hours through scheduled
      scaling (0/0 at night) + RDS stop, WAF in count mode, admin panel IP allow-list, $250 budget
- [x] `envs/prod`: 2 NAT, auto scaling 2–8 with a peak floor of 4 (15:30–17:30), WAF in block
      mode, Multi-AZ RDS with 35-day PITR + DR replication, 90-day logs, deletion protection,
      marketing site behind `landing_site_enabled`, $1,000 budget
- [x] Bootstrap toggles for a new account: `certificates_validated`, `vpc_origin_sg_ready`
      (no more hand edits to the security module between applies); runbook in each env README
- [x] Pipeline: three plans in parallel on every PR; manual applies dev → preprod → prod as
      Bitbucket Deployments; prod plan refuses to save a plan that replaces the database;
      `custom: drift-check`
- [x] `terraform validate` passes for dev, preprod and prod
- [ ] Control Tower: create `acme-preprod` and `acme-prod`, Identity Center permission sets,
      Bitbucket deployments (`preprod`, `prod`) with their UUIDs in `terraform.tfvars`
- [ ] Bootstrap preprod (README runbook), then prod; set `PREPROD_*` / `PROD_*` pipeline variables
- [ ] Two quiet weeks in preprod, then `waf.managed_rules_mode = "block"`
- [ ] Prod launch: `landing_site_enabled = true`, retire the dev landing distribution, move DNS
- [ ] First DR drill: point-in-time restore in Hyderabad, measure RTO

---

## Next (in this order)
- [ ] Shared `alerts@` mailbox for alarms and budgets; one root e-mail alias per AWS account
- [ ] Phase 8 when the backend team is ready
- [ ] Phase 11 account steps (above) once Control Tower is in

## Later
- [ ] Control Tower on the existing organization; enroll `acme-dev`; create shared, preprod, prod
- [ ] ECR in `acme-shared`: build once, promote the same image to preprod/prod
      (cross-account pull); admin web `NEXT_PUBLIC_*` build args must become runtime config first
- [ ] Prod deploys: ECS blue/green or canary 10 % → 100 % with alarm-based rollback
      (CodeDeploy or ECS native); today the circuit breaker rolls back a failed deployment
- [ ] AWS Backup plan with Vault Lock for prod (compliance copy next to the RDS replication)
- [ ] Customer web frontend `dev.example.com` (repo `acme-customer-web` not created yet; the
      CloudFront certificate already covers the name)
- [ ] Shared deploy script (Bitbucket pipe or shared repo) instead of a copy per repo
- [ ] Laptop DB access through SSM port forwarding (no bastion, no open port)
- [ ] IAM database authentication instead of a static app DB password (backend change)
- [ ] `scheduler` run mode as an ECS service
- [ ] `ecs-service` module: add AWS default fields (`hostPort`, empty lists) to the container JSON
      so task definition diffs show only real changes
- [ ] Pin base image digests (node, distroless, aws-cli) and keep them current (Renovate)
- [ ] `envs/dev` outputs: `*_task_definition_arn` show Terraform's first revision, not the one the
      pipeline deployed — reword or remove
- [x] Drift detection: `custom: drift-check` runs `plan -detailed-exitcode` on all three roots
      (schedule it nightly in Bitbucket → Pipelines → Schedules)
