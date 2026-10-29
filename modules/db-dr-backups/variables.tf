variable "name_prefix" {
  description = "Prefix for resource names, e.g. acme-prod"
  type        = string
}

variable "source_db_instance_arn" {
  description = "ARN of the RDS instance in the primary Region"
  type        = string
}

variable "retention_days" {
  description = "How long the replicated backups are kept in the DR Region (1-35)"
  type        = number
  default     = 7

  validation {
    condition     = var.retention_days >= 1 && var.retention_days <= 35
    error_message = "retention_days must be between 1 and 35."
  }
}

variable "kms_deletion_window_days" {
  description = "Days before the DR key is really deleted"
  type        = number
  default     = 30
}
