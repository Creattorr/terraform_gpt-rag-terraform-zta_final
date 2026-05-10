[CmdletBinding()]
param(
  [string]$TerraformDirectory = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$VarFile = "terraform.zta-fresh.tfvars",
  [string]$StateFile = "terraform-zta-fresh.tfstate",
  [string]$OutFile = "tfplan-search-standard-rebuild"
)

$ErrorActionPreference = "Stop"

$targets = @(
  "azurerm_search_service.solution",
  "azurerm_search_service.ai_foundry",
  'azurerm_private_endpoint.this[\"solution_search\"]',
  'azurerm_private_endpoint.this[\"ai_foundry_search\"]',
  "azapi_resource.ai_foundry_account_connection_search",
  "azapi_resource.ai_foundry_project_connection_dependency_search",
  "azurerm_role_assignment.foundry_account_dep_search_contributor",
  "azurerm_role_assignment.foundry_account_dep_search_reader",
  "azurerm_role_assignment.foundry_account_dep_search_service",
  "azurerm_role_assignment.foundry_project_dep_search_contributor",
  "azurerm_role_assignment.foundry_project_dep_search_reader",
  "azurerm_role_assignment.foundry_project_dep_search_service",
  "azurerm_role_assignment.foundry_project_solution_search_reader",
  "azurerm_role_assignment.foundry_project_solution_search_service"
)

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

  Write-Host "Running targeted Search standard rebuild plan in $TerraformDirectory"
  Write-Host "Plan output: $OutFile"

  & terraform @terraformArgs
  exit $LASTEXITCODE
}
finally {
  Pop-Location
}
