# Pre-prod: the prod layout at small size. Same modules as dev and prod; only
# terraform.tfvars differs. Differences from dev that live in this file:
#   - ECS tasks in the private-app subnets behind a NAT gateway (no public IPs)
#   - WAF in front of both CloudFront distributions
#   - Application Auto Scaling per service (office hours = scale to 0/0 at night)
#   - longer retention, deletion protection, 30-day KMS/secret recovery windows

locals {
  name_prefix = "${var.project}-${var.environment}"

  app_secret_keys = [
    "DATABASE_URL", "REDIS_URL",
    "CUSTOMER_JWT_SECRET", "CUSTOMER_OTP_HMAC_KEY",
    "STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET",
  ]

  # api, worker and scheduler share the same config
  app_runtime_environment = merge(var.app_environment, {
    S3_UPLOADS_BUCKET = module.uploads.bucket_name # contains the account ID, so not in tfvars
    AWS_REGION        = var.aws_region
  })

  # Office hours for autoscaled services: 0/0 outside the crons, the normal range inside.
  # Done with scheduled scaling actions, because a plain desired_count = 0 would be
  # undone by the scaler's min_capacity.
  office_hours_actions = {
    for name, svc in {
      api       = var.services.api
      worker    = var.services.worker
      admin_web = var.services.admin_web
      } : name => var.office_hours == null ? {} : {
      office-open = {
        schedule     = var.office_hours.services_start_cron
        min_capacity = svc.min_count
        max_capacity = svc.max_count
      }
      office-close = {
        schedule     = var.office_hours.services_stop_cron
        min_capacity = 0
        max_capacity = 0
      }
    }
  }
}

# Reads the identity Terraform is running as.
# Using any data source forces the AWS provider to authenticate on every plan,
# so allowed_account_ids is always checked.
data "aws_caller_identity" "current" {}

# Created by AWS together with the first CloudFront VPC origin in this VPC.
# Bootstrap: apply with vpc_origin_sg_ready = false first (ALB accepts the CloudFront
# prefix list), then set it to true once the VPC origin exists.
data "aws_security_group" "cloudfront_vpc_origin" {
  count = var.vpc_origin_sg_ready ? 1 : 0

  vpc_id = module.network.vpc_id

  filter {
    name   = "group-name"
    values = ["CloudFront-VPCOrigins-Service-SG"]
  }
}

# ---------------------------------------------------------------
# Network and security
# ---------------------------------------------------------------
module "network" {
  source = "../../modules/network"

  name_prefix       = local.name_prefix
  vpc_cidr          = var.vpc_cidr
  nat_gateway_count = var.nat_gateway_count
}

module "security" {
  source = "../../modules/security"

  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id

  kms_deletion_window_days    = 30
  secret_recovery_window_days = 30

  manage_app_secret_value       = true
  app_secret_values             = var.app_secret_values
  app_secret_version            = var.app_secret_version
  manage_admin_web_secret_value = true
  admin_web_secret_values       = var.admin_web_secret_values
  admin_web_secret_version      = var.admin_web_secret_version

  # ALB inbound: CloudFront prefix list during bootstrap, the VPC origin SG only afterwards
  cloudfront_vpc_origin_sg_id  = one(data.aws_security_group.cloudfront_vpc_origin[*].id)
  allow_cloudfront_prefix_list = !var.vpc_origin_sg_ready
}

# ---------------------------------------------------------------
# Database
# ---------------------------------------------------------------
module "database" {
  source = "../../modules/database"

  name_prefix = local.name_prefix
  subnet_ids  = module.network.private_data_subnet_ids
  db_sg_id    = module.security.db_sg_id
  kms_key_arn = module.security.kms_key_arn

  instance_class        = var.db.instance_class
  allocated_storage     = var.db.allocated_storage
  multi_az              = var.db.multi_az
  backup_retention_days = var.db.backup_retention_days
  deletion_protection   = var.db.deletion_protection
  skip_final_snapshot   = var.db.skip_final_snapshot
  backup_window         = var.db.backup_window
  maintenance_window    = var.db.maintenance_window
  apply_immediately     = false # changes wait for the maintenance window
}

