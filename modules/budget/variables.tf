variable "name_prefix" {
  description = "Prefix for resource names, e.g. acme-dev"
  type        = string
}

variable "monthly_limit_usd" {
  description = "Monthly cost budget in USD (dev 100, preprod 250, prod 1000)"
  type        = number
}

variable "alert_emails" {
  description = "Who gets the budget e-mails"
  type        = list(string)
}
