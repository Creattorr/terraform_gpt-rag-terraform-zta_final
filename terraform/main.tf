data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "random_password" "jumpbox" {
  count            = var.enable_zero_trust && var.enable_jumpbox && var.jumpbox_admin_password == null ? 1 : 0
  length           = 24
  special          = true
  override_special = "!#$%*()-_=+[]{}:?"
}

resource "random_password" "container_app_api_token" {
  count   = var.container_app_api_token == null ? 1 : 0
  length  = 48
  special = false
}

locals {
  gpt_rag_release = "2.1.2"
  resource_token  = lower("${var.environment_name}${random_string.suffix.result}")

  prefix = replace(local.resource_token, "/[^0-9a-z]/", "")

  tags = merge({
    workload   = "gpt-rag"
    managed-by = "terraform"
    reference  = "Azure/GPT-RAG release/2.1.2"
  }, var.tags)

  deployment_name = "terraform-${local.prefix}"

  # Core solution resource names
  solution_storage_account_name = "st${local.prefix}"
  solution_search_service_name  = "srch-${local.prefix}"
  app_config_name               = "appcs-${local.prefix}"
  app_insights_name             = "appi-${local.prefix}"
  log_analytics_name            = "log-${local.prefix}"
  container_env_name            = "cae-${local.prefix}"
  container_registry_name       = "cr${local.prefix}"
  key_vault_name                = "kv-${local.prefix}"
  cosmos_account_name           = "cosmos-${local.prefix}"
  cosmos_database_name          = "gptragdb"
  virtual_network_name          = "vnet-${local.prefix}"
  container_apps_subnet_name    = "snet-${local.prefix}-containerapps"
  ai_foundry_agent_subnet_name  = "snet-${local.prefix}-ai-agents"
  private_endpoints_subnet_name = "snet-${local.prefix}-private-endpoints"
  management_subnet_name        = "snet-${local.prefix}-management"
  bastion_subnet_name           = "AzureBastionSubnet"
  bastion_public_ip_name        = "pip-${local.prefix}-bastion"
  bastion_host_name             = "bas-${local.prefix}"
  jumpbox_nsg_name              = "nsg-${local.prefix}-jumpbox"
  jumpbox_nic_name              = "nic-${local.prefix}-jumpbox"
  jumpbox_vm_name               = "vm-${local.prefix}-jumpbox"
  jumpbox_computer_name         = substr("testvm${local.prefix}", 0, 15)
  jumpbox_nat_public_ip_name    = "pip-nat-${local.prefix}"
  jumpbox_nat_gateway_name      = "nat-${local.prefix}"
  jumpbox_admin_password        = var.jumpbox_admin_password != null ? var.jumpbox_admin_password : try(random_password.jumpbox[0].result, null)
  container_app_api_token       = var.container_app_api_token != null ? var.container_app_api_token : random_password.container_app_api_token[0].result

  # AI Foundry names
  ai_foundry_name_suffix          = trimspace(var.ai_foundry_rebuild_suffix) == "" ? "" : "-${replace(lower(trimspace(var.ai_foundry_rebuild_suffix)), "/[^0-9a-z-]/", "")}"
  ai_foundry_account_name         = "aif-${local.prefix}${local.ai_foundry_name_suffix}"
  ai_foundry_project_name         = "proj-${local.prefix}${local.ai_foundry_name_suffix}"
  ai_foundry_project_display_name = "proj-${local.prefix}${local.ai_foundry_name_suffix}"
  ai_foundry_project_description  = "proj-${local.prefix}${local.ai_foundry_name_suffix} Project"
  ai_foundry_account_cap_host     = "caphostacc"
  ai_foundry_project_cap_host     = "caphostproj"
  ai_foundry_storage_name         = "staif${local.prefix}"
  ai_foundry_search_name          = "srch-aif-${local.prefix}"
  ai_foundry_cosmos_name          = "cosmos-aif-${local.prefix}"
  cosmos_sql_data_contributor_id  = "00000000-0000-0000-0000-000000000002"
  search_location                 = coalesce(var.search_location, var.location)

  private_dns_zones = var.enable_zero_trust ? toset([
    "privatelink.azconfig.io",
    "privatelink.azurecr.io",
    "privatelink.blob.core.windows.net",
    "privatelink.cognitiveservices.azure.com",
    "privatelink.documents.azure.com",
    "privatelink.openai.azure.com",
    "privatelink.search.windows.net",
    "privatelink.vaultcore.azure.net"
  ]) : toset([])

  private_endpoints = var.enable_zero_trust ? {
    solution_blob = {
      name        = "pe-${local.prefix}-st-blob"
      resource_id = azurerm_storage_account.solution.id
      group_ids   = ["blob"]
      dns_zones   = ["privatelink.blob.core.windows.net"]
    }
    ai_foundry_blob = {
      name        = "pe-${local.prefix}-aif-st-blob"
      resource_id = azurerm_storage_account.ai_foundry.id
      group_ids   = ["blob"]
      dns_zones   = ["privatelink.blob.core.windows.net"]
    }
    solution_search = {
      name        = "pe-${local.prefix}-search"
      resource_id = azurerm_search_service.solution.id
      group_ids   = ["searchService"]
      dns_zones   = ["privatelink.search.windows.net"]
    }
    ai_foundry_search = {
      name        = "pe-${local.prefix}-aif-search"
      resource_id = azurerm_search_service.ai_foundry.id
      group_ids   = ["searchService"]
      dns_zones   = ["privatelink.search.windows.net"]
    }
    app_config = {
      name        = "pe-${local.prefix}-appconfig"
      resource_id = azurerm_app_configuration.this.id
      group_ids   = ["configurationStores"]
      dns_zones   = ["privatelink.azconfig.io"]
    }
    key_vault = {
      name        = "pe-${local.prefix}-kv"
      resource_id = azurerm_key_vault.this.id
      group_ids   = ["vault"]
      dns_zones   = ["privatelink.vaultcore.azure.net"]
    }
    acr = {
      name        = "pe-${local.prefix}-acr"
      resource_id = azurerm_container_registry.this.id
      group_ids   = ["registry"]
      dns_zones   = ["privatelink.azurecr.io"]
    }
    solution_cosmos = {
      name        = "pe-${local.prefix}-cosmos"
      resource_id = azurerm_cosmosdb_account.solution.id
      group_ids   = ["Sql"]
      dns_zones   = ["privatelink.documents.azure.com"]
    }
    ai_foundry_cosmos = {
      name        = "pe-${local.prefix}-aif-cosmos"
      resource_id = azurerm_cosmosdb_account.ai_foundry.id
      group_ids   = ["Sql"]
      dns_zones   = ["privatelink.documents.azure.com"]
    }
    ai_foundry_account = {
      name        = "pe-${local.prefix}-aif-account${local.ai_foundry_name_suffix}"
      resource_id = azapi_resource.ai_foundry_account.id
      group_ids   = ["account"]
      dns_zones = [
        "privatelink.cognitiveservices.azure.com",
        "privatelink.openai.azure.com"
      ]
    }
  } : {}

  container_app_specs = [
    {
      service_name   = "orchestrator"
      name           = "ca-${local.prefix}-orchestrator"
      canonical_name = "ORCHESTRATOR_APP"
      image          = var.orchestrator_image
      target_port    = 80
      external       = true
      min_replicas   = 1
      max_replicas   = 1
      identity_id    = azurerm_user_assigned_identity.orchestrator.id
      identity_pid   = azurerm_user_assigned_identity.orchestrator.principal_id
      identity_cid   = azurerm_user_assigned_identity.orchestrator.client_id
    },
    {
      service_name   = "frontend"
      name           = "ca-${local.prefix}-frontend"
      canonical_name = "FRONTEND_APP"
      image          = var.frontend_image
      target_port    = 80
      external       = true
      min_replicas   = 1
      max_replicas   = 1
      identity_id    = azurerm_user_assigned_identity.frontend.id
      identity_pid   = azurerm_user_assigned_identity.frontend.principal_id
      identity_cid   = azurerm_user_assigned_identity.frontend.client_id
    },
    {
      service_name   = "dataingest"
      name           = "ca-${local.prefix}-dataingest"
      canonical_name = "DATA_INGEST_APP"
      image          = var.dataingest_image
      target_port    = 80
      external       = true
      min_replicas   = 1
      max_replicas   = 1
      identity_id    = azurerm_user_assigned_identity.dataingest.id
      identity_pid   = azurerm_user_assigned_identity.dataingest.principal_id
      identity_cid   = azurerm_user_assigned_identity.dataingest.client_id
    },
    {
      service_name   = "mcp"
      name           = "ca-${local.prefix}-mcp"
      canonical_name = "MCP_APP"
      image          = var.mcp_image
      target_port    = 80
      external       = true
      min_replicas   = 1
      max_replicas   = 1
      identity_id    = azurerm_user_assigned_identity.mcp.id
      identity_pid   = azurerm_user_assigned_identity.mcp.principal_id
      identity_cid   = azurerm_user_assigned_identity.mcp.client_id
    }
  ]

  model_deployments = [
    {
      name           = "chat"
      model          = var.chat_model_name
      modelFormat    = "OpenAI"
      type           = "GlobalStandard"
      version        = var.chat_model_version
      apiVersion     = "2025-01-01-preview"
      capacity       = var.chat_model_capacity
      canonical_name = "CHAT_DEPLOYMENT_NAME"
    },
    {
      name           = "text-embedding"
      model          = var.embedding_model_name
      modelFormat    = "OpenAI"
      type           = "Standard"
      version        = var.embedding_model_version
      apiVersion     = "2025-01-01-preview"
      capacity       = var.embedding_model_capacity
      canonical_name = "EMBEDDING_DEPLOYMENT_NAME"
    }
  ]

  rai_content_filters = [
    {
      name              = "hate"
      blocking          = true
      enabled           = true
      severityThreshold = "Medium"
      source            = "Prompt"
    },
    {
      name              = "sexual"
      blocking          = true
      enabled           = true
      severityThreshold = "Medium"
      source            = "Prompt"
    },
    {
      name              = "selfharm"
      blocking          = true
      enabled           = true
      severityThreshold = "Medium"
      source            = "Prompt"
    },
    {
      name              = "violence"
      blocking          = true
      enabled           = true
      severityThreshold = "Medium"
      source            = "Prompt"
    },
    {
      name              = "hate"
      blocking          = true
      enabled           = true
      severityThreshold = "Medium"
      source            = "Completion"
    },
    {
      name              = "sexual"
      blocking          = true
      enabled           = true
      severityThreshold = "Medium"
      source            = "Completion"
    },
    {
      name              = "selfharm"
      blocking          = true
      enabled           = true
      severityThreshold = "Medium"
      source            = "Completion"
    },
    {
      name              = "violence"
      blocking          = true
      enabled           = true
      severityThreshold = "Medium"
      source            = "Completion"
    },
    {
      name     = "jailbreak"
      blocking = false
      enabled  = false
      source   = "Prompt"
    },
    {
      name     = "protected_material_text"
      blocking = false
      enabled  = false
      source   = "Completion"
    },
    {
      name     = "protected_material_code"
      blocking = false
      enabled  = false
      source   = "Completion"
    }
  ]

  rai_custom_blocklists = [
    {
      blocking      = true
      blocklistName = var.rai_blocklist_name
      source        = "Prompt"
    },
    {
      blocking      = true
      blocklistName = var.rai_blocklist_name
      source        = "Completion"
    }
  ]

  nonempty_rai_blocklist_items = {
    for idx, item in var.rai_blocklist_items :
    "${var.rai_blocklist_name}Item${idx}" => item
    if trimspace(item.pattern) != ""
  }
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = local.app_insights_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = local.tags
}

