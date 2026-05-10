[CmdletBinding()]
param(
  [string]$TerraformDirectory = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$VarFile = "terraform.zta-fresh.tfvars",
  [string]$StateFile = "terraform-zta-fresh.tfstate",
  [string]$OutFile = "tfplan-appconfig-keys"
)

$ErrorActionPreference = "Stop"

Push-Location $TerraformDirectory
try {
  & terraform plan `
    "-var-file=$VarFile" `
    "-state=$StateFile" `
    "-target=azapi_resource.app_config_keys" `
    "-out=$OutFile"

  exit $LASTEXITCODE
}
finally {
  Pop-Location
}
