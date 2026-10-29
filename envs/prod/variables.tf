# ---------------------------------------------------------------
# Account and naming
# ---------------------------------------------------------------
variable "aws_account_id" {
  description = "The AWS account ID to use for the provider (TF_VAR_aws_account_id, never in git)."
  type        = string

  validation {
    condition     = can(regex("^\\d{12}$", var.aws_account_id))
    error_message = "The AWS account ID must be a 12-digit number."
  }
}

variable "aws_region" {
  description = "The AWS region to use for the provider."
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "The environment name (dev, preprod, prod)."
  type        = string

  validation {
    condition     = contains(["dev", "preprod", "prod"], var.environment)
    error_message = "The environment must be one of: dev, preprod, prod."
  }
}

variable "project" {
  description = "The name of the project."
  type        = string
  default     = "acme"
}

variable "timezone" {
  description = "IANA time zone for office hours and peak schedules"
  type        = string
  default     = "Asia/Kolkata"
}

# ---------------------------------------------------------------
# Network
# ---------------------------------------------------------------
variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  type        = string
}

variable "nat_gateway_count" {
  description = "NAT gateways for this environment (preprod = 1, prod = 2)"
  type        = number
}

# ---------------------------------------------------------------
# Secrets (write-only: never in plan or state)
# ---------------------------------------------------------------
variable "app_secret_values" {
  description = "App integration secrets (TF_VAR_app_secret_values). Only read when app_secret_version changes; bump it only with real values"
  type        = map(string)
  sensitive   = true
  ephemeral   = true
  default     = {}
}

variable "app_secret_version" {
  description = "Bump to push new app_secret_values"
  type        = number
  default     = 1
}

variable "admin_web_secret_values" {
  description = "Admin web secrets (TF_VAR_admin_web_secret_values). Only read when admin_web_secret_version changes; bump it only with real values"
  type        = map(string)
  sensitive   = true
  ephemeral   = true
  default     = {}
}

variable "admin_web_secret_version" {
  description = "Bump to push new admin_web_secret_values"
  type        = number
  default     = 1
}

# ---------------------------------------------------------------
# Database
# ---------------------------------------------------------------
variable "db" {
  description = "RDS settings for this environment"
  type = object({
    instance_class        = string
    allocated_storage     = number
    multi_az              = bool
    backup_retention_days = number
    deletion_protection   = bool
    skip_final_snapshot   = bool
    backup_window         = string
    maintenance_window    = string
  })
}

# ---------------------------------------------------------------
# CI/CD (public identifiers, not secrets)
# ---------------------------------------------------------------
variable "bitbucket" {
  description = "Bitbucket OIDC settings. *_env_uuid = this environment's deployment in that repo (OIDC page → Select Environment), NOT the repo UUID"
  type = object({
    oidc_provider_url   = string
    oidc_audience       = string
    backend_repo_uuid   = string
    admin_web_repo_uuid = string
    iaac_repo_uuid      = string
    backend_env_uuid    = string
    admin_web_env_uuid  = string
    iaac_env_uuid       = string
  })

  validation {
    condition = alltrue([
      for u in [
        var.bitbucket.backend_repo_uuid, var.bitbucket.admin_web_repo_uuid, var.bitbucket.iaac_repo_uuid,
        var.bitbucket.backend_env_uuid, var.bitbucket.admin_web_env_uuid, var.bitbucket.iaac_env_uuid,
      ] : can(regex("^\\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\}$", u))
    ])
    error_message = "Bitbucket UUIDs must look like {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx} (braces, lowercase hex)."
  }

  validation {
    condition = (
      var.bitbucket.backend_env_uuid != var.bitbucket.backend_repo_uuid &&
      var.bitbucket.admin_web_env_uuid != var.bitbucket.admin_web_repo_uuid &&
      var.bitbucket.iaac_env_uuid != var.bitbucket.iaac_repo_uuid
    )
    error_message = "An environment UUID is the same as its repo UUID: copy it from OIDC page → Select Environment → <this environment>."
  }
}

# ---------------------------------------------------------------
# Edge: hostnames, certificates, WAF
# ---------------------------------------------------------------
variable "hostnames" {
  description = "Public hostnames for this environment: frontend, admin, api"
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["frontend", "admin", "api"] : contains(keys(var.hostnames), k)])
    error_message = "hostnames needs the keys frontend, admin and api."
  }
}

variable "certificates_validated" {
  description = "true once the ACM validation CNAMEs are in the example.com zone (bootstrap step 2)"
  type        = bool
  default     = false
}

variable "vpc_origin_sg_ready" {
  description = "true once CloudFront created CloudFront-VPCOrigins-Service-SG in this VPC (bootstrap step 3): ALB then accepts the VPC origin only"
  type        = bool
  default     = false
}