resource "azurerm_virtual_network" "this" {
  count               = var.enable_zero_trust ? 1 : 0
  name                = local.virtual_network_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.zero_trust_address_space
  tags                = local.tags
}

resource "azurerm_subnet" "container_apps" {
  count                           = var.enable_zero_trust ? 1 : 0
  name                            = local.container_apps_subnet_name
  resource_group_name             = azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this[0].name
  address_prefixes                = [var.container_apps_subnet_address_prefix]
  service_endpoints               = ["Microsoft.AzureCosmosDB", "Microsoft.CognitiveServices"]
  default_outbound_access_enabled = false

  delegation {
    name = "container-apps-environments"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "ai_foundry_agents" {
  count                           = var.enable_zero_trust ? 1 : 0
  name                            = local.ai_foundry_agent_subnet_name
  resource_group_name             = azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this[0].name
  address_prefixes                = [var.ai_foundry_agent_subnet_address_prefix]
  service_endpoints               = ["Microsoft.AzureCosmosDB", "Microsoft.CognitiveServices"]
  default_outbound_access_enabled = false

  delegation {
    name = "Microsoft.App.environments"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  count                             = var.enable_zero_trust ? 1 : 0
  name                              = local.private_endpoints_subnet_name
  resource_group_name               = azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this[0].name
  address_prefixes                  = [var.private_endpoints_subnet_address_prefix]
  service_endpoints                 = ["Microsoft.AzureCosmosDB"]
  private_endpoint_network_policies = "Disabled"
  default_outbound_access_enabled   = false
}

resource "azurerm_subnet" "management" {
  count                           = var.enable_zero_trust ? 1 : 0
  name                            = local.management_subnet_name
  resource_group_name             = azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this[0].name
  address_prefixes                = [var.management_subnet_address_prefix]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "bastion" {
  count                           = var.enable_zero_trust && var.enable_bastion ? 1 : 0
  name                            = local.bastion_subnet_name
  resource_group_name             = azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this[0].name
  address_prefixes                = [var.bastion_subnet_address_prefix]
  default_outbound_access_enabled = false
}

resource "azurerm_network_security_group" "jumpbox" {
  count               = var.enable_zero_trust && var.enable_jumpbox ? 1 : 0
  name                = local.jumpbox_nsg_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  security_rule {
    name                       = "AllowRdpFromVirtualNetwork"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "management" {
  count                     = var.enable_zero_trust && var.enable_jumpbox ? 1 : 0
  subnet_id                 = azurerm_subnet.management[0].id
  network_security_group_id = azurerm_network_security_group.jumpbox[0].id
}

resource "azurerm_public_ip" "jumpbox_nat" {
  count               = var.enable_zero_trust && var.enable_jumpbox && var.enable_jumpbox_nat_gateway ? 1 : 0
  name                = local.jumpbox_nat_public_ip_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags

  lifecycle {
    ignore_changes = [
      ip_tags,
      zones
    ]
  }
}

resource "azurerm_nat_gateway" "jumpbox" {
  count               = var.enable_zero_trust && var.enable_jumpbox && var.enable_jumpbox_nat_gateway ? 1 : 0
  name                = local.jumpbox_nat_gateway_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "jumpbox" {
  count                = var.enable_zero_trust && var.enable_jumpbox && var.enable_jumpbox_nat_gateway ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.jumpbox[0].id
  public_ip_address_id = azurerm_public_ip.jumpbox_nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "management" {
  count          = var.enable_zero_trust && var.enable_jumpbox && var.enable_jumpbox_nat_gateway ? 1 : 0
  subnet_id      = azurerm_subnet.management[0].id
  nat_gateway_id = azurerm_nat_gateway.jumpbox[0].id
}

resource "azurerm_private_dns_zone" "this" {
  for_each            = local.private_dns_zones
  name                = each.key
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each              = azurerm_private_dns_zone.this
  name                  = "link-${local.prefix}-${replace(replace(each.key, "privatelink.", ""), ".", "-")}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.this[0].id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_dns_zone" "services_ai" {
  count               = var.enable_zero_trust ? 1 : 0
  name                = "privatelink.services.ai.azure.com"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "services_ai" {
  count                 = var.enable_zero_trust ? 1 : 0
  name                  = "link-${local.prefix}-services-ai-azure-com"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.services_ai[0].name
  virtual_network_id    = azurerm_virtual_network.this[0].id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_endpoint" "this" {
  for_each            = local.private_endpoints
  name                = each.value.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints[0].id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${each.value.name}"
    private_connection_resource_id = each.value.resource_id
    subresource_names              = each.value.group_ids
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [for zone in each.value.dns_zones : azurerm_private_dns_zone.this[zone].id]
  }
}

resource "azurerm_private_dns_a_record" "ai_foundry_services_ai" {
  count               = var.enable_zero_trust ? 1 : 0
  name                = local.ai_foundry_account_name
  zone_name           = azurerm_private_dns_zone.services_ai[0].name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 3600
  records             = [azurerm_private_endpoint.this["ai_foundry_account"].private_service_connection[0].private_ip_address]
  tags                = local.tags
}

resource "azurerm_public_ip" "bastion" {
  count               = var.enable_zero_trust && var.enable_bastion ? 1 : 0
  name                = local.bastion_public_ip_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags

  lifecycle {
    ignore_changes = [
      ip_tags,
      zones
    ]
  }
}

resource "azurerm_bastion_host" "this" {
  count               = var.enable_zero_trust && var.enable_bastion ? 1 : 0
  name                = local.bastion_host_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Basic"
  tags                = local.tags

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}

resource "azurerm_network_interface" "jumpbox" {
  count               = var.enable_zero_trust && var.enable_jumpbox ? 1 : 0
  name                = local.jumpbox_nic_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.management[0].id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "jumpbox" {
  count               = var.enable_zero_trust && var.enable_jumpbox ? 1 : 0
  name                = local.jumpbox_vm_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  size                = var.jumpbox_vm_size
  computer_name       = local.jumpbox_computer_name
  admin_username      = var.jumpbox_admin_username
  admin_password      = local.jumpbox_admin_password
  network_interface_ids = [
    azurerm_network_interface.jumpbox[0].id
  ]
  provision_vm_agent                                     = true
  patch_mode                                             = "AutomaticByPlatform"
  patch_assessment_mode                                  = "AutomaticByPlatform"
  bypass_platform_safety_checks_on_user_schedule_enabled = true
  tags                                                   = local.tags

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    disk_size_gb         = 250
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "microsoft-dsvm"
    offer     = "dsvm-win-2022"
    sku       = "winserver-2022"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "jumpbox_software" {
  count                      = var.enable_zero_trust && var.enable_jumpbox && var.deploy_jumpbox_software ? 1 : 0
  name                       = "cse"
  virtual_machine_id         = azurerm_windows_virtual_machine.jumpbox[0].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  tags                       = local.tags

  settings = jsonencode({
    fileUris = [
      "https://raw.githubusercontent.com/Azure/GPT-RAG/refs/tags/v${local.gpt_rag_release}/infra/install.ps1"
    ]
    commandToExecute = join(" ", [
      "powershell.exe -ExecutionPolicy Unrestricted -File install.ps1",
      "-release release/${local.gpt_rag_release}",
      "-UseUAI false",
      "-ResourceToken ${local.prefix}",
      "-AzureTenantId ${var.tenant_id}",
      "-AzureLocation ${azurerm_resource_group.this.location}",
      "-AzureSubscriptionId ${var.subscription_id}",
      "-AzureResourceGroupName ${azurerm_resource_group.this.name}",
      "-AzdEnvName ${var.environment_name};",
      "powershell.exe -ExecutionPolicy Bypass -Command",
      "\"$ErrorActionPreference='Continue';",
      "$storage='${azurerm_storage_account.solution.name}';",
      "$container='${var.jumpbox_workspace_container_name}';",
      "$blob='${var.jumpbox_workspace_blob_name}';",
      "$destination='${replace(var.jumpbox_workspace_destination, "\\", "\\\\")}';",
      "$zip='C:\\\\WindowsAzure\\\\Logs\\\\${var.jumpbox_workspace_blob_name}';",
      "az login --identity | Out-Null;",
      "$exists=az storage blob exists --account-name $storage --container-name $container --name $blob --auth-mode login --query exists -o tsv;",
      "choco install terraform -y --ignoredetectedreboot --force;",
      "if ($exists -eq 'true') {",
      "New-Item -ItemType Directory -Force -Path (Split-Path $zip) | Out-Null;",
      "New-Item -ItemType Directory -Force -Path $destination | Out-Null;",
      "az storage blob download --account-name $storage --container-name $container --name $blob --file $zip --auth-mode login --overwrite true | Out-Null;",
      "Expand-Archive -Path $zip -DestinationPath $destination -Force;",
      "Write-Host \\\"Workspace synced to $destination\\\"",
      "} else { Write-Host 'Workspace package not found; skipping sync.' }\""
    ])
  })
}

resource "azurerm_role_assignment" "jumpbox_resource_group_reader" {
  count                = var.enable_zero_trust && var.enable_jumpbox ? 1 : 0
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Reader"
  principal_id         = azurerm_windows_virtual_machine.jumpbox[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "jumpbox_storage_blob_data_contributor" {
  count                = var.enable_zero_trust && var.enable_jumpbox ? 1 : 0
  scope                = azurerm_storage_account.solution.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_windows_virtual_machine.jumpbox[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "jumpbox_search_service_contributor" {
  count                = var.enable_zero_trust && var.enable_jumpbox ? 1 : 0
  scope                = azurerm_search_service.solution.id
  role_definition_name = "Search Service Contributor"
  principal_id         = azurerm_windows_virtual_machine.jumpbox[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "jumpbox_search_index_data_contributor" {
  count                = var.enable_zero_trust && var.enable_jumpbox ? 1 : 0
  scope                = azurerm_search_service.solution.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azurerm_windows_virtual_machine.jumpbox[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "jumpbox_appconfig_data_owner" {
  count                = var.enable_zero_trust && var.enable_jumpbox ? 1 : 0
  scope                = azurerm_app_configuration.this.id
  role_definition_name = "App Configuration Data Owner"
  principal_id         = azurerm_windows_virtual_machine.jumpbox[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "jumpbox_acr_push" {
  count                = var.enable_zero_trust && var.enable_jumpbox ? 1 : 0
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_windows_virtual_machine.jumpbox[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "jumpbox_key_vault_secrets_user" {
  count                = var.enable_zero_trust && var.enable_jumpbox ? 1 : 0
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_windows_virtual_machine.jumpbox[0].identity[0].principal_id
}

resource "azurerm_storage_account" "solution" {
  name                            = local.solution_storage_account_name
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  public_network_access_enabled   = !var.disable_public_network_access
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}

resource "azurerm_storage_container" "solution_documents_images" {
  name                  = "documents-images"
  storage_account_id    = azurerm_storage_account.solution.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "solution_documents" {
  name                  = "documents"
  storage_account_id    = azurerm_storage_account.solution.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "solution_nl2sql" {
  name                  = "nl2sql"
  storage_account_id    = azurerm_storage_account.solution.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "jumpbox_workspace" {
  name                  = var.jumpbox_workspace_container_name
  storage_account_id    = azurerm_storage_account.solution.id
  container_access_type = "private"
}

resource "azurerm_search_service" "solution" {
  name                          = local.solution_search_service_name
  resource_group_name           = azurerm_resource_group.this.name
  location                      = local.search_location
  sku                           = var.search_sku
  local_authentication_enabled  = true
  authentication_failure_mode   = "http401WithBearerChallenge"
  public_network_access_enabled = !var.disable_public_network_access
  tags                          = local.tags
}

resource "azurerm_container_registry" "this" {
  name                          = local.container_registry_name
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  sku                           = var.enable_zero_trust ? "Premium" : "Basic"
  admin_enabled                 = false
  public_network_access_enabled = !var.disable_public_network_access
  tags                          = local.tags
}

resource "azurerm_app_configuration" "this" {
  name                  = local.app_config_name
  resource_group_name   = azurerm_resource_group.this.name
  location              = azurerm_resource_group.this.location
  sku                   = "standard"
  local_auth_enabled    = true
  public_network_access = var.disable_public_network_access ? "Disabled" : null
  tags                  = local.tags
}

resource "azurerm_key_vault" "this" {
  name                          = local.key_vault_name
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false
  public_network_access_enabled = !var.disable_public_network_access
  rbac_authorization_enabled    = true
  tags                          = local.tags
}

resource "azurerm_cosmosdb_account" "solution" {
  name                              = local.cosmos_account_name
  location                          = azurerm_resource_group.this.location
  resource_group_name               = azurerm_resource_group.this.name
  offer_type                        = var.cosmos_offer_type
  kind                              = "GlobalDocumentDB"
  local_authentication_disabled     = true
  public_network_access_enabled     = !var.disable_public_network_access
  is_virtual_network_filter_enabled = var.enable_zero_trust

  dynamic "virtual_network_rule" {
    for_each = var.enable_zero_trust ? [
      azurerm_subnet.private_endpoints[0].id,
      azurerm_subnet.container_apps[0].id
    ] : []

    content {
      id                                   = virtual_network_rule.value
      ignore_missing_vnet_service_endpoint = true
    }
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.this.location
    failover_priority = 0
  }

  capabilities {
    name = "EnableServerless"
  }

  tags = local.tags
}

resource "azurerm_cosmosdb_sql_database" "solution" {
  name                = local.cosmos_database_name
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.solution.name
}

resource "azurerm_cosmosdb_sql_container" "conversations" {
  name                = "conversations"
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.solution.name
  database_name       = azurerm_cosmosdb_sql_database.solution.name
  partition_key_paths = ["/partitionKey"]
}

resource "azurerm_cosmosdb_sql_container" "datasources" {
  name                = "datasources"
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.solution.name
  database_name       = azurerm_cosmosdb_sql_database.solution.name
  partition_key_paths = ["/partitionKey"]
}

resource "azurerm_cosmosdb_sql_container" "prompts" {
  name                = "prompts"
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.solution.name
  database_name       = azurerm_cosmosdb_sql_database.solution.name
  partition_key_paths = ["/partitionKey"]
}

resource "azurerm_cosmosdb_sql_container" "mcp" {
  name                = "mcp"
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.solution.name
  database_name       = azurerm_cosmosdb_sql_database.solution.name
  partition_key_paths = ["/partitionKey"]
}

# AI Foundry dependent resources
resource "azurerm_storage_account" "ai_foundry" {
  name                            = local.ai_foundry_storage_name
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  public_network_access_enabled   = !var.disable_public_network_access
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}

resource "azurerm_search_service" "ai_foundry" {
  name                          = local.ai_foundry_search_name
  resource_group_name           = azurerm_resource_group.this.name
  location                      = local.search_location
  sku                           = "standard"
  local_authentication_enabled  = true
  authentication_failure_mode   = "http401WithBearerChallenge"
  public_network_access_enabled = !var.disable_public_network_access
  tags                          = local.tags
}

resource "azurerm_cosmosdb_account" "ai_foundry" {
  name                              = local.ai_foundry_cosmos_name
  location                          = azurerm_resource_group.this.location
  resource_group_name               = azurerm_resource_group.this.name
  offer_type                        = var.cosmos_offer_type
  kind                              = "GlobalDocumentDB"
  local_authentication_disabled     = true
  public_network_access_enabled     = !var.disable_public_network_access
  is_virtual_network_filter_enabled = false

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.this.location
    failover_priority = 0
  }

  capabilities {
    name = "EnableServerless"
  }

  tags = local.tags
}

resource "azurerm_user_assigned_identity" "frontend" {
  name                = "id-${local.prefix}-frontend"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "orchestrator" {
  name                = "id-${local.prefix}-orchestrator"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "dataingest" {
  name                = "id-${local.prefix}-dataingest"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "mcp" {
  name                = "id-${local.prefix}-mcp"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "executor" {
  name                = "id-${local.prefix}-executor"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_container_app_environment" "this" {
  name                           = local.container_env_name
  location                       = azurerm_resource_group.this.location
  resource_group_name            = azurerm_resource_group.this.name
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  infrastructure_subnet_id       = var.enable_container_apps_private_environment ? azurerm_subnet.container_apps[0].id : null
  internal_load_balancer_enabled = var.enable_container_apps_private_environment ? true : null
  public_network_access          = var.enable_container_apps_private_environment ? "Disabled" : null
  tags                           = local.tags

  lifecycle {
    ignore_changes = [
      infrastructure_resource_group_name
    ]
  }

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
    minimum_count         = 0
    maximum_count         = 0
  }
}

resource "azurerm_private_dns_zone" "container_apps_environment" {
  count               = var.enable_container_apps_private_environment ? 1 : 0
  name                = azurerm_container_app_environment.this.default_domain
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "container_apps_environment" {
  count                 = var.enable_container_apps_private_environment ? 1 : 0
  name                  = "link-${local.prefix}-containerapps-default-domain"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.container_apps_environment[0].name
  virtual_network_id    = azurerm_virtual_network.this[0].id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_dns_a_record" "container_apps_environment_wildcard" {
  count               = var.enable_container_apps_private_environment ? 1 : 0
  name                = "*"
  zone_name           = azurerm_private_dns_zone.container_apps_environment[0].name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 3600
  records             = [azurerm_container_app_environment.this.static_ip_address]
  tags                = local.tags
}

resource "azurerm_container_app" "frontend" {
  name                         = local.container_app_specs[1].name
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"
  workload_profile_name        = var.enable_container_apps_private_environment ? "Consumption" : null

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.frontend.id]
  }

  registry {
    server   = azurerm_container_registry.this.login_server
    identity = azurerm_user_assigned_identity.frontend.id
  }

  ingress {
    external_enabled = !var.container_apps_internal_only
    target_port      = 80
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name    = "frontend"
      image   = var.frontend_image
      cpu     = var.container_app_cpu
      memory  = var.container_app_memory
      command = []
      args    = []

      env {
        name  = "APP_CONFIG_ENDPOINT"
        value = azurerm_app_configuration.this.endpoint
      }

      env {
        name  = "AZURE_TENANT_ID"
        value = var.tenant_id
      }

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.frontend.client_id
      }

      env {
        name  = "ORCHESTRATOR_BASE_URL"
        value = "https://${azurerm_container_app.orchestrator.ingress[0].fqdn}"
      }

      env {
        name  = "DAPR_API_TOKEN"
        value = local.container_app_api_token
      }
    }
  }

  tags = local.tags
}

resource "azurerm_container_app" "orchestrator" {
  name                         = local.container_app_specs[0].name
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"
  workload_profile_name        = var.enable_container_apps_private_environment ? "Consumption" : null

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.orchestrator.id]
  }

  registry {
    server   = azurerm_container_registry.this.login_server
    identity = azurerm_user_assigned_identity.orchestrator.id
  }

  ingress {
    external_enabled = !var.container_apps_internal_only
    target_port      = 80
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name    = "orchestrator"
      image   = var.orchestrator_image
      cpu     = var.container_app_cpu
      memory  = var.container_app_memory
      command = []
      args    = []

      env {
        name  = "APP_CONFIG_ENDPOINT"
        value = azurerm_app_configuration.this.endpoint
      }

      env {
        name  = "AZURE_TENANT_ID"
        value = var.tenant_id
      }

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.orchestrator.client_id
      }

      env {
        name  = "APP_API_TOKEN"
        value = local.container_app_api_token
      }
    }
  }

  tags = local.tags
}

resource "azurerm_container_app" "dataingest" {
  name                         = local.container_app_specs[2].name
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"
  workload_profile_name        = var.enable_container_apps_private_environment ? "Consumption" : null

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.dataingest.id]
  }

  registry {
    server   = azurerm_container_registry.this.login_server
    identity = azurerm_user_assigned_identity.dataingest.id
  }

  ingress {
    external_enabled = !var.container_apps_internal_only
    target_port      = 80
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name    = "dataingest"
      image   = var.dataingest_image
      cpu     = var.container_app_cpu
      memory  = var.container_app_memory
      command = []
      args    = []

      env {
        name  = "APP_CONFIG_ENDPOINT"
        value = azurerm_app_configuration.this.endpoint
      }

      env {
        name  = "AZURE_TENANT_ID"
        value = var.tenant_id
      }

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.dataingest.client_id
      }
    }
  }

  tags = local.tags
}

resource "azurerm_container_app" "mcp" {
  name                         = local.container_app_specs[3].name
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"
  workload_profile_name        = var.enable_container_apps_private_environment ? "Consumption" : null

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.mcp.id]
  }

  registry {
    server   = azurerm_container_registry.this.login_server
    identity = azurerm_user_assigned_identity.mcp.id
  }

  ingress {
    external_enabled = !var.container_apps_internal_only
    target_port      = 80
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name    = "mcp"
      image   = var.mcp_image
      cpu     = var.container_app_cpu
      memory  = var.container_app_memory
      command = []
      args    = []

      env {
        name  = "APP_CONFIG_ENDPOINT"
        value = azurerm_app_configuration.this.endpoint
      }

      env {
        name  = "AZURE_TENANT_ID"
        value = var.tenant_id
      }

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.mcp.client_id
      }
    }
  }

  tags = local.tags
}

# AI Foundry account and project via AzAPI
resource "azapi_resource" "ai_foundry_account" {
  type                      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name                      = local.ai_foundry_account_name
  location                  = azurerm_resource_group.this.location
  parent_id                 = azurerm_resource_group.this.id
  schema_validation_enabled = false
  response_export_values    = ["*"]

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    properties = {
      allowProjectManagement = true
      customSubDomainName    = local.ai_foundry_account_name
      networkAcls = {
        bypass        = "AzureServices"
        defaultAction = var.enable_zero_trust ? "Deny" : "Allow"
        virtualNetworkRules = var.enable_zero_trust ? [
          {
            id                               = azurerm_subnet.ai_foundry_agents[0].id
            ignoreMissingVnetServiceEndpoint = true
          }
        ] : null
        ipRules = []
      }
      networkInjections = var.enable_zero_trust && var.enable_ai_foundry_network_injection ? [
        {
          scenario                   = "agent"
          subnetArmId                = azurerm_subnet.ai_foundry_agents[0].id
          useMicrosoftManagedNetwork = false
        }
      ] : null
      publicNetworkAccess = "Enabled"
      disableLocalAuth    = true
    }
    tags = local.tags
  }
}

resource "azapi_resource" "ai_foundry_chat_deployment" {
  type                      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name                      = "chat"
  parent_id                 = azapi_resource.ai_foundry_account.id
  schema_validation_enabled = false

  body = {
    sku = {
      name     = "GlobalStandard"
      capacity = var.chat_model_capacity
    }
    properties = {
      model = {
        name    = var.chat_model_name
        format  = "OpenAI"
        version = var.chat_model_version
      }
      raiPolicyName = var.enable_responsible_ai_policy ? var.rai_policy_name : null
    }
  }

  depends_on = [
    azapi_resource.ai_foundry_rai_policy
  ]
}

resource "azapi_resource" "ai_foundry_embedding_deployment" {
  type                      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name                      = "text-embedding"
  parent_id                 = azapi_resource.ai_foundry_account.id
  schema_validation_enabled = false

  body = {
    sku = {
      name     = "Standard"
      capacity = var.embedding_model_capacity
    }
    properties = {
      model = {
        name    = var.embedding_model_name
        format  = "OpenAI"
        version = var.embedding_model_version
      }
    }
  }
}

resource "azapi_resource" "ai_foundry_project" {
  type                      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name                      = local.ai_foundry_project_name
  parent_id                 = azapi_resource.ai_foundry_account.id
  location                  = azurerm_resource_group.this.location
  schema_validation_enabled = false
  response_export_values    = ["*"]

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      description = local.ai_foundry_project_description
      displayName = local.ai_foundry_project_display_name
    }
  }
}

resource "azapi_resource" "ai_foundry_rai_blocklist" {
  count                     = var.enable_responsible_ai_policy ? 1 : 0
  type                      = "Microsoft.CognitiveServices/accounts/raiBlocklists@2025-06-01"
  name                      = var.rai_blocklist_name
  parent_id                 = azapi_resource.ai_foundry_account.id
  schema_validation_enabled = false
  tags                      = local.tags

  body = {
    properties = {
      description = "GPT-RAG responsible AI blocklist"
    }
  }
}

resource "azapi_resource" "ai_foundry_rai_blocklist_items" {
  for_each                  = var.enable_responsible_ai_policy ? local.nonempty_rai_blocklist_items : {}
  type                      = "Microsoft.CognitiveServices/accounts/raiBlocklists/raiBlocklistItems@2025-06-01"
  name                      = each.key
  parent_id                 = azapi_resource.ai_foundry_rai_blocklist[0].id
  schema_validation_enabled = false
  tags                      = local.tags

  body = {
    properties = {
      pattern = each.value.pattern
      isRegex = each.value.is_regex
    }
  }
}

resource "azapi_resource" "ai_foundry_rai_policy" {
  count                     = var.enable_responsible_ai_policy ? 1 : 0
  type                      = "Microsoft.CognitiveServices/accounts/raiPolicies@2025-06-01"
  name                      = var.rai_policy_name
  parent_id                 = azapi_resource.ai_foundry_account.id
  schema_validation_enabled = false
  tags                      = local.tags

  body = {
    properties = {
      basePolicyName   = "Microsoft.Default"
      contentFilters   = local.rai_content_filters
      customBlocklists = local.rai_custom_blocklists
      mode             = "Default"
    }
  }

  lifecycle {
    ignore_changes = [
      body
    ]
  }
}

resource "azapi_resource" "ai_foundry_project_connection_cosmos" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name                      = azurerm_cosmosdb_account.ai_foundry.name
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  body = {
    properties = {
      category = "CosmosDb"
      target   = azurerm_cosmosdb_account.ai_foundry.endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_cosmosdb_account.ai_foundry.id
        location   = azurerm_cosmosdb_account.ai_foundry.location
      }
    }
  }
}

resource "azapi_resource" "ai_foundry_project_connection_storage" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name                      = azurerm_storage_account.ai_foundry.name
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  body = {
    properties = {
      category = "AzureStorageAccount"
      target   = trimsuffix(azurerm_storage_account.ai_foundry.primary_blob_endpoint, "/")
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_storage_account.ai_foundry.id
        location   = azurerm_storage_account.ai_foundry.location
      }
    }
  }
}

resource "azapi_resource" "ai_foundry_project_connection_dependency_search" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name                      = azurerm_search_service.ai_foundry.name
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  body = {
    properties = {
      category = "CognitiveSearch"
      target   = "https://${azurerm_search_service.ai_foundry.name}.search.windows.net"
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_search_service.ai_foundry.id
        location   = azurerm_search_service.ai_foundry.location
      }
    }
  }
}

resource "azapi_resource" "ai_foundry_account_connection_search" {
  type                      = "Microsoft.CognitiveServices/accounts/connections@2025-06-01"
  name                      = "${local.ai_foundry_account_name}-connection"
  parent_id                 = azapi_resource.ai_foundry_account.id
  schema_validation_enabled = false

  body = {
    properties = {
      category      = "CognitiveSearch"
      target        = "https://${azurerm_search_service.solution.name}.search.windows.net"
      authType      = "AAD"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_search_service.solution.id
        location   = azurerm_search_service.solution.location
      }
    }
  }
}

resource "azapi_resource" "ai_foundry_account_connection_storage" {
  type                      = "Microsoft.CognitiveServices/accounts/connections@2025-06-01"
  name                      = "${local.ai_foundry_account_name}-storage"
  parent_id                 = azapi_resource.ai_foundry_account.id
  schema_validation_enabled = false

  body = {
    properties = {
      category      = "AzureStorageAccount"
      target        = trimsuffix(azurerm_storage_account.solution.primary_blob_endpoint, "/")
      authType      = "AAD"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_storage_account.solution.id
      }
    }
  }
}

resource "azapi_resource" "ai_foundry_account_connection_appinsights" {
  type                      = "Microsoft.CognitiveServices/accounts/connections@2025-06-01"
  name                      = "${local.ai_foundry_account_name}-appinsights"
  parent_id                 = azapi_resource.ai_foundry_account.id
  schema_validation_enabled = false

  body = {
    properties = {
      category      = "AppInsights"
      target        = azurerm_application_insights.this.id
      authType      = "ApiKey"
      isSharedToAll = true
      credentials = {
        key = azurerm_application_insights.this.connection_string
      }
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_application_insights.this.id
      }
    }
  }
}

resource "azapi_resource" "ai_foundry_account_capability_host" {
  count = var.enable_ai_foundry_capability_hosts ? 1 : 0

  type                      = "Microsoft.CognitiveServices/accounts/capabilityHosts@2025-04-01-preview"
  name                      = local.ai_foundry_account_cap_host
  parent_id                 = azapi_resource.ai_foundry_account.id
  schema_validation_enabled = false

  body = {
    properties = {
      capabilityHostKind = "Agents"
      customerSubnet     = var.enable_zero_trust ? azurerm_subnet.ai_foundry_agents[0].id : null
    }
  }

  timeouts {
    create = "90m"
    update = "90m"
  }
}

resource "azapi_resource" "ai_foundry_project_capability_host" {
  count = var.enable_ai_foundry_capability_hosts ? 1 : 0

  type                      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name                      = local.ai_foundry_project_cap_host
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  body = {
    properties = {
      capabilityHostKind       = "Agents"
      vectorStoreConnections   = [azapi_resource.ai_foundry_project_connection_dependency_search.name]
      storageConnections       = [azapi_resource.ai_foundry_project_connection_storage.name]
      threadStorageConnections = [azapi_resource.ai_foundry_project_connection_cosmos.name]
    }
  }

  timeouts {
    create = "90m"
    update = "90m"
  }

  depends_on = [
    azapi_resource.ai_foundry_account_capability_host,
    azapi_resource.ai_foundry_project_connection_cosmos,
    azapi_resource.ai_foundry_project_connection_storage,
    azapi_resource.ai_foundry_project_connection_dependency_search
  ]
}

locals {
  ai_foundry_account_output = (azapi_resource.ai_foundry_account.output)
  ai_foundry_project_output = (azapi_resource.ai_foundry_project.output)

  ai_foundry_account_endpoint     = try(local.ai_foundry_account_output.properties.endpoint, null)
  ai_foundry_account_principal_id = try(local.ai_foundry_account_output.identity.principalId, null)
  ai_foundry_project_principal_id = try(local.ai_foundry_project_output.identity.principalId, null)
  ai_foundry_project_internal_id  = try(local.ai_foundry_project_output.properties.internalId, "")
  ai_foundry_project_workspace_guid = length(local.ai_foundry_project_internal_id) >= 32 ? format(
    "%s-%s-%s-%s-%s",
    substr(local.ai_foundry_project_internal_id, 0, 8),
    substr(local.ai_foundry_project_internal_id, 8, 4),
    substr(local.ai_foundry_project_internal_id, 12, 4),
    substr(local.ai_foundry_project_internal_id, 16, 4),
    substr(local.ai_foundry_project_internal_id, 20, 12)
  ) : ""

  container_apps_list = [
    {
      name           = azurerm_container_app.orchestrator.name
      fqdn           = azurerm_container_app.orchestrator.ingress[0].fqdn
      external       = true
      service_name   = "orchestrator"
      profile_name   = "main"
      min_replicas   = 1
      max_replicas   = 1
      canonical_name = "ORCHESTRATOR_APP"
      roles = [
        "AppConfigurationDataReader",
        "CognitiveServicesUser",
        "CognitiveServicesOpenAIUser",
        "AcrPull",
        "CosmosDBBuiltInDataContributor",
        "SearchIndexDataReader",
        "StorageBlobDataReader",
        "KeyVaultSecretsUser"
      ]
    },
    {
      name           = azurerm_container_app.frontend.name
      fqdn           = azurerm_container_app.frontend.ingress[0].fqdn
      external       = true
      service_name   = "frontend"
      profile_name   = "main"
      min_replicas   = 1
      max_replicas   = 1
      canonical_name = "FRONTEND_APP"
      roles = [
        "AppConfigurationDataReader",
        "AcrPull",
        "StorageBlobDataReader",
        "KeyVaultSecretsUser"
      ]
    },
    {
      name           = azurerm_container_app.dataingest.name
      fqdn           = azurerm_container_app.dataingest.ingress[0].fqdn
      external       = true
      service_name   = "dataingest"
      profile_name   = "main"
      min_replicas   = 1
      max_replicas   = 1
      canonical_name = "DATA_INGEST_APP"
      roles = [
        "AppConfigurationDataReader",
        "CognitiveServicesUser",
        "CognitiveServicesOpenAIUser",
        "AcrPull",
        "SearchIndexDataContributor",
        "StorageBlobDataContributor",
        "KeyVaultSecretsUser"
      ]
    },
    {
      name           = azurerm_container_app.mcp.name
      fqdn           = azurerm_container_app.mcp.ingress[0].fqdn
      external       = true
      service_name   = "mcp"
      profile_name   = "main"
      min_replicas   = 1
      max_replicas   = 1
      canonical_name = "MCP_APP"
      roles = [
        "AppConfigurationDataReader",
        "CognitiveServicesUser",
        "CognitiveServicesOpenAIUser",
        "CosmosDBBuiltInDataContributor",
        "AcrPull",
        "SearchIndexDataContributor",
        "StorageBlobDataContributor",
        "StorageQueueDataContributor",
        "KeyVaultSecretsUser"
      ]
    }
  ]
}

# App Configuration contract used by GPT-RAG services and post-provision scripts
locals {
  app_config_items = concat(
    [
      for app in local.container_apps_list : {
        name         = "${app.canonical_name}_ENDPOINT"
        value        = "https://${app.fqdn}"
        label        = "gpt-rag"
        content_type = "text/plain"
      }
    ],
    [
      for app in local.container_apps_list : {
        name         = "${app.canonical_name}_NAME"
        value        = app.name
        label        = "gpt-rag"
        content_type = "text/plain"
      }
    ],
    [
      {
        name         = "CHAT_DEPLOYMENT_NAME"
        value        = "chat"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "EMBEDDING_DEPLOYMENT_NAME"
        value        = "text-embedding"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "CONVERSATIONS_DATABASE_CONTAINER"
        value        = azurerm_cosmosdb_sql_container.conversations.name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "DATASOURCES_DATABASE_CONTAINER"
        value        = azurerm_cosmosdb_sql_container.datasources.name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "PROMPTS_CONTAINER"
        value        = azurerm_cosmosdb_sql_container.prompts.name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "MCP_CONTAINER"
        value        = azurerm_cosmosdb_sql_container.mcp.name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "DOCUMENTS_IMAGES_STORAGE_CONTAINER"
        value        = azurerm_storage_container.solution_documents_images.name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "DOCUMENTS_STORAGE_CONTAINER"
        value        = azurerm_storage_container.solution_documents.name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "NL2SQL_STORAGE_CONTAINER"
        value        = azurerm_storage_container.solution_nl2sql.name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "AZURE_TENANT_ID"
        value        = var.tenant_id
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "SUBSCRIPTION_ID"
        value        = var.subscription_id
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "AZURE_RESOURCE_GROUP"
        value        = azurerm_resource_group.this.name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "LOCATION"
        value        = azurerm_resource_group.this.location
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "ENVIRONMENT_NAME"
        value        = var.environment_name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "DEPLOYMENT_NAME"
        value        = local.deployment_name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "RESOURCE_TOKEN"
        value        = local.resource_token
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "NETWORK_ISOLATION"
        value        = "false"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "USE_UAI"
        value        = "true"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "USE_CAPP_API_KEY"
        value        = tostring(var.use_capp_api_key)
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "LOG_LEVEL"
        value        = "INFO"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "ENABLE_CONSOLE_LOGGING"
        value        = "true"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "PROMPT_SOURCE"
        value        = "file"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "GPT_RAG_RELEASE"
        value        = local.gpt_rag_release
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value        = azurerm_application_insights.this.connection_string
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "APPLICATIONINSIGHTS__INSTRUMENTATIONKEY"
        value        = azurerm_application_insights.this.instrumentation_key
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "AGENT_STRATEGY"
        value        = "single_agent_rag"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "KEY_VAULT_RESOURCE_ID"
        value        = azurerm_key_vault.this.id
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "STORAGE_ACCOUNT_RESOURCE_ID"
        value        = azurerm_storage_account.solution.id
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "APP_INSIGHTS_RESOURCE_ID"
        value        = azurerm_application_insights.this.id
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "LOG_ANALYTICS_RESOURCE_ID"
        value        = azurerm_log_analytics_workspace.this.id
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "CONTAINER_ENV_RESOURCE_ID"
        value        = azurerm_container_app_environment.this.id
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "AI_FOUNDRY_ACCOUNT_RESOURCE_ID"
        value        = azapi_resource.ai_foundry_account.id
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "AI_FOUNDRY_PROJECT_RESOURCE_ID"
        value        = azapi_resource.ai_foundry_project.id
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "COSMOS_DB_ACCOUNT_RESOURCE_ID"
        value        = azurerm_cosmosdb_account.solution.id
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "AI_FOUNDRY_PROJECT_WORKSPACE_ID"
        value        = local.ai_foundry_project_workspace_guid
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "SEARCH_SERVICE_UAI_RESOURCE_ID"
        value        = ""
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "SEARCH_SERVICE_RESOURCE_ID"
        value        = azurerm_search_service.solution.id
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "AI_FOUNDRY_ACCOUNT_NAME"
        value        = local.ai_foundry_account_name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "AI_FOUNDRY_PROJECT_NAME"
        value        = local.ai_foundry_project_name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "AI_FOUNDRY_STORAGE_ACCOUNT_NAME"
        value        = local.ai_foundry_storage_name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "APP_CONFIG_NAME"
        value        = local.app_config_name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "APP_INSIGHTS_NAME"
        value        = local.app_insights_name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "CONTAINER_ENV_NAME"
        value        = local.container_env_name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "CONTAINER_REGISTRY_NAME"
        value        = local.container_registry_name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "DATABASE_ACCOUNT_NAME"
        value        = local.cosmos_account_name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "DATABASE_NAME"
        value        = local.cosmos_database_name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "SEARCH_SERVICE_NAME"
        value        = local.solution_search_service_name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "STORAGE_ACCOUNT_NAME"
        value        = local.solution_storage_account_name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "CONTAINER_REGISTRY_LOGIN_SERVER"
        value        = azurerm_container_registry.this.login_server
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "DEPLOY_APP_CONFIG"
        value        = "true"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "DEPLOY_KEY_VAULT"
        value        = "true"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "DEPLOY_LOG_ANALYTICS"
        value        = "true"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "DEPLOY_APP_INSIGHTS"
        value        = "true"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "DEPLOY_SEARCH_SERVICE"
        value        = "true"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "DEPLOY_STORAGE_ACCOUNT"
        value        = "true"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "DEPLOY_COSMOS_DB"
        value        = "true"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "DEPLOY_CONTAINER_APPS"
        value        = "true"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "DEPLOY_CONTAINER_REGISTRY"
        value        = "true"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "DEPLOY_CONTAINER_ENV"
        value        = "true"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "KEY_VAULT_URI"
        value        = azurerm_key_vault.this.vault_uri
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "STORAGE_BLOB_ENDPOINT"
        value        = azurerm_storage_account.solution.primary_blob_endpoint
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "AI_FOUNDRY_ACCOUNT_ENDPOINT"
        value        = local.ai_foundry_account_endpoint
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "AI_FOUNDRY_PROJECT_ENDPOINT"
        value        = "https://${local.ai_foundry_account_name}.services.ai.azure.com/api/projects/${local.ai_foundry_project_name}"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "COSMOS_DB_ENDPOINT"
        value        = azurerm_cosmosdb_account.solution.endpoint
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "SEARCH_SERVICE_QUERY_ENDPOINT"
        value        = "https://${azurerm_search_service.solution.name}.search.windows.net"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "SEARCH_CONNECTION_ID"
        value        = "/subscriptions/${var.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.CognitiveServices/accounts/${local.ai_foundry_account_name}/projects/${local.ai_foundry_project_name}/connections/${local.ai_foundry_account_name}-connection"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "BING_CONNECTION_ID"
        value        = ""
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "AI_FOUNDRY_ACCOUNT_PRINCIPAL_ID"
        value        = local.ai_foundry_account_principal_id
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "AI_FOUNDRY_PROJECT_PRINCIPAL_ID"
        value        = local.ai_foundry_project_principal_id
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "CONTAINER_ENV_PRINCIPAL_ID"
        value        = ""
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "SEARCH_SERVICE_PRINCIPAL_ID"
        value        = ""
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "AI_FOUNDRY_STORAGE_CONNECTION"
        value        = azurerm_storage_account.ai_foundry.name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "AI_FOUNDRY_COSMOS_DB_CONNECTION"
        value        = azurerm_cosmosdb_account.ai_foundry.name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "AI_FOUNDRY_SEARCH_CONNECTION"
        value        = azurerm_search_service.solution.name
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "CONTAINER_APPS"
        value        = jsonencode(local.container_apps_list)
        label        = "gpt-rag"
        content_type = "application/json"
      },
      {
        name         = "MODEL_DEPLOYMENTS"
        value        = jsonencode(local.model_deployments)
        label        = "gpt-rag"
        content_type = "application/json"
      },
      {
        name         = "SEARCH_API_VERSION"
        value        = "2025-05-01-preview"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "SEARCH_ANALYZER_NAME"
        value        = "standard.lucene"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "EMBEDDINGS_VECTOR_DIMENSIONS"
        value        = "3072"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "SEARCH_RAG_INDEX_NAME"
        value        = "ragindex-${local.resource_token}"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "SEARCH_QUERIES_INDEX_NAME"
        value        = "nl2sql-${local.resource_token}-queries"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "SEARCH_TABLES_INDEX_NAME"
        value        = "nl2sql-${local.resource_token}-tables"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "SEARCH_MEASURES_INDEX_NAME"
        value        = "nl2sql-${local.resource_token}-measures"
        label        = "gpt-rag"
        content_type = "text/plain"
      },
      {
        name         = "CRON_RUN_BLOB_PURGE"
        value        = "0 * * * *"
        label        = "gpt-rag-ingestion"
        content_type = "text/plain"
      },
      {
        name         = "CRON_RUN_BLOB_INDEX"
        value        = "10 * * * *"
        label        = "gpt-rag-ingestion"
        content_type = "text/plain"
      }
    ],
    var.use_capp_api_key ? [
      for app in local.container_apps_list : {
        name         = "${app.canonical_name}_APIKEY"
        value        = jsonencode({ uri = "${azurerm_key_vault.this.vault_uri}secrets/${replace(app.canonical_name, "_", "-")}-APIKEY" })
        label        = "gpt-rag"
        content_type = "application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8"
      }
    ] : []
  )

  app_config_map = {
    for item in local.app_config_items :
    "${item.label}:${item.name}" => item
  }
}

resource "azapi_resource" "app_config_keys" {
  for_each                  = var.manage_app_config_keys ? local.app_config_map : {}
  type                      = "Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01"
  name                      = format("%s$%s", each.value.name, each.value.label)
  parent_id                 = azurerm_app_configuration.this.id
  schema_validation_enabled = false

  body = {
    properties = {
      value       = each.value.value
      contentType = each.value.content_type
    }
  }
}

resource "azurerm_key_vault_secret" "container_app_api_keys" {
  for_each     = var.use_capp_api_key ? var.container_app_api_keys : {}
  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.this.id
}

# RBAC for Container Apps
resource "azurerm_role_assignment" "frontend_appconfig" {
  scope                = azurerm_app_configuration.this.id
  role_definition_name = "App Configuration Data Reader"
  principal_id         = azurerm_user_assigned_identity.frontend.principal_id
}

resource "azurerm_role_assignment" "orchestrator_appconfig" {
  scope                = azurerm_app_configuration.this.id
  role_definition_name = "App Configuration Data Reader"
  principal_id         = azurerm_user_assigned_identity.orchestrator.principal_id
}

resource "azurerm_role_assignment" "dataingest_appconfig" {
  scope                = azurerm_app_configuration.this.id
  role_definition_name = "App Configuration Data Reader"
  principal_id         = azurerm_user_assigned_identity.dataingest.principal_id
}

resource "azurerm_role_assignment" "mcp_appconfig" {
  scope                = azurerm_app_configuration.this.id
  role_definition_name = "App Configuration Data Reader"
  principal_id         = azurerm_user_assigned_identity.mcp.principal_id
}

resource "azurerm_role_assignment" "executor_appconfig" {
  scope                = azurerm_app_configuration.this.id
  role_definition_name = "App Configuration Data Owner"
  principal_id         = azurerm_user_assigned_identity.executor.principal_id
}

resource "azurerm_role_assignment" "frontend_acr" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.frontend.principal_id
}

