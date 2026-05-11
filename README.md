# GPT-RAG Terraform Replica Test

This folder is a clean Terraform replication project for testing whether the GPT-RAG zero-trust deployment is general enough to ship to another environment.

It intentionally excludes local state files, saved plans, PEM keys, logs, and subscription-specific values from the working deployment.

## What Is Included

```text
terraform/
  main.tf
  providers.tf
  versions.tf
  variables.tf
  outputs.tf
  terraform.tfvars.example
  backend.hcl.example
  scripts/
test-documents/
README.md
```

Important helper script:

```text
terraform/scripts/create-foundry-capability-hosts-vm.ps1
```

Keep that helper with the project. It is used only if Terraform cannot create/read Azure AI Foundry capability hosts cleanly, or if you need to repair that path from inside the VNet through the jumpbox managed identity.

## Deployment Model

This is a staged deployment:

1. Run Terraform locally to create the foundation with placeholder images.
2. Build and push GPT-RAG images to the new ACR.
3. Apply the real image values.
4. Create Foundry capability hosts.
5. Run private/data-plane steps through VM Run Command.
6. Validate the app from the jumpbox/Bastion path.

Do not expect every private-network/data-plane task to work from your local workstation. In zero-trust mode, some operations must run inside the VNet.

## Helper Script Inventory

The `terraform/scripts` folder contains both normal deployment helpers and troubleshooting scripts. Some were created while hardening the zero-trust path, so not every script is part of the happy path.

| Script | Purpose | Run From |
| --- | --- | --- |
| `create-rag-search-index.ps1` | Creates the GPT-RAG Azure AI Search index used by ingestion and retrieval. Use after infrastructure exists and before validating ingestion. | Local first; VM Run Command if Search data-plane access is private-only. |
| `set-gpt-rag-appconfig-arm.ps1` | Writes GPT-RAG App Configuration keys for orchestrator, UI, ingestion, MCP, Foundry, Search, Storage, and runtime settings. This is the main App Config helper when Terraform data-plane writes are disabled or blocked. | Prefer VM Run Command in zero-trust deployments. |
| `create-foundry-capability-hosts-vm.ps1` | Creates or repairs Azure AI Foundry account/project capability hosts for Agents using the jumpbox managed identity and ARM REST. Use only if Terraform cannot create capability hosts cleanly. | VM Run Command. |
| `publish-workspace-to-jumpbox.ps1` | Packages the Terraform workspace, uploads it to private Storage, and triggers jumpbox download/extract so the VM has the same scripts and tfvars. Useful when you want to work from the VM. | Local. |
| `validate-zero-trust-jumpbox.ps1` | Validates private DNS, Storage, Search, App Config, ACR, Key Vault, Foundry, Cosmos, and smoke Search query from inside the VNet. | VM/jumpbox. |
| `validate-private-containerapps.ps1` | Checks Container Apps environment state, app ingress/FQDNs, DNS resolution, HTTP reachability, and orchestrator smoke call. | VM/jumpbox. |
| `diagnose-private-endpoint-connectivity.ps1` | Lightweight DNS and TCP 443 test for any private endpoint hostnames you pass in. | VM/jumpbox preferred. |
| `diagnose-search-private-endpoints.ps1` | Search-specific DNS, TCP, and HTTPS probe for Search private endpoint hostnames. | VM/jumpbox preferred. |
| `probe-orchestrator-routes.ps1` | Quickly probes common orchestrator routes such as `/`, `/orchestrator`, `/docs`, `/openapi.json`, `/health`, and `/healthz`. | Local for public ingress; VM for private ingress. |
| `plan-containerapps-private.ps1` | Generates a targeted plan for moving Container Apps into the private Container Apps environment. Mostly useful for migration or debugging. | VM/jumpbox or local with Terraform access. |
| `apply-containerapps-private.ps1` | Applies the plan created by `plan-containerapps-private.ps1` and prints Container Apps environment/app status. Mostly useful for migration or debugging. | VM/jumpbox or local with Terraform access. |
| `plan-appconfig-keys.ps1` | Creates a targeted Terraform plan for only App Configuration keys. Useful when testing whether Terraform can own App Config data-plane writes. | Local or VM depending on App Config network access. |
| `plan-foundry-f2-targeted-integrate.ps1` | Creates a targeted plan for Foundry integration resources, connections, and role assignments. Useful for recovering a partially completed Foundry deployment. | Local or VM with correct RBAC. |
| `resume-foundry-zta-rebuild.ps1` | Checks jumpbox managed identity RBAC and can run targeted Check/Plan/Apply for Foundry rebuild recovery. Use only during failed/stuck Foundry ZTA rebuilds. | Local wrapper plus VM Terraform workspace. |
| `plan-search-standard-rebuild.ps1` | Targeted plan for rebuilding Search-related resources and role assignments, especially when moving from Basic to Standard or fixing Foundry Search dependencies. | Local or VM with correct RBAC. |

