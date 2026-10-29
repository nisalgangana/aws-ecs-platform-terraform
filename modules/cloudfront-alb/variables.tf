variable "name_prefix" {
  description = "Prefix for resource names, e.g. acme-dev"
  type        = string
}

variable "alb_arn" {
  description = "Internal ALB to use as the VPC origin"
  type        = string
}

variable "alb_dns_name" {
  description = "Internal ALB DNS name (origin domain)"
  type        = string
}

variable "aliases" {
  description = "Hostnames served by this distribution, e.g. [\"api-dev.example.com\"]"
  type        = list(string)
}

variable "certificate_arn" {
  description = "ACM certificate in us-east-1 covering every alias"
  type        = string
}

variable "web_acl_arn" {
  description = "WAFv2 web ACL ARN (us-east-1); null = no WAF (dev)"
  type        = string
  default     = null
}

variable "price_class" {
  description = "CloudFront price class; PriceClass_All serves every viewer from the nearest edge"
  type        = string
  default     = "PriceClass_All"
}

variable "name" {
  description = "Short name for tags, e.g. api, admin-web"
  type        = string
  default     = "api"
}

variable "description" {
  description = "Distribution comment suffix"
  type        = string
  default     = "API"
}

variable "vpc_origin_id" {
  description = "Existing VPC origin to reuse (one per ALB); null = create one"
  type        = string
  default     = null
}

variable "viewer_protocol_policy" {
  description = "https-only for APIs; redirect-to-https for websites people type in a browser"
  type        = string
  default     = "https-only"
}

variable "static_cache_paths" {
  description = "Path patterns cached at the edge (immutable build assets), e.g. /_next/static/*"
  type        = list(string)
  default     = []
}
