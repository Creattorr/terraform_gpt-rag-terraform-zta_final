param(
  [Parameter(Mandatory = $true)][string]$SubscriptionId,
  [Parameter(Mandatory = $true)][string]$ResourceGroupName,
  [Parameter(Mandatory = $true)][string]$AccountName,
  [Parameter(Mandatory = $true)][string]$ProjectName,
  [Parameter(Mandatory = $true)][string]$CustomerSubnetId,
  [Parameter(Mandatory = $true)][string]$VectorStoreConnectionName,
  [Parameter(Mandatory = $true)][string]$StorageConnectionName,
  [Parameter(Mandatory = $true)][string]$ThreadStorageConnectionName,
  [string]$AccountCapabilityHostName = "caphostacc",
  [string]$ProjectCapabilityHostName = "caphostproj",
  [string]$ApiVersion = "2025-06-01"
)

$ErrorActionPreference = "Stop"

az login --identity --allow-no-subscriptions | Out-Null
az account set --subscription $SubscriptionId

$base = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$AccountName"
$accountUri = "$base/capabilityHosts/$AccountCapabilityHostName`?api-version=$ApiVersion"
$projectUri = "$base/projects/$ProjectName/capabilityHosts/$ProjectCapabilityHostName`?api-version=$ApiVersion"

$workDir = "C:\WindowsAzure\Logs\gpt-rag-foundry-capability-hosts"
New-Item -ItemType Directory -Force -Path $workDir | Out-Null

$accountBodyPath = Join-Path $workDir "account-capability-host.json"
$projectBodyPath = Join-Path $workDir "project-capability-host.json"

$accountBody = @{
  properties = @{
    capabilityHostKind = "Agents"
    customerSubnet     = $CustomerSubnetId
  }
}

$projectBody = @{
  properties = @{
    capabilityHostKind         = "Agents"
    vectorStoreConnections    = @($VectorStoreConnectionName)
    storageConnections        = @($StorageConnectionName)
    threadStorageConnections  = @($ThreadStorageConnectionName)
  }
}

$accountBody | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $accountBodyPath -Encoding UTF8
$projectBody | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $projectBodyPath -Encoding UTF8

Write-Host "Creating or updating account capability host: $AccountCapabilityHostName"
az rest --method put --uri $accountUri --headers "Content-Type=application/json" --body "@$accountBodyPath" -o jsonc

Write-Host "Creating or updating project capability host: $ProjectCapabilityHostName"
az rest --method put --uri $projectUri --headers "Content-Type=application/json" --body "@$projectBodyPath" -o jsonc

Write-Host "Reading capability host status"
az rest --method get --uri "$base/capabilityHosts/$AccountCapabilityHostName`?api-version=$ApiVersion" --query "{name:name,provisioningState:properties.provisioningState,customerSubnet:properties.customerSubnet}" -o jsonc
az rest --method get --uri "$base/projects/$ProjectName/capabilityHosts/$ProjectCapabilityHostName`?api-version=$ApiVersion" --query "{name:name,provisioningState:properties.provisioningState,vectorStoreConnections:properties.vectorStoreConnections,storageConnections:properties.storageConnections,threadStorageConnections:properties.threadStorageConnections}" -o jsonc
