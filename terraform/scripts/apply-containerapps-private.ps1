param(
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,
  [string]$PlanFile = "tfplan-containerapps-private",
  [Parameter(Mandatory = $true)]
  [string]$ResourceGroupName,
  [Parameter(Mandatory = $true)]
  [string]$ContainerAppEnvironmentName,
  [Parameter(Mandatory = $true)]
  [string]$ResourcePrefix
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $PlanFile)) {
  throw "Plan file '$PlanFile' was not found. Run .\scripts\plan-containerapps-private.ps1 first."
}

az login --identity | Out-Null
az account set --subscription $SubscriptionId

terraform apply $PlanFile

Write-Host ""
Write-Host "=== Container Apps Environment ==="
az containerapp env show `
  --resource-group $ResourceGroupName `
  --name $ContainerAppEnvironmentName `
  --query "{name:name,provisioningState:properties.provisioningState,staticIp:properties.staticIp,defaultDomain:properties.defaultDomain,vnetConfiguration:properties.vnetConfiguration}" `
  -o json

Write-Host ""
Write-Host "=== Container Apps ==="
$apps = @(
  "ca-$ResourcePrefix-frontend",
  "ca-$ResourcePrefix-orchestrator",
  "ca-$ResourcePrefix-dataingest",
  "ca-$ResourcePrefix-mcp"
)

foreach ($app in $apps) {
  Write-Host ""
  Write-Host $app
  az containerapp show `
    --resource-group $ResourceGroupName `
    --name $app `
    --query "{name:name,provisioningState:properties.provisioningState,latestRevision:properties.latestRevisionName,external:properties.configuration.ingress.external,fqdn:properties.configuration.ingress.fqdn}" `
    -o json
}

Write-Host ""
Write-Host "Private Container Apps migration apply completed."
Write-Host "Next: validate app logs and private reachability before setting disable_public_network_access=true."