# One-off psql tasks as the master user (create the app user, grants, extensions)
module "db_ops" {
  source = "../../modules/db-ops-task"

  name_prefix          = local.name_prefix
  kms_key_arn          = module.security.kms_key_arn
  db_address           = module.database.db_address
  db_name              = "acme"
  db_master_secret_arn = module.database.db_master_secret_arn
  app_secret_arn       = module.security.app_secret_arn
  log_retention_days   = var.log_retention_days
}

# ---------------------------------------------------------------
# Container registries (one per run mode, same as dev)
# ---------------------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  name        = "${local.name_prefix}-app"
  kms_key_arn = module.security.kms_key_arn
}

module "ecr_worker" {
  source = "../../modules/ecr"

  name        = "${local.name_prefix}-worker"
  kms_key_arn = module.security.kms_key_arn
}

module "ecr_scheduler" {
  source = "../../modules/ecr"

  name        = "${local.name_prefix}-scheduler"
  kms_key_arn = module.security.kms_key_arn
}

module "ecr_admin" {
  source = "../../modules/ecr"

  name        = "${local.name_prefix}-admin-web"
  kms_key_arn = module.security.kms_key_arn
}

# ---------------------------------------------------------------
# ECS cluster and services: private subnets, both AZs, no public IPs
# ---------------------------------------------------------------
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  name_prefix        = local.name_prefix
  container_insights = var.container_insights
}

module "app_service" {
  source = "../../modules/ecs-service"

  name_prefix        = local.name_prefix
  service_name       = "app"
  kms_key_arn        = module.security.kms_key_arn
  secret_arns        = [module.security.app_secret_arn]
  log_retention_days = var.log_retention_days

  cluster_arn        = module.ecs_cluster.cluster_arn
  image              = "${module.ecr.repository_url}:${var.app_image_tag}"
  command            = ["api"]
  cpu                = var.services.api.cpu
  memory             = var.services.api.memory
  desired_count      = var.services.api.min_count
  subnet_ids         = module.network.private_app_subnet_ids
  security_group_ids = [module.security.app_sg_id]
  assign_public_ip   = false
  target_group_arn   = module.alb.target_group_arn

  environment    = local.app_runtime_environment
  app_secret_arn = module.security.app_secret_arn
  secret_keys    = local.app_secret_keys
}

module "app_scaling" {
  source = "../../modules/ecs-autoscaling"

  cluster_name       = module.ecs_cluster.cluster_name
  service_name       = module.app_service.service_name
  min_capacity       = var.services.api.min_count
  max_capacity       = var.services.api.max_count
  cpu_target_percent = var.services.api.cpu_target_percent
  timezone           = var.timezone
  scheduled_actions  = merge(local.office_hours_actions["api"], var.api_scheduled_scaling)
}

# Background jobs: OTP SMS, payment events, River job queue. No HTTP traffic, so no ALB.
module "worker_service" {
  source = "../../modules/ecs-service"

  name_prefix        = local.name_prefix
  service_name       = "worker"
  kms_key_arn        = module.security.kms_key_arn
  secret_arns        = [module.security.app_secret_arn]
  log_retention_days = var.log_retention_days

  cluster_arn        = module.ecs_cluster.cluster_arn
  image              = "${module.ecr_worker.repository_url}:${var.app_image_tag}"
  command            = ["worker"]
  cpu                = var.services.worker.cpu
  memory             = var.services.worker.memory
  desired_count      = var.services.worker.min_count
  subnet_ids         = module.network.private_app_subnet_ids
  security_group_ids = [module.security.app_sg_id]
  assign_public_ip   = false

  environment    = local.app_runtime_environment
  app_secret_arn = module.security.app_secret_arn
  secret_keys    = local.app_secret_keys
}

module "worker_scaling" {
  source = "../../modules/ecs-autoscaling"

