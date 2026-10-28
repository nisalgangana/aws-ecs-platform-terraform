variable "name_prefix" {
  description = "Prefix for resource names, e.g. acme-dev"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC, e.g. 10.10.0.0/16"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR, e.g. 10.10.0.0/16."
  }
}

variable "nat_gateway_count" {
  description = "NAT gateways: 0 = none (dev), 1 = shared (preprod), 2 = one per AZ (prod)"
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1, 2], var.nat_gateway_count)
    error_message = "nat_gateway_count must be 0, 1 or 2."
  }
}