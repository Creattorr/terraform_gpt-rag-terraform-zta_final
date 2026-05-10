param(
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,
  [Parameter(Mandatory = $true)]
  [string]$ResourceGroupName,
  [Parameter(Mandatory = $true)]
  [string]$ContainerAppEnvironmentName,
  [Parameter(Mandatory = $true)]
  [string]$ResourcePrefix,
  [Parameter(Mandatory = $true)]
  [string]$DaprApiToken
)

$ErrorActionPreference = "Continue"

az login --identity | Out-Null
az account set --subscription $SubscriptionId

$environment = az containerapp env show `
  --resource-group $ResourceGroupName `
  --name $ContainerAppEnvironmentName `
  --query "{defaultDomain:properties.defaultDomain,staticIp:properties.staticIp,internal:properties.vnetConfiguration.internal,provisioningState:properties.provisioningState}" `
  -o json | ConvertFrom-Json

Write-Host "=== Container Apps Environment ==="
$environment | ConvertTo-Json -Depth 5

$apps = @(
  "ca-$ResourcePrefix-frontend",
  "ca-$ResourcePrefix-orchestrator",
  "ca-$ResourcePrefix-dataingest",
  "ca-$ResourcePrefix-mcp"
)

Write-Host ""
Write-Host "=== App State ==="
foreach ($app in $apps) {
  az containerapp show `
    --resource-group $ResourceGroupName `
    --name $app `
    --query "{name:name,provisioningState:properties.provisioningState,runningStatus:properties.runningStatus,revision:properties.latestRevisionName,external:properties.configuration.ingress.external,fqdn:properties.configuration.ingress.fqdn,targetPort:properties.configuration.ingress.targetPort}" `
    -o json | ConvertFrom-Json | ConvertTo-Json -Depth 5
}

Write-Host ""
Write-Host "=== DNS and HTTP ==="
foreach ($app in $apps) {
  $fqdn = az containerapp show `
    --resource-group $ResourceGroupName `
    --name $app `
    --query "properties.configuration.ingress.fqdn" `
    -o tsv

  Write-Host ""
  Write-Host $fqdn
  Resolve-DnsName $fqdn | Where-Object { $_.IPAddress -or $_.NameHost } | Format-Table Name,Type,IPAddress,NameHost -AutoSize

  try {
    $response = Invoke-WebRequest -Uri "https://$fqdn" -UseBasicParsing -TimeoutSec 30
    Write-Host "HTTP $($response.StatusCode)"
  }
  catch {
    $statusCode = $null
    if ($_.Exception.Response) {
      $statusCode = [int]$_.Exception.Response.StatusCode
    }

    if ($statusCode) {
      Write-Host "HTTP $statusCode"
    }
    else {
      Write-Host "HTTP ERROR $($_.Exception.Message)"
    }
  }
}

Write-Host ""
Write-Host "=== Orchestrator Smoke Test ==="
$orchestratorFqdn = az containerapp show `
  --resource-group $ResourceGroupName `
  --name "ca-$ResourcePrefix-orchestrator" `
  --query "properties.configuration.ingress.fqdn" `
  -o tsv

$body = @{
  ask          = "What is the unique validation phrase in the Terraform smoke test document?"
  user_context = @{}
} | ConvertTo-Json

try {
  $response = Invoke-WebRequest `
    -Uri "https://$orchestratorFqdn/orchestrator" `
    -Method Post `
    -ContentType "application/json" `
    -Headers @{ "dapr-api-token" = $DaprApiToken } `
    -Body $body `
    -UseBasicParsing `
    -TimeoutSec 120

  Write-Host "HTTP $($response.StatusCode)"
  Write-Host $response.Content
}
catch {
  Write-Host "ORCHESTRATOR ERROR $($_.Exception.Message)"
  if ($_.Exception.Response) {
    Write-Host "HTTP $([int]$_.Exception.Response.StatusCode)"
  }
}