For a clean replica test, the scripts you are most likely to use are:

```text
create-rag-search-index.ps1
set-gpt-rag-appconfig-arm.ps1
create-foundry-capability-hosts-vm.ps1
validate-zero-trust-jumpbox.ps1
validate-private-containerapps.ps1
```

## Prerequisites

Install or verify these locally:

```powershell
# Confirm Azure CLI is installed and usable.
az version

# Confirm Terraform is installed. This repo requires Terraform >= 1.7.0.
terraform version

# Confirm Git is available for cloning or managing the repo.
git --version
```

Login:

```powershell
# Sign in to the tenant where the replica environment will be deployed.
az login --tenant "<tenant-id>"

# Select the target subscription so all az commands use the same subscription as Terraform.
az account set --subscription "<subscription-id>"
```

Make sure the subscription has quota for:

```text
Azure Container Apps
Azure Container Registry
Azure AI Foundry / Cognitive Services
Azure OpenAI model deployments
Azure AI Search
Cosmos DB
Storage
Azure Bastion
Windows Data Science VM
NAT Gateway
Private Endpoints
```

## Stage 0: Prepare Files

From the replica project root:

```powershell
# Move into the clean replica project.
cd .\gpt-rag-terraform-replica

# Create the real tfvars file from the template.
# terraform.tfvars is intentionally gitignored because it contains environment-specific values.
Copy-Item .\terraform\terraform.tfvars.example .\terraform\terraform.tfvars
```

Edit `terraform\terraform.tfvars`:

```hcl
subscription_id     = "<subscription-id>"
tenant_id           = "<tenant-id>"
location            = "swedencentral"
environment_name    = "gptragtest"
resource_group_name = "rg-gptragtest-zta-01"
```

For the first apply, keep these values:

```hcl
# Placeholder images let Terraform create ACR and Container Apps before custom GPT-RAG images exist.
frontend_image     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
orchestrator_image = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
dataingest_image   = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
mcp_image          = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"

# App Config keys are populated later through the helper so private/data-plane access does not block the first apply.
manage_app_config_keys             = false

# Start false so the foundation is created first. Turn true in Stage 4 to test Terraform ownership.
enable_ai_foundry_capability_hosts = false

# Install baseline jumpbox tools at VM creation without depending on winget:
# PowerShell 7, Azure CLI, Azure Developer CLI, Git, and Python 3.12.
install_jumpbox_powershell7       = true
jumpbox_python312_version         = "3.12.10"
deploy_jumpbox_software            = false

# Keep public network access open until private endpoints, DNS, and jumpbox validation are working.
disable_public_network_access      = false
```

`install_jumpbox_powershell7 = true` adds a VM extension that installs the required jumpbox tools when the Windows VM is created. The extension downloads `terraform/scripts/install-jumpbox-required-tools.ps1` and installs PowerShell 7, Azure CLI, Azure Developer CLI, Git, and Python 3.12 using official installers/scripts instead of `winget`. This is important because Windows Server images often do not include `winget`.

Azure VM Run Command still starts in Windows PowerShell 5.1 by default, so call `pwsh.exe` explicitly for scripts that require PowerShell 7.

Verify the toolchain from VM Run Command:

```powershell
az vm run-command invoke `
  -g "<resource-group>" `
  -n "<jumpbox-vm-name>" `
  --command-id RunPowerShellScript `
  --scripts @"
pwsh.exe -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
az version --query '\"azure-cli\"' -o tsv
azd version
git --version
python --version
"@ `
  --query "value[].message" `
  -o tsv
```

## Stage 1: Terraform Foundation Apply

Run:

