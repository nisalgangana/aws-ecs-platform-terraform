locals {
  common_tags = {
    Project   = var.project
    Env       = var.environment
    ManagedBy = "terraform"
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.common_tags
  }
}

# CloudFront only accepts ACM certificates from us-east-1
provider "aws" {
  alias               = "us_east_1"
  region              = "us-east-1"
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.common_tags
  }
}