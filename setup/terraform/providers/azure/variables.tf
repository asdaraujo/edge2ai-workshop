variable "cluster_count" {
  description = "Number of clusters to create"
}

variable "launch_web_server" {
  description = "Whether or not to launch the web server"
  default     = true
}

variable "deploy_cdsw_model" {
  description = "Whether to deploy the CDSW model during launch or not"
  type        = bool
  default     = true
}

variable "ssh_private_key" {
  description = "SSH private key to connect to instances"
}

variable "ssh_public_key" {
  description = "SSH public key to connect to instances"
}

variable "web_ssh_private_key" {
  description = "SSH private key to connect to the Web Server instances"
}

variable "web_ssh_public_key" {
  description = "SSH public key to connect to the Web Server instances"
}

variable "my_public_ip" {
  description = "Public IP address of the local network"
}

variable "owner" {
  description = "Owner user name"
}

variable "ssh_username" {
  description = "SSH username to connect to instances"
}

variable "ssh_password" {
  description = "SSH password to connect to instances"
}

variable "cluster_instance_type" {
  description = "Instance type for the CDH cluster"
}

variable "name_prefix" {
  description = "Name prefix for resources"
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

variable "cidr_block_1" {
  description = "CIDR for subnet 1"
  default     = "10.0.1.0/24"
}

variable "extra_cidr_blocks" {
  description = "Extra CIDR blocks to add to security groups"
  type        = list(string)
  default     = []
}

variable "use_ipa" {
  description = "Whether or not to launch an IPA server"
  type        = bool
  default     = false
}

variable "base_dir" {
  description = "Deployment base dir"
  type        = string
}

variable "azure_region" {
  description = "Azure Region"
}

variable "azure_subscription_id" {
  description = "Abort this with CTRL-C, set the TF_VAR_azure_subscription_id environment variable in your shell and try again."
  default = null
}

variable "azure_tenant_id" {
  description = "Abort this with CTRL-C, set the TF_VAR_azure_tenant_id environment variable in your shell and try again."
}

variable "base_image_publisher" {
  description = "Azure image publisher"
}

variable "base_image_offer" {
  description = "Azure image offer"
}

variable "base_image_sku" {
  description = "Azure image SKU"
}

variable "base_image_version" {
  description = "Azure image version"
}

variable "pvc_data_services" {
  description = "Whether or not to deploy PVC Data Services"
  type        = bool
  default     = false
}

variable "cdp_license_file" {
  description = "CDP license file"
  type        = string
  default     = ""
}
