variable "name_prefix" {
  description = "Prefix for resource names, e.g. acme-dev"
  type        = string
}

variable "aws_account_id" {
  description = "Account ID, appended to the bucket name (bucket names are global)"
  type        = string
}

variable "aliases" {
  description = "Hostnames served by this distribution, e.g. [\"example.com\", \"www.example.com\"]; [] = *.cloudfront.net only"
  type        = list(string)
  default     = []
}

variable "certificate_arn" {
  description = "ACM certificate in us-east-1 covering every alias; null = CloudFront default certificate"
  type        = string
  default     = null
}

variable "price_class" {
  description = "PriceClass_All serves Australia from Australian edges"
  type        = string
  default     = "PriceClass_All"
}

variable "api" {
  description = "Optional Lambda function URL served under /api/* (CloudFront signs with OAC); null = static only"
  type = object({
    function_name       = string
    function_url_domain = string
  })
  default = null
}
