terraform {
  required_version = ">= 1.11"

  # Bucket name is passed at init time: -backend-config="bucket=acme-preprod-tfstate-<account-id>"
  backend "s3" {
    key          = "preprod/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