resource "azurerm_role_assignment" "orchestrator_acr" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.orchestrator.principal_id
}

resource "azurerm_role_assignment" "dataingest_acr" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.dataingest.principal_id
}

resource "azurerm_role_assignment" "mcp_acr" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.mcp.principal_id
}

resource "azurerm_role_assignment" "executor_acr_push" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.executor.principal_id
}

resource "azurerm_role_assignment" "executor_acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.executor.principal_id
}

resource "azurerm_role_assignment" "frontend_kv" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.frontend.principal_id
}

resource "azurerm_role_assignment" "orchestrator_kv" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.orchestrator.principal_id
}

resource "azurerm_role_assignment" "dataingest_kv" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.dataingest.principal_id
}

resource "azurerm_role_assignment" "mcp_kv" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.mcp.principal_id
}

resource "azurerm_role_assignment" "executor_kv_contributor" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Contributor"
  principal_id         = azurerm_user_assigned_identity.executor.principal_id
}

resource "azurerm_role_assignment" "executor_kv_secrets" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.executor.principal_id
}

resource "azurerm_role_assignment" "orchestrator_search_reader" {
  scope                = azurerm_search_service.solution.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = azurerm_user_assigned_identity.orchestrator.principal_id
}

resource "azurerm_role_assignment" "dataingest_search_contributor" {
  scope                = azurerm_search_service.solution.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azurerm_user_assigned_identity.dataingest.principal_id
}

