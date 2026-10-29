variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "service_name" {
  description = "ECS service name (from module.ecs-service, so the service exists first)"
  type        = string
}

variable "min_capacity" {
  description = "Tasks to keep at all times (prod api = 2, one per AZ)"
  type        = number
}

variable "max_capacity" {
  description = "Upper limit the scaler may reach"
  type        = number

  validation {
    condition     = var.max_capacity >= var.min_capacity
    error_message = "max_capacity must be greater than or equal to min_capacity."
  }
}

variable "cpu_target_percent" {
  description = "Average CPU the scaler keeps the service at; null = no CPU policy"
  type        = number
  default     = 60
}

variable "memory_target_percent" {
  description = "Average memory the scaler keeps the service at; null = no memory policy"
  type        = number
  default     = null
}

variable "requests_per_target" {
  description = "ALB requests per task per minute to scale on; null = no request policy"
  type        = number
  default     = null
}

variable "alb_resource_label" {
  description = "app/<alb-suffix>/targetgroup/<tg-suffix>, required when requests_per_target is set"
  type        = string
  default     = null

  validation {
    condition     = var.requests_per_target == null || var.alb_resource_label != null
    error_message = "requests_per_target needs alb_resource_label."
  }
}

variable "scale_out_cooldown" {
  description = "Seconds before another scale-out (short: react to a peak)"
  type        = number
  default     = 60
}

variable "scale_in_cooldown" {
  description = "Seconds before another scale-in (long: do not flap after a peak)"
  type        = number
  default     = 300
}

variable "scheduled_actions" {
  description = "name => cron and the min/max in force from then on (peak hours, office hours). 0/0 stops the service"
  type = map(object({
    schedule     = string # cron(30 15 ? * MON-FRI *)
    min_capacity = number
    max_capacity = number
  }))
  default = {}
}

variable "timezone" {
  description = "IANA time zone for scheduled_actions"
  type        = string
  default     = "Etc/UTC"
}
