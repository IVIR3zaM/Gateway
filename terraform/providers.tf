terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# Default provider — Frankfurt. EC2, S3, and CloudFront resources all use this.
provider "aws" {
  region = "eu-central-1"
  default_tags {
    tags = {
      Project   = "gateway"
      ManagedBy = "terraform"
    }
  }
}
