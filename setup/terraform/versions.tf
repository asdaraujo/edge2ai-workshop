
terraform {
  required_version = ">= 0.12"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 2.42"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 2.1"
    }
  }

}
