param(
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,
  [string]$PlanFile = "tfplan-containerapps-private"
)

$ErrorActionPreference = "Stop"

az login --identity | Out-Null
az account set --subscription $SubscriptionId

terraform init

terraform plan `
  -refresh=false `
  -out $PlanFile `
  -var "enable_zero_trust=true" `
  -var "disable_public_network_access=false" `
  -var "container_apps_internal_only=false" `
  -var "enable_container_apps_private_environment=true" `
  -var "enable_bastion=true" `
  -var "enable_jumpbox=true" `
  -var "deploy_jumpbox_software=true" `
  -var "enable_jumpbox_nat_gateway=true"

terraform show -no-color $PlanFile | Select-String -Pattern "Plan:|must be replaced|will be destroyed|azurerm_container_app_environment|azurerm_container_app\.|public_network_access|disable_public" -Context 0,3
