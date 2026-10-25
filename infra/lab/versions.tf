# Which Terraform and which provider (plugin) versions this code needs.
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # any 5.x version
    }
  }
}

# The AWS provider: which region to work in, and tags added to everything it creates.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "devops-capstone"
      Env       = "lab"
      ManagedBy = "terraform"
    }
  }
}