```powershell
# Enter the Terraform working directory.
cd .\terraform

# Initialize providers without a remote backend.
# -backend=false keeps the replica test local and avoids requiring a pre-created state storage account.
terraform init -backend=false

# Format Terraform files consistently.
terraform fmt

# Validate Terraform syntax and provider schema locally before planning.
terraform validate

# Build a saved plan using the environment-specific tfvars file.
# -var-file points Terraform at your copied terraform.tfvars.
# -out saves the exact plan so apply runs the same actions that were reviewed.
terraform plan -var-file="terraform.tfvars" -out="tfplan-foundation"

# Apply the reviewed foundation plan.
terraform apply "tfplan-foundation"
```

Capture the outputs:

```powershell
# Capture frequently used Terraform outputs into PowerShell variables for later commands.
$rg = terraform output -raw resource_group_name
$acrLoginServer = terraform output -raw container_registry_login_server

# Convert crxxxx.azurecr.io to the ACR resource name crxxxx.
$acrName = $acrLoginServer.Split('.')[0]
$jumpboxName = terraform output -raw jumpbox_vm_name
$frontendUrl = terraform output -raw frontend_url

# Print the values so you can confirm the environment before continuing.
Write-Host "RG: $rg"
Write-Host "ACR: $acrName"
Write-Host "Jumpbox: $jumpboxName"
Write-Host "Frontend: $frontendUrl"
```

## Stage 2: Build and Push GPT-RAG Images

The Terraform project does not contain the application source. Use one of these layouts:

```text
<workspace>\gpt-rag-terraform-replica\
<workspace>\components\gpt-rag-ui\
<workspace>\components\gpt-rag-orchestrator\
<workspace>\components\gpt-rag-ingestion\
<workspace>\components\gpt-rag-mcp\
```

Or clone the four component repositories from Azure/GPT-RAG into any folder and update the paths below.

From the folder that contains `components`:

```powershell
# Use the ACR name returned by Terraform, not the login server.
$acrName = "<acr-name-from-terraform-output>"

# Build each component inside Azure Container Registry.
# az acr build avoids needing local Docker and pushes the image directly to ACR.
# --registry selects the target ACR.
# --image sets repository:tag.
# The final path is the Docker build context for that component.
az acr build --registry $acrName --image gpt-rag-ui:v2.1.0 ..\..\components\gpt-rag-ui
az acr build --registry $acrName --image gpt-rag-orchestrator:v2.1.0 ..\..\components\gpt-rag-orchestrator
az acr build --registry $acrName --image gpt-rag-ingestion:v2.0.5 ..\..\components\gpt-rag-ingestion
az acr build --registry $acrName --image gpt-rag-mcp:v0.2.2 ..\..\components\gpt-rag-mcp
```

Verify:

```powershell
# Confirm the expected tags exist in the new ACR before updating Terraform image values.
# -n is the ACR resource name.
# --repository is the image repository to inspect.
# -o table keeps the output readable.
az acr repository show-tags -n $acrName --repository gpt-rag-ui -o table
az acr repository show-tags -n $acrName --repository gpt-rag-orchestrator -o table
az acr repository show-tags -n $acrName --repository gpt-rag-ingestion -o table
az acr repository show-tags -n $acrName --repository gpt-rag-mcp -o table
```

## Stage 3: Apply Real Container Images

Edit `terraform\terraform.tfvars` and replace the four image values:

```hcl
frontend_image     = "<acr-login-server>/gpt-rag-ui:v2.1.0"
orchestrator_image = "<acr-login-server>/gpt-rag-orchestrator:v2.1.0"
dataingest_image   = "<acr-login-server>/gpt-rag-ingestion:v2.0.5"
mcp_image          = "<acr-login-server>/gpt-rag-mcp:v0.2.2"
```

Apply:

```powershell
# Plan only the changes caused by replacing placeholder images with real ACR images.
terraform plan -var-file="terraform.tfvars" -out="tfplan-images"

# Apply the saved image update plan.
terraform apply "tfplan-images"
```

Verify the apps:

```powershell
# List all Container Apps with runtime status, image, and ingress FQDN.
# --query projects only the fields that matter for the deployment check.
az containerapp list -g $rg `
  --query "[].{name:name,running:properties.runningStatus,image:properties.template.containers[0].image,fqdn:properties.configuration.ingress.fqdn}" `
  -o table
```

## Stage 4: Create Foundry Capability Hosts

First test the clean Terraform path.

Edit `terraform\terraform.tfvars`:

```hcl
# Turn on Terraform-managed Foundry Agents capability hosts for the clean-environment test.
enable_ai_foundry_capability_hosts = true
```

Run:

```powershell
# Create a focused saved plan for capability hosts.
terraform plan -var-file="terraform.tfvars" -out="tfplan-foundry-capability-hosts"

# Apply it. If this works, Terraform can own the capability hosts in a fresh deployment.
terraform apply "tfplan-foundry-capability-hosts"
```

If this succeeds, keep the flag `true`. This means the code is general enough for Terraform to own those resources in the new environment.

If it fails because of preview API timeout, local identity permissions, or a provider inconsistency, use the VM Run Command fallback in the next section.

## Stage 4B: Capability Host Fallback Through VM Run Command

Use this only if Stage 4 fails.

Set the flag back to false so future local plans do not repeatedly try the failed create:

```hcl
# Fallback mode: keep Terraform from retrying a failing/conflicting capability host create.
enable_ai_foundry_capability_hosts = false
```

Apply the no-capability-host state:

```powershell
# Save and apply a plan that records the fallback decision in Terraform inputs.
terraform plan -var-file="terraform.tfvars" -out="tfplan-disable-capability-hosts"
terraform apply "tfplan-disable-capability-hosts"
```

Get values:

```powershell
# Subscription id is passed explicitly into the VM-side helper.
$subscriptionId = "<subscription-id>"

# Pull reusable names from Terraform outputs so the commands stay environment-neutral.
$rg = terraform output -raw resource_group_name
$jumpboxName = terraform output -raw jumpbox_vm_name
$accountName = terraform output -raw ai_foundry_account_name
$projectName = terraform output -raw ai_foundry_project_name

# Read the AI Foundry agents subnet id. The capability host needs this subnet for private agent networking.
# --query id returns only the subnet resource id.
# -o tsv removes JSON quotes so the value can be passed directly as a parameter.
$subnetId = az network vnet subnet show `
  -g $rg `
  --vnet-name ((terraform output -raw zero_trust_virtual_network_name)) `
  -n ("snet-" + (terraform output -raw resource_prefix) + "-ai-agents") `
  --query id `
  -o tsv
```

Run the helper from local, executed on the jumpbox:

```powershell
# Execute a local script on the private jumpbox through Azure VM Run Command.
# -g selects the resource group.
# -n selects the VM name.
# --command-id RunPowerShellScript tells Azure to run PowerShell on the Windows VM.
# --scripts "@path" uploads and runs the local script file.
# --parameters passes named values into the script.
# --query "value[].message" returns only script output instead of the full Run Command envelope.
# -o tsv keeps the output readable in PowerShell.
az vm run-command invoke `
  -g $rg `
  -n $jumpboxName `
  --command-id RunPowerShellScript `
  --scripts "@.\scripts\create-foundry-capability-hosts-vm.ps1" `
  --parameters `
    "SubscriptionId=$subscriptionId" `
    "ResourceGroupName=$rg" `
    "AccountName=$accountName" `
    "ProjectName=$projectName" `
    "CustomerSubnetId=$subnetId" `
    "VectorStoreConnectionName=srch-aif-$(terraform output -raw resource_prefix)" `
    "StorageConnectionName=staif$(terraform output -raw resource_prefix)" `
    "ThreadStorageConnectionName=cosmos-aif-$(terraform output -raw resource_prefix)" `
  --query "value[].message" `
  -o tsv
```

Expected final project host state:

```text
caphostproj Succeeded
```

If you used the fallback, leave this value false:

```hcl
enable_ai_foundry_capability_hosts = false
```

## Stage 5: Populate App Configuration from the Jumpbox

In zero-trust mode, local data-plane writes to App Configuration may be blocked. Use VM Run Command.

From `terraform`:

