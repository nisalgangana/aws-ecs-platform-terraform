variable "name_prefix" {
  description = "Prefix for resource names, e.g. acme-prod"
  type        = string
}

variable "name" {
  description = "Short name of the protected distribution, e.g. api, admin-web"
  type        = string
}

variable "rate_limit_per_5_min" {
  description = "Requests from one IP in 5 minutes before it is blocked (WAF minimum is 10)"
  type        = number
  default     = 2000

  validation {
    condition     = var.rate_limit_per_5_min >= 10
    error_message = "rate_limit_per_5_min must be at least 10 (AWS WAF minimum)."
  }
}

variable "allowed_country_codes" {
  description = "ISO 3166-1 alpha-2 codes; requests from any other country are blocked. [] = no geo rule"
  type        = list(string)
  default     = []
}

variable "allowed_ip_cidrs" {
  description = "IPv4 CIDRs that always pass (office, UAT providers, load-test runner); they skip the rate and managed rules"
  type        = list(string)
  default     = []
}

variable "restrict_to_allowed_ips" {
  description = "true = block everything that is not in allowed_ip_cidrs (private UAT); false = allow-list only skips the other rules"
  type        = bool
  default     = false

  validation {
    condition     = !var.restrict_to_allowed_ips || length(var.allowed_ip_cidrs) > 0
    error_message = "restrict_to_allowed_ips needs at least one CIDR in allowed_ip_cidrs, otherwise nobody can reach the site."
  }
}

variable "managed_rules_mode" {
  description = "block = enforce the AWS managed rule groups; count = log matches only (first weeks of a new environment)"
  type        = string
  default     = "block"

  validation {
    condition     = contains(["block", "count"], var.managed_rules_mode)
    error_message = "managed_rules_mode must be block or count."
  }
}

variable "common_rule_set_count_rules" {
  description = "Rules of AWSManagedRulesCommonRuleSet switched to count because they break the app, e.g. [\"SizeRestrictions_BODY\"]"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "WAF log retention in CloudWatch Logs (us-east-1)"
  type        = number
  default     = 30
}
