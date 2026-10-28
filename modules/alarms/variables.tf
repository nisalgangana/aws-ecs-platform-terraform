variable "name_prefix" {
  description = "Prefix for resource names, e.g. acme-dev"
  type        = string
}

variable "alert_emails" {
  description = "E-mail addresses subscribed to the alerts topic (each must confirm once)"
  type        = list(string)
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (dimension LoadBalancer)"
  type        = string
}

variable "target_groups" {
  description = "Target group key => ARN suffix; one unhealthy-targets alarm each"
  type        = map(string)
}

variable "db_instance_identifier" {
  description = "RDS instance identifier"
  type        = string
}

variable "error_log_groups" {
  description = "Name => CloudWatch log group of a JSON-logging service; one error-count alarm each"
  type        = map(string)
}

variable "http_5xx_threshold" {
  description = "5xx responses in 5 minutes that raise the alarm"
  type        = number
  default     = 5
}

variable "error_log_threshold" {
  description = "ERROR log lines in 5 minutes that raise the alarm"
  type        = number
  default     = 10
}

variable "db_cpu_percent" {
  description = "Average RDS CPU over 15 minutes that raises the alarm"
  type        = number
  default     = 80
}

variable "db_free_storage_gib" {
  description = "Free RDS storage below this raises the alarm"
  type        = number
  default     = 2
}