  cluster_name       = module.ecs_cluster.cluster_name
  service_name       = module.worker_service.service_name
  min_capacity       = var.services.worker.min_count
  max_capacity       = var.services.worker.max_count
  cpu_target_percent = var.services.worker.cpu_target_percent
  timezone           = var.timezone
  scheduled_actions  = local.office_hours_actions["worker"]
}

# Periodic jobs: exactly one task (Postgres advisory lock). Not autoscaled.
module "scheduler_service" {
  source = "../../modules/ecs-service"

  name_prefix        = local.name_prefix
  service_name       = "scheduler"
  kms_key_arn        = module.security.kms_key_arn
  secret_arns        = [module.security.app_secret_arn]
  log_retention_days = var.log_retention_days

  cluster_arn        = module.ecs_cluster.cluster_arn
  image              = "${module.ecr_scheduler.repository_url}:${var.app_image_tag}"
  command            = ["scheduler"]
  cpu                = var.services.scheduler.cpu
  memory             = var.services.scheduler.memory
  desired_count      = 1
  subnet_ids         = module.network.private_app_subnet_ids
  security_group_ids = [module.security.app_sg_id]
  assign_public_ip   = false

  environment    = local.app_runtime_environment
  app_secret_arn = module.security.app_secret_arn
  secret_keys    = local.app_secret_keys
}

# Admin panel (Next.js BFF). Calls the API through its public hostname, never the DB.
module "admin_web_service" {
  source = "../../modules/ecs-service"

  name_prefix        = local.name_prefix
  service_name       = "admin-web"
  kms_key_arn        = module.security.kms_key_arn
  secret_arns        = [module.security.admin_web_secret_arn]
  log_retention_days = var.log_retention_days

  cluster_arn        = module.ecs_cluster.cluster_arn
  image              = "${module.ecr_admin.repository_url}:${var.admin_web_image_tag}"
  command            = ["server.js"] # distroless: the image's ENTRYPOINT is node
  cpu                = var.services.admin_web.cpu
  memory             = var.services.admin_web.memory
  desired_count      = var.services.admin_web.min_count
  container_port     = 8080
  subnet_ids         = module.network.private_app_subnet_ids
  security_group_ids = [module.security.admin_web_sg_id]
  assign_public_ip   = false
  target_group_arn   = module.alb.host_target_group_arns["admin-web"]

  environment    = var.admin_web_environment
  app_secret_arn = module.security.admin_web_secret_arn
  secret_keys    = ["SESSION_SECRET"]
}

module "admin_web_scaling" {
  source = "../../modules/ecs-autoscaling"

  cluster_name       = module.ecs_cluster.cluster_name
  service_name       = module.admin_web_service.service_name
  min_capacity       = var.services.admin_web.min_count
  max_capacity       = var.services.admin_web.max_count
  cpu_target_percent = var.services.admin_web.cpu_target_percent
  timezone           = var.timezone
  scheduled_actions  = local.office_hours_actions["admin_web"]
}

# Presigned uploads (photos, documents)
module "uploads" {
  source = "../../modules/s3-uploads"

  name_prefix     = local.name_prefix
  kms_key_arn     = module.security.kms_key_arn
  expiration_days = var.uploads_expiration_days

  cors_allowed_origins = [
    "https://${var.hostnames["admin"]}",
    "https://${var.hostnames["frontend"]}",
  ]

  access_role_names = {
    api    = module.app_service.task_role_name
    worker = module.worker_service.task_role_name
  }
}

# ---------------------------------------------------------------
# Load balancer (internal) and certificates
# ---------------------------------------------------------------
module "alb" {
  source = "../../modules/alb"

  name_prefix         = local.name_prefix
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.private_app_subnet_ids
  alb_sg_id           = module.security.alb_sg_id
  health_check_path   = "/api/v1/health/ready"
  certificate_arn     = module.cert_alb.certificate_arn
  deletion_protection = false # pre-prod is rebuilt for chaos tests

  additional_certificates = {
    admin-web = module.cert_alb_admin.certificate_arn
  }

