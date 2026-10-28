variable "name_prefix" {
  description = "Prefix for resource names, e.g. acme-dev"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Private-app subnet IDs (2 AZs)"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group for the ALB (from module.security)"
  type        = string
}

variable "target_port" {
  description = "Port the app container listens on"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "App health endpoint (confirm with the backend team)"
  type        = string
  default     = "/healthz"
}

variable "deletion_protection" {
  description = "Block ALB deletion (prod = true)"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ACM certificate for the HTTPS listener (same Region as the ALB)"
  type        = string
}

variable "ssl_policy" {
  description = "TLS policy for the HTTPS listener"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "additional_certificates" {
  description = "Extra certificates on the HTTPS listener (SNI), name => ARN"
  type        = map(string)
  default     = {}
}

variable "host_routes" {
  description = "Hostnames sent to their own target group instead of the default (API) one"
  type = map(object({
    host              = string
    port              = number
    health_check_path = string
    priority          = number
  }))
  default = {}
}
