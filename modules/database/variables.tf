variable "name_prefix" {
  description = "Prefix for resource names, e.g. acme-dev"
  type        = string
}

variable "subnet_ids" {
  description = "Private-data subnet IDs (2 AZs)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS needs subnets in at least 2 AZs."
  }
}

variable "db_sg_id" {
  description = "Security group for RDS (from module.security)"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for storage and the master user secret"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL major version (minor upgrades are automatic)"
  type        = string
  default     = "18"
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "acme"
}

variable "master_username" {
  description = "Master user name (password is managed by RDS in Secrets Manager)"
  type        = string
  default     = "acme_admin"
}

variable "instance_class" {
  description = "e.g. db.t4g.micro (dev), db.t4g.large (prod)"
  type        = string
}

variable "allocated_storage" {
  description = "Storage in GB (gp3)"
  type        = number
}

variable "multi_az" {
  description = "Standby in a second AZ (prod)"
  type        = bool
}

variable "backup_retention_days" {
  description = "Automated backup retention in days (1-35)"
  type        = number
}

variable "deletion_protection" {
  description = "Block deletion through the API (prod = true)"
  type        = bool
}

variable "skip_final_snapshot" {
  description = "Skip the snapshot on delete (dev only)"
  type        = bool
}

variable "backup_window" {
  description = "Daily backup window in UTC, hh24:mi-hh24:mi"
  type        = string
}

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC, ddd:hh24:mi-ddd:hh24:mi"
  type        = string
}

variable "apply_immediately" {
  description = "Apply changes now instead of in the maintenance window (dev = true)"
  type        = bool
  default     = false
}