resource "azurerm_role_assignment" "mcp_search_contributor" {
  scope                = azurerm_search_service.solution.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azurerm_user_assigned_identity.mcp.principal_id
}

resource "azurerm_role_assignment" "executor_search_service" {
  scope                = azurerm_search_service.solution.id
  role_definition_name = "Search Service Contributor"
  principal_id         = azurerm_user_assigned_identity.executor.principal_id
}

resource "azurerm_role_assignment" "executor_search_data" {
  scope                = azurerm_search_service.solution.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azurerm_user_assigned_identity.executor.principal_id
}

resource "azurerm_role_assignment" "orchestrator_storage_reader" {
  scope                = azurerm_storage_account.solution.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.orchestrator.principal_id
}

resource "azurerm_role_assignment" "frontend_storage_reader" {
  scope                = azurerm_storage_account.solution.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.frontend.principal_id
}

resource "azurerm_role_assignment" "dataingest_storage_contributor" {
  scope                = azurerm_storage_account.solution.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.dataingest.principal_id
}

resource "azurerm_role_assignment" "mcp_storage_contributor" {
  scope                = azurerm_storage_account.solution.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.mcp.principal_id
}

resource "azurerm_role_assignment" "executor_storage_contributor" {
  scope                = azurerm_storage_account.solution.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.executor.principal_id
}

