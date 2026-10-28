variable "name_prefix" {
  description = "Prefix for resource names, e.g. acme-dev"
  type        = string
}

variable "notify_emails" {
  description = "Addresses that receive each enquiry (SNS e-mail, must be confirmed once)"
  type        = list(string)
}

variable "log_retention_days" {
  description = "Lambda log retention"
  type        = number
  default     = 30
}
