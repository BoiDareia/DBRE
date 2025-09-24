terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.51.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"  # Must be modified to match the intended region
}

