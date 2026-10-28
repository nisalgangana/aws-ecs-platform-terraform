variable "domain_name" {
  description = "Main hostname on the certificate"
  type        = string
}

variable "subject_alternative_names" {
  description = "Extra hostnames on the same certificate"
  type        = list(string)
  default     = []
}

variable "wait_for_validation" {
  description = "Set true after the validation CNAMEs are in the example.com zone"
  type        = bool
  default     = false
}