```powershell
# Pass subscription and tenant explicitly because VM Run Command starts in a fresh PowerShell session.
$subscriptionId = "<subscription-id>"
$tenantId = "<tenant-id>"

# Pull the environment-specific names from Terraform outputs.
$rg = terraform output -raw resource_group_name
$jumpboxName = terraform output -raw jumpbox_vm_name
$prefix = terraform output -raw resource_prefix
$location = "<location-from-tfvars>"

# Leave empty unless ai_foundry_rebuild_suffix was set in terraform.tfvars.
$foundrySuffix = ""

# Fetch an App Configuration connection string for the helper.
# This avoids local App Config data-plane writes when public network access is restricted.
# --query "[0].connectionString" returns the first available connection string.
$conn = az appconfig credential list `
  -g $rg `
  -n "appcs-$prefix" `
  --query "[0].connectionString" `
  -o tsv

# Run the App Config helper inside the VNet through the jumpbox.
# NetworkIsolation=true writes private/ZTA-aware GPT-RAG settings.
# LoginWithManagedIdentity=true makes the VM use its managed identity for Azure ARM lookups.
az vm run-command invoke `
  -g $rg `
  -n $jumpboxName `
  --command-id RunPowerShellScript `
  --scripts "@.\scripts\set-gpt-rag-appconfig-arm.ps1" `
  --parameters `
    "SubscriptionId=$subscriptionId" `
    "TenantId=$tenantId" `
    "ResourceGroupName=$rg" `
    "Location=$location" `
    "EnvironmentName=gptrag" `
    "ResourcePrefix=$prefix" `
    "FoundrySuffix=$foundrySuffix" `
    "NetworkIsolation=true" `
    "ConnectionString=$conn" `
    "LoginWithManagedIdentity=true" `
  --query "value[].message" `
  -o tsv
```

Restart apps:

```powershell
# Restart the active revision of every Container App so they reload App Configuration and secrets.
# The inner revision list picks the currently active revision for each app.
az containerapp list -g $rg --query "[].name" -o tsv | ForEach-Object {
  az containerapp revision restart -g $rg -n $_ --revision (az containerapp revision list -g $rg -n $_ --query "[?properties.active].name | [0]" -o tsv)
}
```

## Stage 6: Create the RAG Search Index

Run locally:

```powershell
# Create the Azure AI Search index used by GPT-RAG ingestion.
# ResourceGroupName identifies the deployment resource group.
# SearchServiceName is the solution Search service, not the separate Foundry dependency Search service.
# IndexName should match the RAG index configured in App Configuration.
.\scripts\create-rag-search-index.ps1 `
  -ResourceGroupName $rg `
  -SearchServiceName "srch-$prefix" `
  -IndexName "ragindex-$prefix"
```

If this fails due private networking, run the same script through the jumpbox with `az vm run-command invoke`.

## Stage 7: Upload a Smoke Document

Try local upload first:

```powershell
# Upload the smoke document to the documents container.
# --auth-mode login uses your Entra identity instead of storage account keys.
# --overwrite true makes the step repeatable.
az storage blob upload `
  --account-name "st$prefix" `
  --container-name documents `
  --name "gpt-rag-terraform-smoke-test.txt" `
  --file "..\test-documents\gpt-rag-terraform-smoke-test.txt" `
  --auth-mode login `
  --overwrite true
```

If local upload is blocked by private networking or RBAC, run the upload from the jumpbox:

```powershell
# Build a temporary script that will run inside the jumpbox.
$script = @"
`$ErrorActionPreference = 'Stop'

# Write a tiny validation document on the VM.
`$path = 'C:\WindowsAzure\Logs\gpt-rag-terraform-smoke-test.txt'
@'
This is a GPT-RAG Terraform smoke test document.
The unique validation phrase is terraform-rag-smoke-20260426.
'@ | Set-Content -LiteralPath `$path -Encoding UTF8

# Use the VM managed identity, then upload to the private Storage endpoint.
az login --identity --allow-no-subscriptions | Out-Null
az account set --subscription $subscriptionId
az storage blob upload --account-name st$prefix --container-name documents --name gpt-rag-terraform-smoke-test.txt --file `$path --auth-mode login --overwrite true
"@

# Store the temporary script locally so az vm run-command can upload it.
$temp = Join-Path $env:TEMP 'upload-smoke-doc-from-vm.ps1'
Set-Content -LiteralPath $temp -Value $script -Encoding UTF8

# Execute the temporary upload script on the jumpbox.
az vm run-command invoke `
  -g $rg `
  -n $jumpboxName `
  --command-id RunPowerShellScript `
  --scripts "@$temp" `
  --query "value[].message" `
  -o tsv
```

Restart data ingestion:

```powershell
# Restarting dataingest triggers the ingestion process for the newly uploaded document.
# The revision query selects the active revision for the dataingest app.
az containerapp revision restart `
  -g $rg `
  -n "ca-$prefix-dataingest" `
  --revision (az containerapp revision list -g $rg -n "ca-$prefix-dataingest" --query "[?properties.active].name | [0]" -o tsv)
```

Wait 2-5 minutes, then verify the index:

```powershell
# Confirm Search query keys are available.
# This is a lightweight sanity check that the Search service exists and the caller can read query keys.
az search query-key list `
  -g $rg `
  --service-name "srch-$prefix" `
  --query "[0].key" `
  -o tsv
