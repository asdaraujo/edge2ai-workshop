provider "aws" {
  access_key = var.aws_access_key_id
  secret_key = var.aws_secret_access_key
  region     = var.aws_region
  version = "~> 2.42"
}

provider "null" {
  version = "~> 2.1"
}
