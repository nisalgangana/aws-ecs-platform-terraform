variable "aws_account_id" {
  description = "The AWS account ID to use for the provider."
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

variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  type        = string

}

variable "nat_gateway_count" {
  description = "NAT gateways for this environment (dev = 0)"
  type        = number
}

variable "app_secret_values" {
  description = "App integration secrets (TF_VAR_app_secret_values). Only read when app_secret_version changes; bump it only with real values"
  type        = map(string)
  sensitive   = true
  ephemeral   = true
  default     = {}
}

variable "admin_web_secret_values" {
  description = "Admin web secrets (TF_VAR_admin_web_secret_values). Only read when admin_web_secret_version changes; bump it only with real values"
  type        = map(string)
  sensitive   = true
  ephemeral   = true
  default     = {}
}


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

variable "bitbucket" {
  description = "Bitbucket OIDC settings (public values, not secrets)"
  type = object({
    oidc_provider_url      = string
    oidc_audience          = string
    backend_repo_uuid      = string
    admin_web_repo_uuid    = string
    iaac_repo_uuid         = string
    backend_dev_env_uuid   = string
    admin_web_dev_env_uuid = string
    iaac_dev_env_uuid      = string
    landing_repo_uuid      = string
    landing_dev_env_uuid   = string

  })

  validation {
    condition = alltrue([
      for u in [var.bitbucket.backend_repo_uuid, var.bitbucket.admin_web_repo_uuid, var.bitbucket.iaac_repo_uuid,
        var.bitbucket.landing_repo_uuid, var.bitbucket.backend_dev_env_uuid, var.bitbucket.admin_web_dev_env_uuid,
      var.bitbucket.iaac_dev_env_uuid, var.bitbucket.landing_dev_env_uuid] :
      can(regex("^\\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\}$", u))
    ])
    error_message = "Bitbucket UUIDs must look like {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx} (braces, lowercase hex)."
  }

  validation {
    condition = (
      var.bitbucket.backend_dev_env_uuid != var.bitbucket.backend_repo_uuid &&
      var.bitbucket.admin_web_dev_env_uuid != var.bitbucket.admin_web_repo_uuid &&
      var.bitbucket.iaac_dev_env_uuid != var.bitbucket.iaac_repo_uuid &&
      var.bitbucket.landing_dev_env_uuid != var.bitbucket.landing_repo_uuid
    )
    error_message = "A dev environment UUID is the same as its repo UUID: copy it from OIDC page → Select Environment → dev."
  }
}



variable "hostnames" {
  description = "Public hostnames for this environment (role => hostname)"
  type        = map(string)
}

variable "certificates_validated" {
  description = "true once the ACM validation CNAMEs are in the example.com zone"
  type        = bool
  default     = false
}

variable "app_image_tag" {
  description = "Image tag (git commit SHA) to run"
  type        = string
}

variable "app_environment" {
  description = "Non-secret app settings for this environment"
  type        = map(string)
}

variable "budget_alert_emails" {
  description = "Budget alert recipients"
  type        = list(string)
}

variable "admin_web_image_tag" {
  description = "Admin web image tag in ECR (git commit SHA from the admin-web pipeline)"
  type        = string
}

variable "admin_web_environment" {
  description = "Non-secret environment variables for the admin web container"
  type        = map(string)
}

variable "landing_certificate_validated" {
  description = "true once the landing site's ACM validation CNAMEs are in the example.com zone"
  type        = bool
  default     = false
}

variable "landing_form_emails" {
  description = "Who receives landing site enquiries (each address must confirm the SNS e-mail)"
  type        = list(string)
}
