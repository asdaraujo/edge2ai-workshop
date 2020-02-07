variable "cluster_count" {
  description = "Number of clusters to create"
}

variable "deploy_cdsw_model" {
  description = "Whether to deploy the CDSW model during launch or not"
  type        = bool
  default     = true
}

variable "ssh_private_key" {
  description = "SSH private key to connect to AWS instances"
}

variable "ssh_public_key" {
  description = "SSH public key to connect to AWS instances"
}

variable "web_ssh_private_key" {
  description = "SSH private key to connect to the Web Server AWS instances"
}

variable "web_ssh_public_key" {
  description = "SSH public key to connect to the Web Server AWS instances"
}

variable "my_public_ip" {
  description = "Public IP address of the local network"
}

variable "key_name" {
  description = "Name of the SSH Key in AWS"
}

variable "web_key_name" {
  description = "Name of the SSH Key for the Web Server in AWS"
}

variable "owner" {
  description = "Owner user name"
}

variable "aws_region" {
  description = "AWS Region"
}

variable "ssh_username" {
  description = "SSH username to connect to AWS instances"
}

variable "ssh_password" {
  description = "SSH password to connect to AWS instances"
}

variable "base_ami" {
  description = "AWS AMI for the Web Service"
}

variable "cluster_ami" {
  description = "AWS AMI for the CDH cluster"
}

variable "cluster_instance_type" {
  description = "Instance type for the CDH cluster"
}

variable "aws_access_key_id" {
  description = "Abort this with CTRL-C, set the TF_VAR_aws_access_key_id environment variable in your shell and try again."
}

variable "aws_secret_access_key" {
  description = "Abort this with CTRL-C, set the TF_VAR_aws_secret_access_key environment variable in your shell and try again."
}

variable "name_prefix" {
  description = "Name prefix for AWS resources"
}

variable "project" {
  description = "Project name"
}

variable "enddate" {
  description = "Resource expiration date (MMDDYYYY)"
}

variable "namespace" {
  description = "Namespace for the cluster deployment"
}

variable "vpc_id" {
  description = "AWS VPC id"
  default     = ""
}

variable "cidr_block_1" {
  description = "CIDR for subnet 1"
  default     = "10.0.1.0/24"
}

variable "managed_security_group_ids" {
  type    = list(string)
  default = []
}
