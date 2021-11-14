provider "aws" {
  profile                 = var.aws_profile
  shared_credentials_file = "~/.aws/credentials"
  access_key              = var.aws_access_key_id
  secret_key              = var.aws_secret_access_key
  region                  = var.aws_region
}

provider "null" {
}
