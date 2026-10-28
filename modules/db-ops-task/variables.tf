variable "name_prefix" {
  description = "Prefix for resource names, e.g. acme-dev"
  type        = string
}

variable "kms_key_arn" {
  description = "Environment KMS key (logs, secrets)"
  type        = string
}

variable "db_address" {
  description = "RDS endpoint hostname"
  type        = string
}

variable "db_name" {
  description = "Database to connect to"
  type        = string
}

variable "db_master_secret_arn" {
  description = "RDS-managed master user secret (keys: username, password)"
  type        = string
}

variable "app_secret_arn" {
  description = "App secret holding APP_DB_PASSWORD (the password for the app's own DB user)"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention"
  type        = number
  default     = 7
}
