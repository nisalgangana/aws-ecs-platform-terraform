variable "name_prefix" {
  description = "Prefix for resource names, e.g. acme-dev"
  type        = string
}

variable "vpc_id" {
  description = "VPC to create the security groups in"
  type        = string
}

variable "app_port" {
  description = "Port the Go API listens on"
  type        = number
  default     = 8080
}

variable "db_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "kms_deletion_window_days" {
  description = "Days before a deleted KMS key is really gone (7 dev, 30 prod)"
  type        = number
  default     = 7

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "kms_deletion_window_days must be between 7 and 30."
  }
}

variable "secret_recovery_window_days" {
  description = "Days a deleted secret can be restored (0 = delete immediately)"
  type        = number
  default     = 7
}

variable "manage_app_secret_value" {
  description = "Let Terraform write the app secret value (write-only, never stored in state)"
  type        = bool
  default     = false
}

variable "app_secret_values" {
  description = "Key/value pairs for the app integrations secret"
  type        = map(string)
  sensitive   = true
  ephemeral   = true
  default     = null
}

variable "app_secret_version" {
  description = "Bump this number to push new secret values"
  type        = number
  default     = 1
}

variable "manage_admin_web_secret_value" {
  description = "Let Terraform write the admin web secret value (write-only, never stored in state)"
  type        = bool
  default     = false
}

variable "admin_web_secret_values" {
  description = "Key/value pairs for the admin web secret (SESSION_SECRET)"
  type        = map(string)
  sensitive   = true
  ephemeral   = true
  default     = null
}

variable "admin_web_secret_version" {
  description = "Bump this number to push new admin web secret values"
  type        = number
  default     = 1
}

variable "allow_cloudfront_prefix_list" {
  description = "ALB inbound 443 from every CloudFront IP (needed until the VPC origin exists)"
  type        = bool
  default     = true
}

variable "cloudfront_vpc_origin_sg_id" {
  description = "CloudFront-VPCOrigins-Service-SG (created by AWS with the first VPC origin); null = not yet"
  type        = string
  default     = null
}