  host_routes = {
    admin-web = {
      host              = var.hostnames["admin"]
      port              = 8080
      health_check_path = "/login" # until the admin web has /api/health
      priority          = 10
    }
  }
}

# One certificate for the CloudFront distributions (must be in us-east-1)
module "cert_cloudfront" {
  source    = "../../modules/acm-certificate"
  providers = { aws = aws.us_east_1 }

  domain_name               = var.hostnames["frontend"]
  subject_alternative_names = [var.hostnames["admin"], var.hostnames["api"]]
  wait_for_validation       = var.certificates_validated
}

# The internal ALB serves the API hostname (ap-south-1)
module "cert_alb" {
  source = "../../modules/acm-certificate"

  domain_name         = var.hostnames["api"]
  wait_for_validation = var.certificates_validated
}

# The internal ALB also serves the admin web hostname (ap-south-1).
# Same validation CNAME as the CloudFront cert, so it issues on its own.
module "cert_alb_admin" {
  source = "../../modules/acm-certificate"

  domain_name         = var.hostnames["admin"]
  wait_for_validation = var.certificates_validated
}

# ---------------------------------------------------------------
# Edge: WAF + CloudFront -> VPC origin -> internal ALB
# ---------------------------------------------------------------
module "waf_api" {
  source    = "../../modules/waf"
  providers = { aws = aws.us_east_1 }

  name_prefix           = local.name_prefix
  name                  = "api"
  managed_rules_mode    = var.waf.managed_rules_mode
  rate_limit_per_5_min  = var.waf.api.rate_limit_per_5_min
  allowed_country_codes = var.waf.api.allowed_country_codes
  allowed_ip_cidrs      = var.waf.api.allowed_ip_cidrs
  log_retention_days    = var.log_retention_days
}

module "waf_admin" {
  source    = "../../modules/waf"
  providers = { aws = aws.us_east_1 }

  name_prefix             = local.name_prefix
  name                    = "admin-web"
  managed_rules_mode      = var.waf.managed_rules_mode
  rate_limit_per_5_min    = var.waf.admin.rate_limit_per_5_min
  allowed_country_codes   = var.waf.admin.allowed_country_codes
  allowed_ip_cidrs        = var.waf.admin.allowed_ip_cidrs
  restrict_to_allowed_ips = var.waf.admin.restrict_to_allowed_ips
  log_retention_days      = var.log_retention_days
}

# Public entry point for the API
module "api_cdn" {
  source = "../../modules/cloudfront-alb"

  name_prefix     = local.name_prefix
  alb_arn         = module.alb.alb_arn
  alb_dns_name    = module.alb.alb_dns_name
  aliases         = [var.hostnames["api"]]
  certificate_arn = module.cert_cloudfront.certificate_arn # us-east-1 cert
  web_acl_arn     = module.waf_api.web_acl_arn
}

# Admin panel: same ALB and VPC origin, its own distribution and web ACL
module "admin_cdn" {
  source = "../../modules/cloudfront-alb"

  name_prefix            = local.name_prefix
  name                   = "admin-web"
  description            = "admin web"
  alb_arn                = module.alb.alb_arn
  alb_dns_name           = module.alb.alb_dns_name
  vpc_origin_id          = module.api_cdn.vpc_origin_id
  aliases                = [var.hostnames["admin"]]
  certificate_arn        = module.cert_cloudfront.certificate_arn
  web_acl_arn            = module.waf_admin.web_acl_arn
  viewer_protocol_policy = "redirect-to-https"
  static_cache_paths     = ["/_next/static/*"]
}

# ---------------------------------------------------------------
# CI/CD: Bitbucket OIDC roles scoped to this environment's deployments
# ---------------------------------------------------------------
module "ci_oidc" {
  source = "../../modules/ci-oidc"

  name_prefix       = local.name_prefix
  oidc_provider_url = var.bitbucket.oidc_provider_url
  oidc_audience     = var.bitbucket.oidc_audience

