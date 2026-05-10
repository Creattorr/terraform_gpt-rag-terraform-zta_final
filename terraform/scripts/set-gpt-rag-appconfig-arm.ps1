param(
  [Parameter(Mandatory = $true)]
  [string] $SubscriptionId,
  [Parameter(Mandatory = $true)]
  [string] $TenantId,
  [Parameter(Mandatory = $true)]
  [string] $ResourceGroupName,
  [string] $Location = "swedencentral",
  [string] $EnvironmentName = "gptragzta",
  [Parameter(Mandatory = $true)]
  [string] $ResourcePrefix,
  [string] $FoundrySuffix = "",
  [string] $NetworkIsolation = "true",
  [string] $Label = "gpt-rag",
  [string] $IngestionLabel = "gpt-rag-ingestion",
  [string] $ConnectionString = "",
  [string] $LoginWithManagedIdentity = "false"
)

$ErrorActionPreference = "Stop"

if ($LoginWithManagedIdentity -in @("1", "true", "True", "$true")) {
  az login --identity --only-show-errors --output none
  if ($LASTEXITCODE -ne 0) {
    throw "Managed identity login failed."
  }
}

az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors --output none

function Invoke-AzCliJson {
  param(
    [Parameter(Mandatory = $true)]
    [string[]] $Arguments
  )

  $json = az @Arguments -o json 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI command failed: az $($Arguments -join ' ')"
  }

  if ([string]::IsNullOrWhiteSpace($json)) {
    return $null
  }

  return $json | ConvertFrom-Json
}

function Get-ArmResource {
  param(
    [Parameter(Mandatory = $true)]
    [string] $ResourceId,
    [Parameter(Mandatory = $true)]
    [string] $ApiVersion
  )

  return Invoke-AzCliJson @(
    "rest",
    "--method", "get",
    "--url", "https://management.azure.com$ResourceId`?api-version=$ApiVersion"
  )
}

function Add-AppConfigItem {
  param(
    [System.Collections.Generic.List[object]] $Items,
    [Parameter(Mandatory = $true)]
    [string] $Name,
    [AllowEmptyString()]
    [string] $Value,
    [string] $ItemLabel = $Label,
    [string] $ContentType = "text/plain"
  )

  $Items.Add([pscustomobject]@{
    name        = $Name
    value       = $Value
    label       = $ItemLabel
    contentType = $ContentType
  }) | Out-Null
}

