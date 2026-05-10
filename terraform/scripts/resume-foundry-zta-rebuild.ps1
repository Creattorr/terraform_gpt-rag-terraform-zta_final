param(
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,
  [Parameter(Mandatory = $true)]
  [string]$ResourceGroupName,
  [Parameter(Mandatory = $true)]
  [string]$VmName,
  [string]$TerraformPath = "C:\github\gpt-rag-terraform\terraform",
  [Parameter(Mandatory = $true)]
  [string]$FoundryAccountName,
  [ValidateSet("Check", "Plan", "Apply")]
  [string]$Mode = "Check"
)

$ErrorActionPreference = "Stop"

az account set --subscription $SubscriptionId

$vmPrincipalId = az vm show `
  --resource-group $ResourceGroupName `
  --name $VmName `
  --query identity.principalId `
  -o tsv

if (-not $vmPrincipalId) {
  throw "Could not read the system-assigned managed identity principal id for $VmName."
}

$scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
$requiredRoles = @(
  "Azure AI Account Owner",
  "Role Based Access Control Administrator"
)

$assignedRoles = az role assignment list `
  --scope $scope `
  --query "[?principalId=='$vmPrincipalId'].roleDefinitionName" `
  -o tsv

Write-Host "Jumpbox managed identity: $vmPrincipalId"
Write-Host "Scope: $scope"
Write-Host ""
Write-Host "Current roles:"
$assignedRoles | ForEach-Object { Write-Host "  - $_" }

$missingRoles = $requiredRoles | Where-Object { $assignedRoles -notcontains $_ }
if ($missingRoles.Count -gt 0) {
  Write-Host ""
  Write-Host "Missing roles required for secured Azure AI Foundry Agent provisioning:"
  $missingRoles | ForEach-Object { Write-Host "  - $_" }
  Write-Host ""
  Write-Host "Ask an Azure RBAC admin to run:"
  foreach ($role in $missingRoles) {
    Write-Host "az role assignment create --assignee-object-id $vmPrincipalId --assignee-principal-type ServicePrincipal --role `"$role`" --scope `"$scope`""
  }
  Write-Host ""
  Write-Host "Stopping before Terraform changes."
  exit 2
}

$foundryState = az rest `
  --method get `
  --uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$FoundryAccountName`?api-version=2025-04-01-preview" `
  --query properties.provisioningState `
  -o tsv 2>$null

if ($LASTEXITCODE -eq 0 -and $foundryState -and $foundryState -notin @("Succeeded", "Failed", "Canceled")) {
  Write-Host ""
  Write-Host "$FoundryAccountName provisioningState is '$foundryState'. Wait until it becomes terminal before retrying."
  exit 3
}

$targetArgs = @(
  "-target=azapi_resource.ai_foundry_account",
  "-target=azapi_resource.ai_foundry_chat_deployment",
  "-target=azapi_resource.ai_foundry_embedding_deployment",
  "-target=azapi_resource.ai_foundry_project",
  "-target=azapi_resource.ai_foundry_rai_blocklist[0]",
  "-target=azapi_resource.ai_foundry_rai_policy[0]",
  "-target=azapi_resource.ai_foundry_project_connection_cosmos",
  "-target=azapi_resource.ai_foundry_project_connection_storage",
  "-target=azapi_resource.ai_foundry_project_connection_dependency_search",
  "-target=azapi_resource.ai_foundry_account_connection_search",
  "-target=azapi_resource.ai_foundry_account_connection_storage",
  "-target=azapi_resource.ai_foundry_account_connection_appinsights",
  "-target=azapi_resource.ai_foundry_account_capability_host",
  "-target=azapi_resource.ai_foundry_project_capability_host",
  "-target=azurerm_private_endpoint.this",
  "-target=azurerm_private_dns_a_record.ai_foundry_services_ai[0]"
)

$remoteScript = @"
`$ErrorActionPreference = "Stop"
az login --identity | Out-Null
az account set --subscription $SubscriptionId
cd "$TerraformPath"
terraform init -input=false
terraform validate
terraform plan -out=tfplan-foundry-core-create -no-color $($targetArgs -join " ")
if ("$Mode" -eq "Apply") {
  terraform apply -auto-approve -no-color tfplan-foundry-core-create
}
"@

if ($Mode -eq "Check") {
  Write-Host ""
  Write-Host "Prerequisites look ready. Run again with -Mode Plan or -Mode Apply from your workstation."
  exit 0
}

$tempScript = Join-Path $env:TEMP "resume-foundry-zta-rebuild.remote.ps1"
Set-Content -LiteralPath $tempScript -Value $remoteScript -Encoding UTF8

az vm run-command invoke `
  --resource-group $ResourceGroupName `
  --name $VmName `
  --command-id RunPowerShellScript `
  --scripts "@$tempScript" `
  --query "value[].message" `
  -o tsv