  # Build step: push only (no deployment environment)
  push_roles = {
    backend = {
      repo_uuid = var.bitbucket.backend_repo_uuid
      ecr_repository_arns = [
        module.ecr.repository_arn, # api
        module.ecr_worker.repository_arn,
        module.ecr_scheduler.repository_arn,
      ]
      description = "Bitbucket pipeline of acme-core-backend: push images to ECR (${var.environment})"
    }
    admin-web = {
      repo_uuid           = var.bitbucket.admin_web_repo_uuid
      ecr_repository_arns = [module.ecr_admin.repository_arn]
      description         = "Bitbucket pipeline of acme-admin-web: push images to ECR (${var.environment})"
    }
  }

  # Deploy step: only from this environment's deployment (approvals live in Bitbucket)
  deploy_roles = {
    backend = {
      repo_uuid        = var.bitbucket.backend_repo_uuid
      environment_uuid = var.bitbucket.backend_env_uuid
      description      = "Bitbucket ${var.environment} deployment of acme-core-backend: migrate and roll out api, worker and scheduler"
      cluster_arn      = module.ecs_cluster.cluster_arn
      service_names = [
        module.app_service.service_name,
        module.worker_service.service_name,
        module.scheduler_service.service_name,
      ]
      pass_role_arns = [
        module.app_service.execution_role_arn, module.app_service.task_role_arn,
        module.worker_service.execution_role_arn, module.worker_service.task_role_arn,
        module.scheduler_service.execution_role_arn, module.scheduler_service.task_role_arn,
      ]
    }
    admin-web = {
      repo_uuid        = var.bitbucket.admin_web_repo_uuid
      environment_uuid = var.bitbucket.admin_web_env_uuid
      description      = "Bitbucket ${var.environment} deployment of acme-admin-web: roll out admin-web"
      cluster_arn      = module.ecs_cluster.cluster_arn
      service_names    = [module.admin_web_service.service_name]
      pass_role_arns   = [module.admin_web_service.execution_role_arn, module.admin_web_service.task_role_arn]
    }
  }

  # This repo's own pipeline: plan on every PR, apply only from this environment's deployment
  terraform_ci = {
    repo_uuid        = var.bitbucket.iaac_repo_uuid
    environment_uuid = var.bitbucket.iaac_env_uuid
    state_bucket_arn = "arn:aws:s3:::${local.name_prefix}-tfstate-${var.aws_account_id}"
    state_key        = "${var.environment}/terraform.tfstate"
  }
}

# ---------------------------------------------------------------
# Operations: office hours, budget, alarms
# ---------------------------------------------------------------
# Office hours: RDS and the scheduler service. The autoscaled services follow the
# same crons through their scheduled scaling actions (see local.office_hours_actions).
module "office_hours" {
  source = "../../modules/env-scheduler"
  count  = var.office_hours == null ? 0 : 1

  name_prefix            = local.name_prefix
  cluster_name           = module.ecs_cluster.cluster_name
  db_instance_identifier = module.database.db_identifier
  timezone               = var.timezone
  db_start_cron          = var.office_hours.db_start_cron
  services_start_cron    = var.office_hours.services_start_cron
  services_stop_cron     = var.office_hours.services_stop_cron
  db_stop_cron           = var.office_hours.db_stop_cron

  services = {
    (module.scheduler_service.service_name) = 1
  }
}

module "budget" {
  source = "../../modules/budget"

  name_prefix       = local.name_prefix
  monthly_limit_usd = var.budget_monthly_limit_usd
  alert_emails      = var.alert_emails
}

# E-mail when the API, admin web, worker or database is in trouble
module "alarms" {
  source = "../../modules/alarms"

  name_prefix            = local.name_prefix
  alert_emails           = var.alert_emails
  alb_arn_suffix         = module.alb.alb_arn_suffix
  target_groups          = module.alb.target_group_arn_suffixes
  db_instance_identifier = module.database.db_identifier
  db_free_storage_gib    = 10

  error_log_groups = {
    api       = module.app_service.log_group_name
    worker    = module.worker_service.log_group_name
    scheduler = module.scheduler_service.log_group_name
    admin-web = module.admin_web_service.log_group_name
  }
}