resource "azurerm_cosmosdb_sql_role_assignment" "orchestrator_cosmos_contributor" {
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.solution.name
  role_definition_id  = "${azurerm_cosmosdb_account.solution.id}/sqlRoleDefinitions/${local.cosmos_sql_data_contributor_id}"
  principal_id        = azurerm_user_assigned_identity.orchestrator.principal_id
  scope               = azurerm_cosmosdb_account.solution.id
}

resource "azurerm_cosmosdb_sql_role_assignment" "mcp_cosmos_contributor" {
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.solution.name
  role_definition_id  = "${azurerm_cosmosdb_account.solution.id}/sqlRoleDefinitions/${local.cosmos_sql_data_contributor_id}"
  principal_id        = azurerm_user_assigned_identity.mcp.principal_id
  scope               = azurerm_cosmosdb_account.solution.id
}

resource "azurerm_cosmosdb_sql_role_assignment" "executor_cosmos_contributor" {
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.solution.name
  role_definition_id  = "${azurerm_cosmosdb_account.solution.id}/sqlRoleDefinitions/${local.cosmos_sql_data_contributor_id}"
  principal_id        = azurerm_user_assigned_identity.executor.principal_id
  scope               = azurerm_cosmosdb_account.solution.id
}

# RBAC for AI Foundry account and project
resource "azurerm_role_assignment" "orchestrator_foundry_user" {
  scope                = azapi_resource.ai_foundry_account.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_user_assigned_identity.orchestrator.principal_id
}

