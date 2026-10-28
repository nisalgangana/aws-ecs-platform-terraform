variable "name_prefix" {
  description = "Prefix for resource names, e.g. acme-dev"
  type        = string
}

variable "kms_key_arn" {
  description = "Environment KMS key for default bucket encryption"
  type        = string
}

variable "access_role_names" {
  description = "Name => IAM role name allowed to put/get/delete objects (the app's task roles)"
  type        = map(string)
}

variable "cors_allowed_origins" {
  description = "Web origins allowed to upload from the browser with a presigned URL; empty = no CORS"
  type        = list(string)
  default     = []
}

variable "expiration_days" {
  description = "Delete objects this many days after upload; null = keep forever"
  type        = number
  default     = null
}
