output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "resource_prefix" {
  value = local.resource_token
}

output "storage_account_name" {
  value = azurerm_storage_account.solution.name
}

output "search_service_name" {
  value = azurerm_search_service.solution.name
}

output "container_registry_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "app_config_endpoint" {
  value = azurerm_app_configuration.this.endpoint
}

output "frontend_url" {
  value = try("https://${azurerm_container_app.frontend.ingress[0].fqdn}", null)
}

output "ai_foundry_account_name" {
  value = local.ai_foundry_account_name
}

output "ai_foundry_project_name" {
  value = local.ai_foundry_project_name
}

output "ai_foundry_account_endpoint" {
  value = local.ai_foundry_account_endpoint
}

output "ai_foundry_project_endpoint" {
  value = "https://${local.ai_foundry_account_name}.services.ai.azure.com/api/projects/${local.ai_foundry_project_name}"
}

output "ai_foundry_workspace_guid" {
  value = local.ai_foundry_project_workspace_guid
}

output "zero_trust_virtual_network_name" {
  value = try(azurerm_virtual_network.this[0].name, null)
}

output "zero_trust_private_endpoint_names" {
  value = keys(azurerm_private_endpoint.this)
}

output "bastion_host_name" {
  value = try(azurerm_bastion_host.this[0].name, null)
}

output "jumpbox_vm_name" {
  value = try(azurerm_windows_virtual_machine.jumpbox[0].name, null)
}

output "jumpbox_private_ip_address" {
  value = try(azurerm_network_interface.jumpbox[0].private_ip_address, null)
}

output "jumpbox_generated_admin_password" {
  value     = try(random_password.jumpbox[0].result, null)
  sensitive = true
}