resource "azurerm_role_assignment" "dataingest_foundry_user" {
  scope                = azapi_resource.ai_foundry_account.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_user_assigned_identity.dataingest.principal_id
}

resource "azurerm_role_assignment" "mcp_foundry_user" {
  scope                = azapi_resource.ai_foundry_account.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_user_assigned_identity.mcp.principal_id
}

resource "azurerm_role_assignment" "orchestrator_foundry_openai_user" {
  scope                = azapi_resource.ai_foundry_account.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.orchestrator.principal_id
}

resource "azurerm_role_assignment" "dataingest_foundry_openai_user" {
  scope                = azapi_resource.ai_foundry_account.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.dataingest.principal_id
}

resource "azurerm_role_assignment" "mcp_foundry_openai_user" {
  scope                = azapi_resource.ai_foundry_account.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.mcp.principal_id
}

resource "azurerm_role_assignment" "executor_foundry_project_manager" {
  scope                = azapi_resource.ai_foundry_account.id
  role_definition_name = "Azure AI Project Manager"
  principal_id         = azurerm_user_assigned_identity.executor.principal_id
}

resource "azurerm_role_assignment" "foundry_project_solution_search_reader" {
  scope                = azurerm_search_service.solution.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = local.ai_foundry_project_principal_id
}

