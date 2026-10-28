locals {
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
}

# Reads the identity Terraform is running as.
# Using any data source forces the AWS provider to authenticate on every plan,
# so allowed_account_ids is always checked.
data "aws_caller_identity" "current" {}

# Created by AWS together with the first CloudFront VPC origin in this VPC.
# A brand-new environment must apply once without it (see modules/security).
data "aws_security_group" "cloudfront_vpc_origin" {
  vpc_id = module.network.vpc_id

  filter {
    name   = "group-name"
    values = ["CloudFront-VPCOrigins-Service-SG"]
  }
}

module "network" {
  source = "../../modules/network"

  name_prefix       = "${var.project}-${var.environment}"
  vpc_cidr          = var.vpc_cidr
  nat_gateway_count = var.nat_gateway_count
}

module "security" {
  source = "../../modules/security"

  name_prefix = "${var.project}-${var.environment}"
  vpc_id      = module.network.vpc_id

  manage_app_secret_value       = true
  app_secret_values             = var.app_secret_values
  app_secret_version            = 5
  manage_admin_web_secret_value = true
  admin_web_secret_values       = var.admin_web_secret_values
  admin_web_secret_version      = 1

  # ALB inbound: CloudFront VPC origin SG only (7.3)
  cloudfront_vpc_origin_sg_id  = data.aws_security_group.cloudfront_vpc_origin.id
  allow_cloudfront_prefix_list = false # Phase A; set false in Phase B
}


module "database" {
  source = "../../modules/database"

  name_prefix = "${var.project}-${var.environment}"
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
  apply_immediately     = true
}

# One-off psql tasks as the master user (create the app user, grants, extensions)
module "db_ops" {
  source = "../../modules/db-ops-task"

  name_prefix          = "${var.project}-${var.environment}"
  kms_key_arn          = module.security.kms_key_arn
  db_address           = module.database.db_address
  db_name              = "acme"
  db_master_secret_arn = module.database.db_master_secret_arn
  app_secret_arn       = module.security.app_secret_arn
}


# api image (kept as "app" so the existing repo is not recreated)
module "ecr" {
  source = "../../modules/ecr"

  name        = "${var.project}-${var.environment}-app"
  kms_key_arn = module.security.kms_key_arn
}

module "ecr_worker" {
  source = "../../modules/ecr"

  name        = "${var.project}-${var.environment}-worker"
  kms_key_arn = module.security.kms_key_arn
}

module "ecr_scheduler" {
  source = "../../modules/ecr"

  name        = "${var.project}-${var.environment}-scheduler"
  kms_key_arn = module.security.kms_key_arn
}

module "ecr_admin" {
  source = "../../modules/ecr"

  name        = "${var.project}-${var.environment}-admin-web"
  kms_key_arn = module.security.kms_key_arn
}


module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  name_prefix = "${var.project}-${var.environment}"
}

module "app_service" {
  source = "../../modules/ecs-service"

  name_prefix  = "${var.project}-${var.environment}"
  service_name = "app"
  kms_key_arn  = module.security.kms_key_arn
  secret_arns  = [module.security.app_secret_arn]

  cluster_arn        = module.ecs_cluster.cluster_arn
  image              = "${module.ecr.repository_url}:${var.app_image_tag}"
  command            = ["api"]
  desired_count      = 1
  subnet_ids         = [module.network.public_subnet_ids[0]] # dev: tasks in AZ a, public IP, no NAT
  security_group_ids = [module.security.app_sg_id]
  assign_public_ip   = true
  target_group_arn   = module.alb.target_group_arn

  # Plain config from tfvars + values only Terraform knows (bucket name contains the account ID)
  environment    = local.app_runtime_environment
  app_secret_arn = module.security.app_secret_arn
  secret_keys    = local.app_secret_keys
}

# Background jobs: OTP SMS, payment events, River job queue. No HTTP traffic, so no ALB.
module "worker_service" {
  source = "../../modules/ecs-service"

  name_prefix  = "${var.project}-${var.environment}"
  service_name = "worker"
  kms_key_arn  = module.security.kms_key_arn
  secret_arns  = [module.security.app_secret_arn]

  cluster_arn        = module.ecs_cluster.cluster_arn
  image              = "${module.ecr_worker.repository_url}:${var.app_image_tag}"
  command            = ["worker"]
  cpu                = 256
  memory             = 512
  desired_count      = 1 # 1 after migrations
  subnet_ids         = [module.network.public_subnet_ids[0]]
  security_group_ids = [module.security.app_sg_id]
  assign_public_ip   = true

