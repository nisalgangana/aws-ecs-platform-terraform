variable "name_prefix" {
  description = "Prefix for resource names, e.g. acme-dev"
  type        = string
}

variable "service_name" {
  description = "Short service name, e.g. app"
  type        = string
}

variable "kms_key_arn" {
  description = "Environment KMS key (logs, secrets)"
  type        = string
}

variable "secret_arns" {
  description = "Secrets the task may receive as environment variables"
  type        = list(string)
}

variable "log_retention_days" {
  description = "CloudWatch log retention (7 dev, 30+ prod)"
  type        = number
  default     = 7
}

variable "cluster_arn" {
  description = "ECS cluster to run in"
  type        = string
}

variable "image" {
  description = "Full image URI with tag, e.g. <repo-url>:<git-sha>"
  type        = string
}

variable "command" {
  description = "Run mode: [\"api\"], [\"worker\"] or [\"scheduler\"]"
  type        = list(string)
  default     = ["api"]
}

variable "cpu" {
  description = "Task CPU units (512 = 0.5 vCPU)"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Task memory in MiB"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "How many tasks to keep running"
  type        = number
  default     = 1
}

variable "container_port" {
  description = "Port the app listens on"
  type        = number
  default     = 8080
}

variable "subnet_ids" {
  description = "Subnets for the tasks (dev: public, preprod/prod: private-app)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups for the tasks (the app SG)"
  type        = list(string)
}

variable "assign_public_ip" {
  description = "true in dev (no NAT): tasks reach ECR, Secrets Manager and the internet directly"
  type        = bool
  default     = false
}

variable "target_group_arn" {
  description = "ALB target group, or null for services without HTTP (worker, scheduler)"
  type        = string
  default     = null
}

variable "environment" {
  description = "Non-secret environment variables"
  type        = map(string)
  default     = {}
}

variable "app_secret_arn" {
  description = "Secrets Manager secret holding the app's secret values (JSON)"
  type        = string
}

variable "secret_keys" {
  description = "JSON keys of app_secret_arn to inject as environment variables"
  type        = list(string)
  default     = []
}
