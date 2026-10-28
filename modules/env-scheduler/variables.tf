variable "name_prefix" {
  description = "Prefix for resource names, e.g. acme-dev"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "services" {
  description = "ECS service name => desired count while the environment is up"
  type        = map(number)
}

variable "db_instance_identifier" {
  description = "RDS instance to start and stop"
  type        = string
}

variable "timezone" {
  description = "IANA time zone for the cron expressions"
  type        = string
  default     = "Etc/UTC"
}

variable "db_start_cron" {
  description = "When the database starts (before the services)"
  type        = string
  default     = "cron(40 7 ? * MON-FRI *)"
}

variable "services_start_cron" {
  description = "When the services start"
  type        = string
  default     = "cron(0 8 ? * MON-FRI *)"
}

variable "services_stop_cron" {
  description = "When the services stop (before the database)"
  type        = string
  default     = "cron(0 20 ? * MON-FRI *)"
}

variable "db_stop_cron" {
  description = "When the database stops"
  type        = string
  default     = "cron(15 20 ? * MON-FRI *)"
}
