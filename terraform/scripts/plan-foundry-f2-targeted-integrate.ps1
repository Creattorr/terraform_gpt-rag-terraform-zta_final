[CmdletBinding()]
param(
  [string]$TerraformDirectory = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$VarFile = "terraform.zta-fresh.tfvars",
  [string]$StateFile = "terraform-zta-fresh.tfstate",
  [string]$OutFile = "tfplan-foundry-f2-targeted-integrate",
  [switch]$IncludePrivateEndpoints
)

$ErrorActionPreference = "Stop"

$targets = @(
  "azapi_resource.ai_foundry_account_connection_appinsights",
  "azapi_resource.ai_foundry_account_connection_search",
  "azapi_resource.ai_foundry_account_connection_storage",
  "azapi_resource.ai_foundry_project_connection_cosmos",
  "azapi_resource.ai_foundry_project_connection_dependency_search",
  "azapi_resource.ai_foundry_project_connection_storage",
  "azurerm_cosmosdb_sql_role_assignment.foundry_account_dep_cosmos_contributor",
  "azurerm_cosmosdb_sql_role_assignment.foundry_project_dep_cosmos_contributor",
  "azurerm_role_assignment.dataingest_foundry_openai_user",
  "azurerm_role_assignment.dataingest_foundry_user",
  "azurerm_role_assignment.executor_foundry_project_manager",
  "azurerm_role_assignment.foundry_account_dep_search_contributor",
  "azurerm_role_assignment.foundry_account_dep_search_reader",
  "azurerm_role_assignment.foundry_account_dep_search_service",
  "azurerm_role_assignment.foundry_account_dep_storage_contributor",
  "azurerm_role_assignment.foundry_account_dep_storage_reader",
  "azurerm_role_assignment.foundry_project_dep_cosmos_account_contributor",
  "azurerm_role_assignment.foundry_project_dep_cosmos_enterprise_memory_reader",
  "azurerm_role_assignment.foundry_project_dep_cosmos_operator",
  "azurerm_role_assignment.foundry_project_dep_cosmos_system_thread_store_reader",
  "azurerm_role_assignment.foundry_project_dep_cosmos_thread_store_reader",
  "azurerm_role_assignment.foundry_project_dep_search_contributor",
  "azurerm_role_assignment.foundry_project_dep_search_reader",
  "azurerm_role_assignment.foundry_project_dep_search_service",
  "azurerm_role_assignment.foundry_project_dep_storage_contributor",
  "azurerm_role_assignment.foundry_project_dep_storage_reader",
  "azurerm_role_assignment.foundry_project_resource_group_reader",
  "azurerm_role_assignment.foundry_project_solution_search_reader",
  "azurerm_role_assignment.foundry_project_solution_search_service",
  "azurerm_role_assignment.foundry_project_solution_storage_reader",
  "azurerm_role_assignment.mcp_foundry_openai_user",
  "azurerm_role_assignment.mcp_foundry_user",
  "azurerm_role_assignment.orchestrator_foundry_openai_user",
  "azurerm_role_assignment.orchestrator_foundry_user"
)

if ($IncludePrivateEndpoints) {
  $targets += @(
    "azurerm_private_endpoint.this",
    "azurerm_private_dns_a_record.ai_foundry_services_ai"
  )
}

Push-Location $TerraformDirectory
try {
  $terraformArgs = @(
    "plan",
    "-var-file=$VarFile",
    "-state=$StateFile",
    "-out=$OutFile"
  )

  foreach ($target in $targets) {
    $terraformArgs += "-target=$target"
  }

  Write-Host "Running targeted Foundry integration plan in $TerraformDirectory"
  Write-Host "Plan output: $OutFile"
  if ($IncludePrivateEndpoints) {
    Write-Host "Including private endpoints in this plan."
  } else {
    Write-Host "Private endpoints are excluded. Re-run with -IncludePrivateEndpoints after the Foundry connections are healthy."
  }

  & terraform @terraformArgs
  exit $LASTEXITCODE
}
finally {
  Pop-Location
}