```

If direct query is blocked locally, use the Azure portal or run validation from the jumpbox.

## Troubleshooting

Known errors and retry steps are documented in `troubleshooting.md`.

Most important rule: if an apply fails and you edit Terraform files, create a new saved plan. Do not reuse the old `tfplan-*` file.

## Stage 8: End-to-End Orchestrator Smoke Test from the Jumpbox

Run from local, executed on the jumpbox:

```powershell
# Build a temporary smoke-test script to execute inside the VNet.
$script = @"
`$ErrorActionPreference = 'Continue'

# Use the jumpbox managed identity for Azure lookups.
az login --identity --allow-no-subscriptions | Out-Null
az account set --subscription $subscriptionId

# Resolve the orchestrator FQDN from Azure Container Apps.
`$rg = '$rg'
`$app = 'ca-$prefix-orchestrator'
`$fqdn = az containerapp show -g `$rg -n `$app --query 'properties.configuration.ingress.fqdn' -o tsv

# Read APP_API_TOKEN from the app environment. If it is secret-backed, read the secret value.
`$envs = az containerapp show -g `$rg -n `$app --query 'properties.template.containers[0].env' -o json | ConvertFrom-Json

`$token = (`$envs | Where-Object { `$_.name -eq 'APP_API_TOKEN' }).value
if (-not `$token) {
  `$secretRef = (`$envs | Where-Object { `$_.name -eq 'APP_API_TOKEN' }).secretRef
  if (`$secretRef) {
    `$token = az containerapp secret show -g `$rg -n `$app --secret-name `$secretRef --query value -o tsv
  }
}

# Ask a question that can only be answered if ingestion, Search, Foundry, and orchestrator are working.
`$payload = @{
  ask = 'What is the unique validation phrase in the Terraform smoke test document?'
  user_context = @{}
} | ConvertTo-Json -Compress

# curl.exe avoids PowerShell alias behavior.
# -k allows the request even if the private path presents a cert chain PowerShell does not fully trust.
# -sS keeps output quiet but still shows errors.
# -N disables buffering for streamed responses.
# -m 180 sets a 180-second maximum runtime.
# --data-binary '@-' sends the JSON payload from stdin.
`$payload | curl.exe -k -sS -N -m 180 `
  -H 'Content-Type: application/json' `
  -H "dapr-api-token: `$token" `
  --data-binary '@-' `
  "https://`$fqdn/orchestrator"
"@

# Store the temporary script locally for VM Run Command upload.
$temp = Join-Path $env:TEMP 'smoke-orchestrator-from-vm.ps1'
Set-Content -LiteralPath $temp -Value $script -Encoding UTF8

# Execute the smoke test from inside the private network.
az vm run-command invoke `
  -g $rg `
  -n $jumpboxName `
  --command-id RunPowerShellScript `
  --scripts "@$temp" `
  --query "value[].message" `
  -o tsv
```

Expected response includes:

```text
terraform-rag-smoke-20260426
```

## Stage 9: Test the UI from Bastion/Jumpbox

Connect to the jumpbox through Azure Bastion.

Inside the jumpbox browser, open the frontend URL:

```powershell
# Print the deployed frontend URL.
terraform output -raw frontend_url
```

Ask:

```text
What is the unique validation phrase in the Terraform smoke test document?
```

Expected answer:

```text
terraform-rag-smoke-20260426
```

## Pass or Fail Criteria

Pass:

```text
Terraform creates the foundation in a fresh resource group.
Images build and push to the new ACR.
All four Container Apps run the new ACR images.
Foundry capability hosts are Succeeded.
App Config contains GPT-RAG keys.
Smoke document is ingested into Azure AI Search.
Orchestrator answers with terraform-rag-smoke-20260426 from the jumpbox.
Frontend works from the jumpbox browser.
```

Fail or needs hardening:

```text
Fresh Terraform cannot create Foundry capability hosts without the VM fallback.
App Config keys cannot be populated by Terraform or the helper.
Ingestion cannot reach Storage/Search privately.
Orchestrator cannot resolve private Search/Foundry endpoints from the agent path.
Container Apps require manual image/env edits outside Terraform.
```

## Cleanup

Only run this for the replica test environment:

```powershell
# Destroy only the replica environment described by this tfvars file.
# Do not run this from the original production/test deployment folder.
terraform destroy -var-file="terraform.tfvars"
```