variable "waf" {
  description = "WAF settings per distribution. managed_rules_mode: count for the first weeks, then block"
  type = object({
    managed_rules_mode = optional(string, "block")
    api = object({
      rate_limit_per_5_min  = number
      allowed_country_codes = optional(list(string), [])
      allowed_ip_cidrs      = optional(list(string), [])
    })
    admin = object({
      rate_limit_per_5_min    = number
      allowed_country_codes   = optional(list(string), [])
      allowed_ip_cidrs        = optional(list(string), [])
      restrict_to_allowed_ips = optional(bool, false)
    })
  })
}

# ---------------------------------------------------------------
# Workloads
# ---------------------------------------------------------------
variable "app_image_tag" {
  description = "First api/worker/scheduler image tag (git commit SHA); afterwards the deploy pipeline owns the running revision"
  type        = string
}

variable "admin_web_image_tag" {
  description = "First admin web image tag (git commit SHA); afterwards the deploy pipeline owns the running revision"
  type        = string
}

variable "app_environment" {
  description = "Non-secret app settings for this environment"
  type        = map(string)
}

variable "admin_web_environment" {
  description = "Non-secret environment variables for the admin web container"
  type        = map(string)
}

variable "services" {
  description = "Task size and scaling range per service. scheduler always runs exactly one task (advisory lock)"
  type = object({
    api = object({
      cpu                = number
      memory             = number
      min_count          = number
      max_count          = number
      cpu_target_percent = optional(number, 60)
    })
    worker = object({
      cpu                = number
      memory             = number
      min_count          = number
      max_count          = number
      cpu_target_percent = optional(number, 60)
    })
    scheduler = object({
      cpu    = number
      memory = number
    })
    admin_web = object({
      cpu                = number
      memory             = number
      min_count          = number
      max_count          = number
      cpu_target_percent = optional(number, 60)
    })
  })
}

variable "api_scheduled_scaling" {
  description = "Extra scheduled min/max changes for the api (afternoon peak). name => cron + range, in var.timezone"
  type = map(object({
    schedule     = string
    min_capacity = number
    max_capacity = number
  }))
  default = {}
}

variable "office_hours" {
  description = "Stop everything outside these crons (var.timezone); null = runs 24/7 (prod)"
  type = object({
    db_start_cron       = string
    services_start_cron = string
    services_stop_cron  = string
    db_stop_cron        = string
  })
  default = null
}

# ---------------------------------------------------------------
# Retention and observability
# ---------------------------------------------------------------
variable "log_retention_days" {
  description = "CloudWatch log retention for ECS tasks and Lambda (preprod 30, prod 90)"
  type        = number
  default     = 30
}

variable "uploads_expiration_days" {
  description = "Delete uploaded objects after this many days; null = keep forever"
  type        = number
  default     = null
}

variable "container_insights" {
  description = "ECS Container Insights: enabled (preprod) or enhanced (prod)"
  type        = string
  default     = "enabled"
}

variable "alert_emails" {
  description = "Recipients of CloudWatch alarms and budget alerts (each address confirms the SNS e-mail once)"
  type        = list(string)
}

variable "budget_monthly_limit_usd" {
  description = "Monthly cost budget (preprod 250, prod 1000)"
  type        = number
}

# ---------------------------------------------------------------
# Prod only: marketing site and disaster recovery
# ---------------------------------------------------------------
variable "landing_site_enabled" {
  description = "Serve the marketing site (hostnames.landing / landing_www) from this account. A hostname can be on one CloudFront distribution only: retire the dev one first"
  type        = bool
  default     = false

  validation {
    condition     = !var.landing_site_enabled || alltrue([for k in ["landing", "landing_www"] : contains(keys(var.hostnames), k)])
    error_message = "landing_site_enabled needs hostnames.landing and hostnames.landing_www."
  }

  validation {
    condition     = !var.landing_site_enabled || var.landing_env_uuids != null
    error_message = "landing_site_enabled needs landing_env_uuids (the landing repo's Bitbucket UUIDs) for the site deploy role."
  }
}

variable "landing_certificate_validated" {
  description = "true once the landing site's ACM validation CNAMEs are in the example.com zone"
  type        = bool
  default     = false
}

variable "landing_form_emails" {
  description = "Who receives landing site enquiries (each address must confirm the SNS e-mail)"
  type        = list(string)
  default     = []
}

variable "landing_env_uuids" {
  description = "Bitbucket repo and deployment UUIDs of acme-landing-page (its only site = Production); null until the landing site moves here"
  type = object({
    repo_uuid = string
    env_uuid  = string
  })
  default = null

  validation {
    condition = var.landing_env_uuids == null || alltrue([
      for u in [var.landing_env_uuids.repo_uuid, var.landing_env_uuids.env_uuid] :
      can(regex("^\\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\}$", u))
    ])
    error_message = "Bitbucket UUIDs must look like {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx} (braces, lowercase hex)."
  }
}

variable "dr" {
  description = "Cross-Region RDS automated backups (RPO ≈ 5 min). region is also where a Region-loss restore happens"
  type = object({
    enabled        = bool
    region         = string
    retention_days = number
  })
  default = {
    enabled        = true
    region         = "ap-south-2"
    retention_days = 7
  }
}
