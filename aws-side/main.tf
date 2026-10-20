terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0" # accepts any AWS provider 5.0 or newer
    }
  }
}

# Tells Terraform which cloud and region to talk to. It uses your aws configure login.
provider "aws" {
  region = var.aws_region
}

# Looks up the newest Windows Server 2022 image automatically,
# so you never hard-code an image ID that may not exist in your region.
data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------- Network ----------
# The private network (VPC). All three servers live in it.
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = "vpc-migrate-manuel" })
}

# The door to the internet. Appliances need internet to reach Azure.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "igw-migrate-manuel" })
}

# One subnet. map_public_ip_on_launch gives each server a public IP so you can RDP in.
resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags                    = merge(var.tags, { Name = "snet-migrate-manuel" })
}

# Route table: send all outside traffic (0.0.0.0/0) through the internet gateway.
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(var.tags, { Name = "rt-migrate-manuel" })
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# ---------- Firewalls (security groups) ----------
# Discovery appliance: RDP from your IP only.
resource "aws_security_group" "discovery" {
  name   = "migrate-discovery-sg-manuel"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 3389 # Remote Desktop
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }
  egress { # allow all outbound so it can reach Azure
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Name = "migrate-discovery-sg-manuel" })
}

# Source server: RDP from you, WinRM (5985) from the discovery appliance only.
resource "aws_security_group" "source" {
  name   = "migrate-source-sg-manuel" # AWS rejects names starting with sg-
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }
  ingress {
    from_port       = 5985 # WinRM, used by discovery
    to_port         = 5985
    protocol        = "tcp"
    security_groups = [aws_security_group.discovery.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Name = "migrate-source-sg-manuel" })
}

# Replication appliance: RDP from you, 443 and 9443 from the source server only.
resource "aws_security_group" "replication" {
  name   = "migrate-replication-sg-manuel"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }
  ingress {
    from_port       = 443 # Mobility service management traffic
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.source.id]
  }
  ingress {
    from_port       = 9443 # replication data
    to_port         = 9443
    protocol        = "tcp"
    security_groups = [aws_security_group.source.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Name = "migrate-replication-sg-manuel" })
}

# ---------- Servers ----------
# The Windows Server being migrated. user_data runs once at first boot:
# it sets the Administrator password and turns on WinRM so discovery can connect.
resource "aws_instance" "source" {
  ami                    = data.aws_ami.windows_2022.id
  instance_type          = var.source_instance_type
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.source.id]
  user_data              = <<-EOT
    <powershell>
    net user Administrator "${var.admin_password}"
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    </powershell>
  EOT
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }
  tags = merge(var.tags, { Name = "ec2-migrate-source-manuel" })
}

# Discovery appliance: finds and describes the source server for Azure.
resource "aws_instance" "discovery" {
  ami                    = data.aws_ami.windows_2022.id
  instance_type          = var.discovery_instance_type
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.discovery.id]
  user_data              = <<-EOT
    <powershell>
    net user Administrator "${var.admin_password}"
    </powershell>
  EOT
  root_block_device {
    volume_size = 100 # Microsoft says about 80 GB
    volume_type = "gp3"
  }
  tags = merge(var.tags, { Name = "ec2-migrate-discovery-manuel" })
}

# Replication appliance: receives disk changes and uploads them to Azure.
# The extra disk is the 300 GB cache. You initialize it inside Windows later.
resource "aws_instance" "replication" {
  ami                    = data.aws_ami.windows_2022.id
  instance_type          = var.replication_instance_type
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.replication.id]
  user_data              = <<-EOT
    <powershell>
    net user Administrator "${var.admin_password}"
    </powershell>
  EOT
  root_block_device {
    volume_size = 100
    volume_type = "gp3"
  }
  ebs_block_device {
    device_name = "xvdf"
    volume_size = var.replication_cache_gb
    volume_type = "gp3"
  }
  tags = merge(var.tags, { Name = "ec2-migrate-replication-manuel" })
}