  # Plain config from tfvars + values only Terraform knows (bucket name contains the account ID)
  environment    = local.app_runtime_environment
  app_secret_arn = module.security.app_secret_arn
  secret_keys    = local.app_secret_keys
}

# Periodic jobs: decides when a job is due and enqueues it; the worker runs it. No HTTP, so no ALB.
module "scheduler_service" {
  source = "../../modules/ecs-service"

  name_prefix  = "${var.project}-${var.environment}"
  service_name = "scheduler"
  kms_key_arn  = module.security.kms_key_arn
  secret_arns  = [module.security.app_secret_arn]

  cluster_arn        = module.ecs_cluster.cluster_arn
  image              = "${module.ecr_scheduler.repository_url}:${var.app_image_tag}"
  command            = ["scheduler"]
  cpu                = 256
  memory             = 512
  desired_count      = 0 # 0 until the first scheduler image is in ECR
  subnet_ids         = [module.network.public_subnet_ids[0]]
  security_group_ids = [module.security.app_sg_id]
  assign_public_ip   = true

  environment    = local.app_runtime_environment
  app_secret_arn = module.security.app_secret_arn
  secret_keys    = local.app_secret_keys
}

# Presigned uploads (photos, documents). Dev keeps files 14 days; decide per environment.
module "uploads" {
  source = "../../modules/s3-uploads"

  name_prefix     = "${var.project}-${var.environment}"
  kms_key_arn     = module.security.kms_key_arn
  expiration_days = 14

  cors_allowed_origins = [
    "https://${var.hostnames["admin"]}",
    "https://${var.hostnames["frontend"]}",
    "http://localhost:3000", # dev only: admin web running locally
  ]

  access_role_names = {
    api    = module.app_service.task_role_name
    worker = module.worker_service.task_role_name
  }
}


# Admin panel (Next.js BFF). Calls the API through https://api-dev.example.com, never the DB.
module "admin_web_service" {
  source = "../../modules/ecs-service"

  name_prefix  = "${var.project}-${var.environment}"
  service_name = "admin-web"
  kms_key_arn  = module.security.kms_key_arn
  secret_arns  = [module.security.admin_web_secret_arn]

  cluster_arn        = module.ecs_cluster.cluster_arn
  image              = "${module.ecr_admin.repository_url}:${var.admin_web_image_tag}"
  command            = ["server.js"] # distroless: the image's ENTRYPOINT is node
  cpu                = 256
  memory             = 512
  desired_count      = 1 # 1 after the first image is in ECR
  container_port     = 8080
  subnet_ids         = [module.network.public_subnet_ids[0]]
  security_group_ids = [module.security.admin_web_sg_id]
  assign_public_ip   = true
  target_group_arn   = module.alb.host_target_group_arns["admin-web"]

  environment    = var.admin_web_environment
  app_secret_arn = module.security.admin_web_secret_arn
  secret_keys    = ["SESSION_SECRET"]
}



module "alb" {
  source = "../../modules/alb"

  name_prefix       = "${var.project}-${var.environment}"
  vpc_id            = module.network.vpc_id
  subnet_ids        = module.network.private_app_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
  health_check_path = "/api/v1/health/ready"
  certificate_arn   = module.cert_alb.certificate_arn

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

module "ci_oidc" {
  source = "../../modules/ci-oidc"

  name_prefix       = "${var.project}-${var.environment}"
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
      description = "Bitbucket pipeline of acme-core-backend: push images to ECR"
    }
    admin-web = {
      repo_uuid           = var.bitbucket.admin_web_repo_uuid
      ecr_repository_arns = [module.ecr_admin.repository_arn]
      description         = "Bitbucket pipeline of acme-admin-web: push images to ECR"
    }
  }

  # Deploy step: only from the "dev" deployment environment
  deploy_roles = {
    backend = {
      repo_uuid        = var.bitbucket.backend_repo_uuid
      environment_uuid = var.bitbucket.backend_dev_env_uuid
      description      = "Bitbucket dev deployment of acme-core-backend: migrate and roll out api, worker and scheduler"
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
      environment_uuid = var.bitbucket.admin_web_dev_env_uuid
      description      = "Bitbucket dev deployment of acme-admin-web: roll out admin-web"
      cluster_arn      = module.ecs_cluster.cluster_arn
      service_names    = [module.admin_web_service.service_name]
      pass_role_arns   = [module.admin_web_service.execution_role_arn, module.admin_web_service.task_role_arn]
    }
  }

  # Landing site: sync the static export and invalidate the cache (dev deployment only)
  site_deploy_roles = {
    landing = {
      repo_uuid        = var.bitbucket.landing_repo_uuid
      environment_uuid = var.bitbucket.landing_dev_env_uuid
      description      = "Bitbucket dev deployment of acme-landing-page: sync the site, invalidate the cache"
      bucket_arn       = module.landing.bucket_arn
      distribution_arn = module.landing.distribution_arn
    }
  }


  # This repo's own pipeline: plan on every PR, apply after merge (dev deployment only)
  terraform_ci = {
    repo_uuid        = var.bitbucket.iaac_repo_uuid
    environment_uuid = var.bitbucket.iaac_dev_env_uuid
    state_bucket_arn = "arn:aws:s3:::${var.project}-${var.environment}-tfstate-${var.aws_account_id}"
    state_key        = "${var.environment}/terraform.tfstate"
  }
}




