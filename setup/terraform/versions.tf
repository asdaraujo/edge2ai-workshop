
terraform {
  required_version = ">= 0.12"

  required_providers {
    aws = {
      source  = "registry.terraform.io/hashicorp/aws"
      version = "~> 3.53"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 2.1"
    }
  }

}
