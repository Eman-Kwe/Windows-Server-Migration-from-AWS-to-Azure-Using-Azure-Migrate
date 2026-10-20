# Region to build in. The README uses us-east-1.
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# Your public IP with /32 (meaning "exactly this one address").
# Only this address may use Remote Desktop. No default, so Terraform needs a value.
variable "my_ip_cidr" {
  type = string
}

# Windows Administrator password. sensitive = true hides it in Terraform output.
variable "admin_password" {
  type      = string
  sensitive = true
}

# Server sizes. Appliance sizes follow Microsoft's documented requirements.
variable "source_instance_type" {
  type    = string
  default = "t3.medium" # 2 vCPU, 4 GB: the server being migrated
}

variable "discovery_instance_type" {
  type    = string
  default = "m5.2xlarge" # 8 vCPU, 32 GB: Microsoft's requirement for the discovery appliance
}

variable "replication_instance_type" {
  type    = string
  default = "c5.2xlarge" # 8 vCPU, 16 GB: Microsoft's minimum for the replication appliance
}

# Extra disk the replication appliance uses to cache data. Microsoft's table says 300 GB.
variable "replication_cache_gb" {
  type    = number
  default = 300
}

# Tags attached to every resource, so you can find and delete lab resources later.
variable "tags" {
  type = map(string)
  default = {
    project    = "azure-migrate-lab"
    owner      = "manuel"
    managed_by = "terraform"
  }
}
