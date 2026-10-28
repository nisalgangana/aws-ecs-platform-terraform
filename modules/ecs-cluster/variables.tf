variable "name_prefix" {
  description = "Prefix for resource names, e.g. acme-dev"
  type        = string
}

variable "container_insights" {
  description = "disabled (dev), enabled or enhanced (prod) — insights cost money"
  type        = string
  default     = "disabled"

  validation {
    condition     = contains(["disabled", "enabled", "enhanced"], var.container_insights)
    error_message = "container_insights must be disabled, enabled or enhanced."
  }
}