function Set-AppConfigKeyValue {
  param(
    [Parameter(Mandatory = $true)]
    [string] $StoreResourceId,
    [Parameter(Mandatory = $true)]
    [object] $Item,
    [string] $ConnectionString = ""
  )

  if (-not [string]::IsNullOrWhiteSpace($ConnectionString)) {
    $value = [string]$Item.value
    az appconfig kv set `
      --connection-string $ConnectionString `
      --key $Item.name `
      --label $Item.label `
      --value="$value" `
      --yes `
      --only-show-errors `
      --output none

    if ($LASTEXITCODE -ne 0) {
      throw "Failed to set App Configuration key '$($Item.name)' with label '$($Item.label)'."
    }

    return
  }

  $name = [System.Uri]::EscapeDataString("$($Item.name)`$$($Item.label)")
  $url = "https://management.azure.com$StoreResourceId/keyValues/$name`?api-version=2024-05-01"
  $body = @{
    properties = @{
      value = [string]$Item.value
    }
  } | ConvertTo-Json -Depth 6 -Compress

  az rest `
    --method put `
    --url $url `
    --headers "Content-Type=application/json" `
    --body $body `
    --only-show-errors `
    --output none

  if ($LASTEXITCODE -ne 0) {
    throw "Failed to set App Configuration key '$($Item.name)' with label '$($Item.label)'."
  }
}

$prefix = $ResourcePrefix
$subscriptionScope = "/subscriptions/$SubscriptionId"
$resourceGroupScope = "$subscriptionScope/resourceGroups/$ResourceGroupName"

$names = @{
  appConfig        = "appcs-$prefix"
  appInsights     = "appi-$prefix"
  keyVault         = "kv-$prefix"
  logAnalytics     = "log-$prefix"
  containerEnv     = "cae-$prefix"
  registry         = "cr$prefix"
  solutionStorage  = "st$prefix"
  solutionSearch   = "srch-$prefix"
  solutionCosmos   = "cosmos-$prefix"
  foundryStorage   = "staif$prefix"
  foundrySearch    = "srch-aif-$prefix"
  foundryCosmos    = "cosmos-aif-$prefix"
  foundryAccount   = "aif-$prefix-$FoundrySuffix"
  foundryProject   = "proj-$prefix-$FoundrySuffix"
}

$ids = @{
  appConfig       = "$resourceGroupScope/providers/Microsoft.AppConfiguration/configurationStores/$($names.appConfig)"
  appInsights    = "$resourceGroupScope/providers/Microsoft.Insights/components/$($names.appInsights)"
  keyVault        = "$resourceGroupScope/providers/Microsoft.KeyVault/vaults/$($names.keyVault)"
  logAnalytics    = "$resourceGroupScope/providers/Microsoft.OperationalInsights/workspaces/$($names.logAnalytics)"
  containerEnv    = "$resourceGroupScope/providers/Microsoft.App/managedEnvironments/$($names.containerEnv)"
  registry        = "$resourceGroupScope/providers/Microsoft.ContainerRegistry/registries/$($names.registry)"
  solutionStorage = "$resourceGroupScope/providers/Microsoft.Storage/storageAccounts/$($names.solutionStorage)"
  solutionSearch  = "$resourceGroupScope/providers/Microsoft.Search/searchServices/$($names.solutionSearch)"
  solutionCosmos  = "$resourceGroupScope/providers/Microsoft.DocumentDB/databaseAccounts/$($names.solutionCosmos)"
  foundryAccount  = "$resourceGroupScope/providers/Microsoft.CognitiveServices/accounts/$($names.foundryAccount)"
  foundryProject  = "$resourceGroupScope/providers/Microsoft.CognitiveServices/accounts/$($names.foundryAccount)/projects/$($names.foundryProject)"
}

$appInsights = Get-ArmResource -ResourceId $ids.appInsights -ApiVersion "2020-02-02"
$foundryAccount = Get-ArmResource -ResourceId $ids.foundryAccount -ApiVersion "2025-06-01"
$foundryProject = Get-ArmResource -ResourceId $ids.foundryProject -ApiVersion "2025-06-01"

$containerApps = @(
  [pscustomobject]@{ service = "orchestrator"; canonical = "ORCHESTRATOR_APP"; targetPort = 80 },
  [pscustomobject]@{ service = "frontend"; canonical = "FRONTEND_APP"; targetPort = 80 },
  [pscustomobject]@{ service = "dataingest"; canonical = "DATA_INGEST_APP"; targetPort = 80 },
  [pscustomobject]@{ service = "mcp"; canonical = "MCP_APP"; targetPort = 80 }
)

$containerAppItems = foreach ($app in $containerApps) {
  $appName = "ca-$prefix-$($app.service)"
  $appInfo = Invoke-AzCliJson @(
    "containerapp",
    "show",
    "--resource-group", $ResourceGroupName,
    "--name", $appName,
    "--query", "{name:name,fqdn:properties.configuration.ingress.fqdn}"
  )

  [pscustomobject]@{
    name           = $appInfo.name
    fqdn           = $appInfo.fqdn
    external       = $true
    service_name   = $app.service
    profile_name   = "main"
    min_replicas   = 1
    max_replicas   = 1
    canonical_name = $app.canonical
  }
}

$items = [System.Collections.Generic.List[object]]::new()

foreach ($app in $containerAppItems) {
  Add-AppConfigItem -Items $items -Name "$($app.canonical_name)_ENDPOINT" -Value "https://$($app.fqdn)"
  Add-AppConfigItem -Items $items -Name "$($app.canonical_name)_NAME" -Value $app.name
}

Add-AppConfigItem -Items $items -Name "CHAT_DEPLOYMENT_NAME" -Value "chat"
Add-AppConfigItem -Items $items -Name "EMBEDDING_DEPLOYMENT_NAME" -Value "text-embedding"
Add-AppConfigItem -Items $items -Name "CONVERSATIONS_DATABASE_CONTAINER" -Value "conversations"
Add-AppConfigItem -Items $items -Name "DATASOURCES_DATABASE_CONTAINER" -Value "datasources"
Add-AppConfigItem -Items $items -Name "PROMPTS_CONTAINER" -Value "prompts"
Add-AppConfigItem -Items $items -Name "MCP_CONTAINER" -Value "mcp"
Add-AppConfigItem -Items $items -Name "DOCUMENTS_IMAGES_STORAGE_CONTAINER" -Value "documents-images"
Add-AppConfigItem -Items $items -Name "DOCUMENTS_STORAGE_CONTAINER" -Value "documents"
Add-AppConfigItem -Items $items -Name "NL2SQL_STORAGE_CONTAINER" -Value "nl2sql"
Add-AppConfigItem -Items $items -Name "AZURE_TENANT_ID" -Value $TenantId
Add-AppConfigItem -Items $items -Name "SUBSCRIPTION_ID" -Value $SubscriptionId
Add-AppConfigItem -Items $items -Name "AZURE_RESOURCE_GROUP" -Value $ResourceGroupName
Add-AppConfigItem -Items $items -Name "LOCATION" -Value $Location
Add-AppConfigItem -Items $items -Name "ENVIRONMENT_NAME" -Value $EnvironmentName
Add-AppConfigItem -Items $items -Name "DEPLOYMENT_NAME" -Value "terraform-$prefix"
Add-AppConfigItem -Items $items -Name "RESOURCE_TOKEN" -Value $prefix
Add-AppConfigItem -Items $items -Name "NETWORK_ISOLATION" -Value $NetworkIsolation
Add-AppConfigItem -Items $items -Name "USE_UAI" -Value "true"
Add-AppConfigItem -Items $items -Name "USE_CAPP_API_KEY" -Value "false"
Add-AppConfigItem -Items $items -Name "LOG_LEVEL" -Value "INFO"
Add-AppConfigItem -Items $items -Name "ENABLE_CONSOLE_LOGGING" -Value "true"
Add-AppConfigItem -Items $items -Name "PROMPT_SOURCE" -Value "file"
Add-AppConfigItem -Items $items -Name "GPT_RAG_RELEASE" -Value "2.1.2"
Add-AppConfigItem -Items $items -Name "APPLICATIONINSIGHTS_CONNECTION_STRING" -Value $appInsights.properties.ConnectionString
Add-AppConfigItem -Items $items -Name "APPLICATIONINSIGHTS__INSTRUMENTATIONKEY" -Value $appInsights.properties.InstrumentationKey
Add-AppConfigItem -Items $items -Name "AGENT_STRATEGY" -Value "single_agent_rag"
Add-AppConfigItem -Items $items -Name "KEY_VAULT_RESOURCE_ID" -Value $ids.keyVault
Add-AppConfigItem -Items $items -Name "STORAGE_ACCOUNT_RESOURCE_ID" -Value $ids.solutionStorage
Add-AppConfigItem -Items $items -Name "APP_INSIGHTS_RESOURCE_ID" -Value $ids.appInsights
Add-AppConfigItem -Items $items -Name "LOG_ANALYTICS_RESOURCE_ID" -Value $ids.logAnalytics
Add-AppConfigItem -Items $items -Name "CONTAINER_ENV_RESOURCE_ID" -Value $ids.containerEnv
Add-AppConfigItem -Items $items -Name "AI_FOUNDRY_ACCOUNT_RESOURCE_ID" -Value $ids.foundryAccount
Add-AppConfigItem -Items $items -Name "AI_FOUNDRY_PROJECT_RESOURCE_ID" -Value $ids.foundryProject
Add-AppConfigItem -Items $items -Name "COSMOS_DB_ACCOUNT_RESOURCE_ID" -Value $ids.solutionCosmos
Add-AppConfigItem -Items $items -Name "AI_FOUNDRY_PROJECT_WORKSPACE_ID" -Value $foundryProject.properties.internalId
Add-AppConfigItem -Items $items -Name "SEARCH_SERVICE_UAI_RESOURCE_ID" -Value ""
Add-AppConfigItem -Items $items -Name "SEARCH_SERVICE_RESOURCE_ID" -Value $ids.solutionSearch
Add-AppConfigItem -Items $items -Name "AI_FOUNDRY_ACCOUNT_NAME" -Value $names.foundryAccount
Add-AppConfigItem -Items $items -Name "AI_FOUNDRY_PROJECT_NAME" -Value $names.foundryProject
Add-AppConfigItem -Items $items -Name "AI_FOUNDRY_STORAGE_ACCOUNT_NAME" -Value $names.foundryStorage
Add-AppConfigItem -Items $items -Name "APP_CONFIG_NAME" -Value $names.appConfig
Add-AppConfigItem -Items $items -Name "APP_INSIGHTS_NAME" -Value $names.appInsights
Add-AppConfigItem -Items $items -Name "CONTAINER_ENV_NAME" -Value $names.containerEnv
Add-AppConfigItem -Items $items -Name "CONTAINER_REGISTRY_NAME" -Value $names.registry
Add-AppConfigItem -Items $items -Name "DATABASE_ACCOUNT_NAME" -Value $names.solutionCosmos
Add-AppConfigItem -Items $items -Name "DATABASE_NAME" -Value "gptragdb"
Add-AppConfigItem -Items $items -Name "SEARCH_SERVICE_NAME" -Value $names.solutionSearch
Add-AppConfigItem -Items $items -Name "STORAGE_ACCOUNT_NAME" -Value $names.solutionStorage
Add-AppConfigItem -Items $items -Name "CONTAINER_REGISTRY_LOGIN_SERVER" -Value "$($names.registry).azurecr.io"
Add-AppConfigItem -Items $items -Name "DEPLOY_APP_CONFIG" -Value "true"
Add-AppConfigItem -Items $items -Name "DEPLOY_KEY_VAULT" -Value "true"
Add-AppConfigItem -Items $items -Name "DEPLOY_LOG_ANALYTICS" -Value "true"
Add-AppConfigItem -Items $items -Name "DEPLOY_APP_INSIGHTS" -Value "true"
Add-AppConfigItem -Items $items -Name "DEPLOY_SEARCH_SERVICE" -Value "true"
Add-AppConfigItem -Items $items -Name "DEPLOY_STORAGE_ACCOUNT" -Value "true"
Add-AppConfigItem -Items $items -Name "DEPLOY_COSMOS_DB" -Value "true"
Add-AppConfigItem -Items $items -Name "DEPLOY_CONTAINER_APPS" -Value "true"
Add-AppConfigItem -Items $items -Name "DEPLOY_CONTAINER_REGISTRY" -Value "true"
Add-AppConfigItem -Items $items -Name "DEPLOY_CONTAINER_ENV" -Value "true"
Add-AppConfigItem -Items $items -Name "KEY_VAULT_URI" -Value "https://$($names.keyVault).vault.azure.net/"
Add-AppConfigItem -Items $items -Name "STORAGE_BLOB_ENDPOINT" -Value "https://$($names.solutionStorage).blob.core.windows.net/"
Add-AppConfigItem -Items $items -Name "AI_FOUNDRY_ACCOUNT_ENDPOINT" -Value "https://$($names.foundryAccount).cognitiveservices.azure.com/"
Add-AppConfigItem -Items $items -Name "AI_FOUNDRY_PROJECT_ENDPOINT" -Value "https://$($names.foundryAccount).services.ai.azure.com/api/projects/$($names.foundryProject)"
Add-AppConfigItem -Items $items -Name "COSMOS_DB_ENDPOINT" -Value "https://$($names.solutionCosmos).documents.azure.com:443/"
Add-AppConfigItem -Items $items -Name "SEARCH_SERVICE_QUERY_ENDPOINT" -Value "https://$($names.solutionSearch).search.windows.net"
Add-AppConfigItem -Items $items -Name "SEARCH_CONNECTION_ID" -Value "$($ids.foundryProject)/connections/$($names.foundryAccount)-connection"
Add-AppConfigItem -Items $items -Name "BING_CONNECTION_ID" -Value ""
Add-AppConfigItem -Items $items -Name "AI_FOUNDRY_ACCOUNT_PRINCIPAL_ID" -Value $foundryAccount.identity.principalId
Add-AppConfigItem -Items $items -Name "AI_FOUNDRY_PROJECT_PRINCIPAL_ID" -Value $foundryProject.identity.principalId
Add-AppConfigItem -Items $items -Name "CONTAINER_ENV_PRINCIPAL_ID" -Value ""
Add-AppConfigItem -Items $items -Name "SEARCH_SERVICE_PRINCIPAL_ID" -Value ""
Add-AppConfigItem -Items $items -Name "AI_FOUNDRY_STORAGE_CONNECTION" -Value $names.foundryStorage
Add-AppConfigItem -Items $items -Name "AI_FOUNDRY_COSMOS_DB_CONNECTION" -Value $names.foundryCosmos
Add-AppConfigItem -Items $items -Name "AI_FOUNDRY_SEARCH_CONNECTION" -Value $names.solutionSearch
Add-AppConfigItem -Items $items -Name "CONTAINER_APPS" -Value ($containerAppItems | ConvertTo-Json -Depth 8 -Compress) -ContentType "application/json"
Add-AppConfigItem -Items $items -Name "MODEL_DEPLOYMENTS" -Value (@(
    @{
      name           = "chat"
      model          = "gpt-4o"
      modelFormat    = "OpenAI"
      type           = "GlobalStandard"
      version        = "2024-11-20"
      apiVersion     = "2025-01-01-preview"
      capacity       = 8
      canonical_name = "CHAT_DEPLOYMENT_NAME"
    },
    @{
      name           = "text-embedding"
      model          = "text-embedding-3-large"
      modelFormat    = "OpenAI"
      type           = "Standard"
      version        = "1"
      apiVersion     = "2025-01-01-preview"
      capacity       = 8
      canonical_name = "EMBEDDING_DEPLOYMENT_NAME"
    }
  ) | ConvertTo-Json -Depth 8 -Compress) -ContentType "application/json"
Add-AppConfigItem -Items $items -Name "SEARCH_API_VERSION" -Value "2025-05-01-preview"
Add-AppConfigItem -Items $items -Name "SEARCH_ANALYZER_NAME" -Value "standard.lucene"
Add-AppConfigItem -Items $items -Name "EMBEDDINGS_VECTOR_DIMENSIONS" -Value "3072"
Add-AppConfigItem -Items $items -Name "SEARCH_RAG_INDEX_NAME" -Value "ragindex-$prefix"
Add-AppConfigItem -Items $items -Name "SEARCH_QUERIES_INDEX_NAME" -Value "nl2sql-$prefix-queries"
Add-AppConfigItem -Items $items -Name "SEARCH_TABLES_INDEX_NAME" -Value "nl2sql-$prefix-tables"
Add-AppConfigItem -Items $items -Name "SEARCH_MEASURES_INDEX_NAME" -Value "nl2sql-$prefix-measures"
Add-AppConfigItem -Items $items -Name "CRON_RUN_BLOB_PURGE" -Value "0 * * * *" -ItemLabel $IngestionLabel
Add-AppConfigItem -Items $items -Name "CRON_RUN_BLOB_INDEX" -Value "10 * * * *" -ItemLabel $IngestionLabel

Write-Host "Writing $($items.Count) App Configuration key-values to $($names.appConfig)..."
foreach ($item in $items) {
  Set-AppConfigKeyValue -StoreResourceId $ids.appConfig -Item $item -ConnectionString $ConnectionString
}

Write-Host "Done. Restart the Container Apps so they reload App Configuration."
