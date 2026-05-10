param(
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,
  [Parameter(Mandatory = $true)]
  [string]$ResourceGroupName,
  [Parameter(Mandatory = $true)]
  [string]$VmName,
  [Parameter(Mandatory = $true)]
  [string]$StorageAccountName,
  [string]$ContainerName = "jumpbox-workspace",
  [string]$BlobName = "gpt-rag-terraform-workspace.zip",
  [string]$Destination = "C:\github\gpt-rag-terraform"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..\..")
$tempRoot = Join-Path $env:TEMP ("gpt-rag-workspace-" + [guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $tempRoot "workspace"
$zipPath = Join-Path $tempRoot $BlobName

Write-Host "Packaging workspace from $repoRoot"
New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null

$includePaths = @(
  "terraform",
  "test-documents"
)

foreach ($relativePath in $includePaths) {
  $source = Join-Path $repoRoot $relativePath
  if (Test-Path $source) {
    $target = Join-Path $packageRoot $relativePath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -Path $source -Destination $target -Recurse -Force
  }
}

$excludePatterns = @(
  "\.terraform",
  "terraform\.tfstate",
  "terraform\.tfstate\.backup",
  "tfplan",
  "\.terraform\.tfstate\.lock\.info",
  "plan.*\.txt",
  "plan_.*\.txt",
  ".*\.zip",
  ".*\.pem",
  ".*\.pfx",
  ".*\.key"
)

Get-ChildItem -Path $packageRoot -Recurse -Force | Where-Object {
  $path = $_.FullName
  $excludePatterns | Where-Object { $path -match $_ }
} | Sort-Object FullName -Descending | ForEach-Object {
  Remove-Item -LiteralPath $_.FullName -Recurse -Force
}

Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $zipPath -Force

Write-Host "Uploading $zipPath to $StorageAccountName/$ContainerName/$BlobName"
az account set --subscription $SubscriptionId
az storage container create `
  --account-name $StorageAccountName `
  --name $ContainerName `
  --auth-mode login `
  --public-access off `
  -o none

az storage blob upload `
  --account-name $StorageAccountName `
  --container-name $ContainerName `
  --name $BlobName `
  --file $zipPath `
  --auth-mode login `
  --overwrite true `
  -o none

$syncScript = @"
`$ErrorActionPreference = "Stop"
`$storage = "$StorageAccountName"
`$container = "$ContainerName"
`$blob = "$BlobName"
`$destination = "$Destination"
`$zip = "C:\WindowsAzure\Logs\$BlobName"

az login --identity | Out-Null
az account set --subscription $SubscriptionId
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
  choco install terraform -y --ignoredetectedreboot --force
}
New-Item -ItemType Directory -Force -Path (Split-Path `$zip) | Out-Null
New-Item -ItemType Directory -Force -Path `$destination | Out-Null
az storage blob download --account-name `$storage --container-name `$container --name `$blob --file `$zip --auth-mode login --overwrite true | Out-Null
Expand-Archive -Path `$zip -DestinationPath `$destination -Force
Write-Host "Workspace synced to `$destination"
"@

Write-Host "Triggering immediate sync on $VmName"
$runScriptPath = Join-Path $tempRoot "sync-workspace.ps1"
Set-Content -Path $runScriptPath -Value $syncScript -Encoding UTF8
az vm run-command invoke `
  --resource-group $ResourceGroupName `
  --name $VmName `
  --command-id RunPowerShellScript `
  --scripts "@$runScriptPath" `
  --query "value[0].message" `
  -o tsv

Write-Host "Done. Package uploaded and sync command invoked."
Write-Host "Workspace destination: $Destination"

Remove-Item -LiteralPath $tempRoot -Recurse -Force