resource "azurerm_role_assignment" "foundry_project_solution_search_service" {
  scope                = azurerm_search_service.solution.id
  role_definition_name = "Search Service Contributor"
  principal_id         = local.ai_foundry_project_principal_id
}

resource "azurerm_role_assignment" "foundry_project_solution_storage_reader" {
  scope                = azurerm_storage_account.solution.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = local.ai_foundry_project_principal_id
}

resource "azurerm_role_assignment" "foundry_account_dep_storage_reader" {
  scope                = azurerm_storage_account.ai_foundry.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = local.ai_foundry_account_principal_id
}

resource "azurerm_role_assignment" "foundry_account_dep_storage_contributor" {
  scope                = azurerm_storage_account.ai_foundry.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.ai_foundry_account_principal_id
}

resource "azurerm_role_assignment" "foundry_project_dep_storage_reader" {
  scope                = azurerm_storage_account.ai_foundry.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = local.ai_foundry_project_principal_id
}

resource "azurerm_role_assignment" "foundry_project_dep_storage_contributor" {
  scope                = azurerm_storage_account.ai_foundry.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.ai_foundry_project_principal_id
}

resource "azurerm_role_assignment" "foundry_account_dep_search_reader" {
  scope                = azurerm_search_service.ai_foundry.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = local.ai_foundry_account_principal_id
}

