# Your Azure subscription ID. The Azure provider (v4) requires it. Goes in terraform.tfvars.
variable "subscription_id" {
  type = string
}

# Azure region. The README uses East US.
variable "location" {
  type    = string
  default = "eastus"
}

# Used in every resource name, so names match the README (for example rg-migrate-staging-kweku).
# Change it only if the storage account name is already taken.
variable "name_suffix" {
  type    = string
  default = "kweku"
}

# Your public IP with /32. Only this address may Remote Desktop into the migrated VM.
variable "my_ip_cidr" {
  type = string
}

variable "tags" {
  type = map(string)
  default = {
    project    = "azure-migrate-lab"
    owner      = "kweku"
    managed_by = "terraform"
  }
}