# One certificate for all three CloudFront distributions (must be in us-east-1)
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

# Marketing site certificate (us-east-1 for CloudFront). Own toggle: it is validated
# after the other certificates, so it cannot share certificates_validated.
module "cert_landing" {
  source    = "../../modules/acm-certificate"
  providers = { aws = aws.us_east_1 }

  domain_name               = var.hostnames["landing"]
  subject_alternative_names = [var.hostnames["landing_www"]]
  wait_for_validation       = var.landing_certificate_validated
}


# Public entry point for the API: CloudFront -> VPC origin -> internal ALB
module "api_cdn" {
  source = "../../modules/cloudfront-alb"

  name_prefix     = "${var.project}-${var.environment}"
  alb_arn         = module.alb.alb_arn
  alb_dns_name    = module.alb.alb_dns_name
  aliases         = [var.hostnames["api"]]
  certificate_arn = module.cert_cloudfront.certificate_arn # us-east-1 cert
  # web_acl_arn: none in dev; preprod/prod pass module.waf.web_acl_arn
}

# Admin panel: same ALB and VPC origin, its own distribution (own cache, own WAF later)
module "admin_cdn" {
  source = "../../modules/cloudfront-alb"

  name_prefix            = "${var.project}-${var.environment}"
  name                   = "admin-web"
  description            = "admin web"
  alb_arn                = module.alb.alb_arn
  alb_dns_name           = module.alb.alb_dns_name
  vpc_origin_id          = module.api_cdn.vpc_origin_id
  aliases                = [var.hostnames["admin"]]
  certificate_arn        = module.cert_cloudfront.certificate_arn # already covers admin-dev
  viewer_protocol_policy = "redirect-to-https"
  static_cache_paths     = ["/_next/static/*"]
}

# Dev runs weekdays 08:00-20:00 local time; everything else is off
module "scheduler" {
  source = "../../modules/env-scheduler"

  name_prefix            = "${var.project}-${var.environment}"
  cluster_name           = "${var.project}-${var.environment}-cluster"
  db_instance_identifier = "${var.project}-${var.environment}-db"
  services = {
    (module.app_service.service_name)       = 1
    (module.worker_service.service_name)    = 1
    (module.admin_web_service.service_name) = 1
  }
}

module "budget" {
  source = "../../modules/budget"

  name_prefix       = "${var.project}-${var.environment}"
  monthly_limit_usd = 100
  alert_emails      = var.budget_alert_emails
}

# E-mail when the API, admin web, worker or database is in trouble
module "alarms" {
  source = "../../modules/alarms"

  name_prefix            = "${var.project}-${var.environment}"
  alert_emails           = var.budget_alert_emails
  alb_arn_suffix         = module.alb.alb_arn_suffix
  target_groups          = module.alb.target_group_arn_suffixes
  db_instance_identifier = "${var.project}-${var.environment}-db"

  error_log_groups = {
    api       = module.app_service.log_group_name
    worker    = module.worker_service.log_group_name
    scheduler = module.scheduler_service.log_group_name
    admin-web = module.admin_web_service.log_group_name
  }
}

# Contact and dealer forms of the landing site: /api/* -> Lambda -> SNS -> e-mail
module "landing_form" {
  source = "../../modules/site-form"

  name_prefix   = "${var.project}-${var.environment}"
  notify_emails = var.landing_form_emails
}

# Marketing site example.com: static export in S3 behind CloudFront, forms under /api/*
module "landing" {
  source = "../../modules/static-site"

  name_prefix     = "${var.project}-${var.environment}"
  aws_account_id  = var.aws_account_id
  aliases         = [var.hostnames["landing"], var.hostnames["landing_www"]]
  certificate_arn = module.cert_landing.certificate_arn # us-east-1, waits for validation

  api = {
    function_name       = module.landing_form.function_name
    function_url_domain = module.landing_form.function_url_domain
  }
}

output "uploads_bucket_name" {
  description = "Private bucket for presigned uploads"
  value       = module.uploads.bucket_name
}
