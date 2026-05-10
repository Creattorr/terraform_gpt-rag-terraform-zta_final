param(
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,
  [Parameter(Mandatory = $true)]
  [string]$StorageAccountName,
  [Parameter(Mandatory = $true)]
  [string]$AiFoundryStorageAccountName,
  [string]$DocumentsContainerName = "documents",
  [Parameter(Mandatory = $true)]
  [string]$SearchServiceName,
  [Parameter(Mandatory = $true)]
  [string]$AiFoundrySearchServiceName,
  [Parameter(Mandatory = $true)]
  [string]$AppConfigName,
  [Parameter(Mandatory = $true)]
  [string]$ContainerRegistryName,
  [Parameter(Mandatory = $true)]
  [string]$KeyVaultName,
  [Parameter(Mandatory = $true)]
  [string]$AiFoundryAccountName,
  [Parameter(Mandatory = $true)]
  [string]$SolutionCosmosAccountName,
  [Parameter(Mandatory = $true)]
  [string]$AiFoundryCosmosAccountName,
  [Parameter(Mandatory = $true)]
  [string]$RagIndexName
)

$ErrorActionPreference = "Stop"

function Write-Section {
  param([string]$Name)
  Write-Host ""
  Write-Host "=== $Name ==="
}

Write-Section "Managed Identity Login"
az login --identity | Out-Null
az account set --subscription $SubscriptionId
az account show --query "{name:name,id:id,tenantId:tenantId}" -o table

Write-Section "Private DNS"
$names = @(
  "$StorageAccountName.blob.core.windows.net",
  "$AiFoundryStorageAccountName.blob.core.windows.net",
  "$SearchServiceName.search.windows.net",
  "$AiFoundrySearchServiceName.search.windows.net",
  "$AppConfigName.azconfig.io",
  "$ContainerRegistryName.azurecr.io",
  "$KeyVaultName.vault.azure.net",
  "$AiFoundryAccountName.cognitiveservices.azure.com",
  "$AiFoundryAccountName.services.ai.azure.com",
  "$SolutionCosmosAccountName.documents.azure.com",
  "$AiFoundryCosmosAccountName.documents.azure.com"
)

foreach ($name in $names) {
  Write-Host ""
  Write-Host $name
  Resolve-DnsName $name | Where-Object { $_.IPAddress -or $_.NameHost } | Format-Table Name,Type,IPAddress,NameHost -AutoSize
}

Write-Section "Storage Data Plane"
az storage blob list `
  --account-name $StorageAccountName `
  --container-name $DocumentsContainerName `
  --auth-mode login `
  --query "[].{name:name,contentLength:properties.contentLength}" `
  -o table

Write-Section "AI Search Indexes"
$searchToken = az account get-access-token --resource https://search.azure.com --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $searchToken" }
try {
  $indexes = Invoke-RestMethod `
    -Method Get `
    -Uri "https://$SearchServiceName.search.windows.net/indexes?api-version=2025-05-01-preview" `
    -Headers $headers
  $indexes.value | Select-Object name | Format-Table -AutoSize
}
catch {
  Write-Host "Index definition listing was skipped or not permitted for this identity. Continuing with data-plane query."
}

Write-Section "AI Search Smoke Query"
$body = @{
  search = "terraform-rag-smoke-20260426"
  count  = $true
  select = "id,title,metadata_storage_name,source"
  top    = 3
} | ConvertTo-Json

$result = Invoke-RestMethod `
  -Method Post `
  -Uri "https://$SearchServiceName.search.windows.net/indexes/$RagIndexName/docs/search?api-version=2025-05-01-preview" `
  -Headers @{
    Authorization  = "Bearer $searchToken"
    "Content-Type" = "application/json"
  } `
  -Body $body

$result | ConvertTo-Json -Depth 8

Write-Section "App Configuration"
az appconfig kv list `
  --name $AppConfigName `
  --auth-mode login `
  --key "SEARCH_RAG_INDEX_NAME" `
  --label "gpt-rag" `
  -o table
