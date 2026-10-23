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
  default = "c5.4xlarge" # 16 vCPU = 8 physical cores, 32 GB: the appliance check counts cores, not vCPUs
}

# Extra disk the replication appliance uses to cache data. The simplified appliance's
# DRInstaller.ps1 aborts unless at least 600 GB is free, and Microsoft's docs list a 620 GB data disk.
variable "replication_cache_gb" {
  type    = number
  default = 620
}

# Tags attached to every resource, so you can find and delete lab resources later.
variable "tags" {
  type = map(string)
  default = {
    project    = "azure-migrate-lab"
    owner      = "kweku"
    managed_by = "terraform"
  }
}