resource "azurerm_role_assignment" "foundry_account_dep_search_contributor" {
  scope                = azurerm_search_service.ai_foundry.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = local.ai_foundry_account_principal_id
}

resource "azurerm_role_assignment" "foundry_account_dep_search_service" {
  scope                = azurerm_search_service.ai_foundry.id
  role_definition_name = "Search Service Contributor"
  principal_id         = local.ai_foundry_account_principal_id
}

resource "azurerm_role_assignment" "foundry_project_dep_search_reader" {
  scope                = azurerm_search_service.ai_foundry.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = local.ai_foundry_project_principal_id
}

resource "azurerm_role_assignment" "foundry_project_dep_search_contributor" {
  scope                = azurerm_search_service.ai_foundry.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = local.ai_foundry_project_principal_id
}

resource "azurerm_role_assignment" "foundry_project_dep_search_service" {
  scope                = azurerm_search_service.ai_foundry.id
  role_definition_name = "Search Service Contributor"
  principal_id         = local.ai_foundry_project_principal_id
}

resource "azurerm_cosmosdb_sql_role_assignment" "foundry_account_dep_cosmos_contributor" {
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.ai_foundry.name
  role_definition_id  = "${azurerm_cosmosdb_account.ai_foundry.id}/sqlRoleDefinitions/${local.cosmos_sql_data_contributor_id}"
  principal_id        = local.ai_foundry_account_principal_id
  scope               = azurerm_cosmosdb_account.ai_foundry.id
}

resource "azurerm_role_assignment" "foundry_project_dep_cosmos_operator" {
  scope                = azurerm_cosmosdb_account.ai_foundry.id
  role_definition_name = "Cosmos DB Operator"
  principal_id         = local.ai_foundry_project_principal_id
}

resource "azurerm_role_assignment" "foundry_project_resource_group_reader" {
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Reader"
  principal_id         = local.ai_foundry_project_principal_id
}

resource "azurerm_role_assignment" "foundry_project_dep_cosmos_account_contributor" {
  scope                = azurerm_cosmosdb_account.ai_foundry.id
  role_definition_name = "DocumentDB Account Contributor"
  principal_id         = local.ai_foundry_project_principal_id
}

resource "azurerm_role_assignment" "foundry_project_dep_cosmos_enterprise_memory_reader" {
  scope                = "${azurerm_cosmosdb_account.ai_foundry.id}/sqlDatabases/enterprise_memory"
  role_definition_name = "Reader"
  principal_id         = local.ai_foundry_project_principal_id
}

resource "azurerm_role_assignment" "foundry_project_dep_cosmos_thread_store_reader" {
  scope                = "${azurerm_cosmosdb_account.ai_foundry.id}/sqlDatabases/enterprise_memory/containers/${local.ai_foundry_project_workspace_guid}-thread-message-store"
  role_definition_name = "Reader"
  principal_id         = local.ai_foundry_project_principal_id
}

resource "azurerm_role_assignment" "foundry_project_dep_cosmos_system_thread_store_reader" {
  scope                = "${azurerm_cosmosdb_account.ai_foundry.id}/sqlDatabases/enterprise_memory/containers/${local.ai_foundry_project_workspace_guid}-system-thread-message-store"
  role_definition_name = "Reader"
  principal_id         = local.ai_foundry_project_principal_id
}

resource "azurerm_cosmosdb_sql_role_assignment" "foundry_project_dep_cosmos_contributor" {
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.ai_foundry.name
  role_definition_id  = "${azurerm_cosmosdb_account.ai_foundry.id}/sqlRoleDefinitions/${local.cosmos_sql_data_contributor_id}"
  principal_id        = local.ai_foundry_project_principal_id
  scope               = azurerm_cosmosdb_account.ai_foundry.id
}
