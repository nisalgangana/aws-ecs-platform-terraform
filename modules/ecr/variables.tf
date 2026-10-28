variable "name" {
  description = "Repository name, e.g. acme-dev-app"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for image encryption (cannot change after creation)"
  type        = string
}

variable "keep_tagged_images" {
  description = "How many tagged images to keep"
  type        = number
  default     = 20
}
