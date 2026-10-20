output "staging_resource_group" { value = azurerm_resource_group.staging.name }
output "target_resource_group" { value = azurerm_resource_group.target.name }
output "vnet_name" { value = azurerm_virtual_network.main.name }
output "subnet_name" { value = azurerm_subnet.main.name }
output "storage_account_name" { value = azurerm_storage_account.replication.name }
output "nsg_name" { value = azurerm_network_security_group.target.name }
