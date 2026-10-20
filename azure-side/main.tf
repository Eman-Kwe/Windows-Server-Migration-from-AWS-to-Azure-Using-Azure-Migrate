terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# features {} is required, even when empty. subscription_id says WHERE to build.
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Names built from the suffix, matching the README's naming table.
locals {
  staging_rg_name = "rg-migrate-staging-${var.name_suffix}"
  target_rg_name  = "rg-migrate-target-${var.name_suffix}"
  vnet_name       = "vnet-migrate-${var.name_suffix}"
  storage_name    = "stmigrate${var.name_suffix}" # 3-24 lowercase letters/digits, globally unique
  nsg_name        = "nsg-migrate-target-${var.name_suffix}"
}

# Staging group: holds the migration tooling (storage, network, later the Migrate project).
resource "azurerm_resource_group" "staging" {
  name     = local.staging_rg_name
  location = var.location
  tags     = var.tags
}

# Target group: where the migrated VM will land. Kept separate so the tooling can be
# deleted without touching the migrated VM.
resource "azurerm_resource_group" "target" {
  name     = local.target_rg_name
  location = var.location
  tags     = var.tags
}

# The Azure network the migrated VM joins. 10.1.x.x so it never overlaps AWS's 10.0.x.x.
resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.staging.location
  resource_group_name = azurerm_resource_group.staging.name
  tags                = var.tags
}

resource "azurerm_subnet" "main" {
  name                 = "snet-migrate"
  resource_group_name  = azurerm_resource_group.staging.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.1.0/24"]
}

# Storage account that holds the copied disk data during replication.
resource "azurerm_storage_account" "replication" {
  name                            = local.storage_name
  resource_group_name             = azurerm_resource_group.staging.name
  location                        = azurerm_resource_group.staging.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS" # cheapest: 3 copies in one datacenter
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false # no public blob access
  tags                            = var.tags
}

# Firewall for the migrated VM: RDP from your IP only.
# It is attached to the VM's network interface later, in Step 13.
resource "azurerm_network_security_group" "target" {
  name                = local.nsg_name
  location            = azurerm_resource_group.target.location
  resource_group_name = azurerm_resource_group.target.name
  tags                = var.tags

  security_rule {
    name                       = "allow-rdp-my-ip"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.my_ip_cidr
    destination_address_prefix = "*"
  }
}
