# GPT-RAG Terraform Replica Troubleshooting

Use this file to record fresh-environment errors, likely causes, fixes, and retry commands. Add new issues here as they appear during replica testing.

## General Retry Rule for Terraform Saved Plans

If a Terraform apply fails and you edit `.tf` files afterward, do not rerun the old saved plan.

Saved plans are immutable snapshots of the previous code and variable values.

Use this retry pattern:

```powershell
cd .\terraform

# Confirms the current Terraform files are syntactically valid.
terraform validate

# Creates a new saved plan from the fixed code and current state.
terraform plan -var-file="terraform.tfvars" -out="tfplan-retry"

# Applies the new reviewed plan.
terraform apply "tfplan-retry"
```

## Error: RAI Policy Not Found During Chat Deployment

### Symptom

`terraform apply "tfplan-foundation"` fails with:

```text
Error: Failed to create/update resource

with azapi_resource.ai_foundry_chat_deployment

ERROR CODE: InvalidResourceProperties
The specified RaiPolicyName 'gptragReplicaRAIPolicy' is not found, please update it to a valid value.
```

### Likely Cause

The chat model deployment referenced the custom Responsible AI policy before Azure AI Foundry had finished creating or surfacing that policy.

This is a dependency/order issue in the Terraform graph.

### Fix Applied

The replica Terraform now makes the chat deployment wait for the RAI policy:

```hcl
resource "azapi_resource" "ai_foundry_chat_deployment" {
  ...

  depends_on = [
    azapi_resource.ai_foundry_rai_policy
  ]
}
```

### Retry Steps

From `gpt-rag-terraform-replica\terraform`:

```powershell
terraform validate
terraform plan -var-file="terraform.tfvars" -out="tfplan-foundation-retry"
terraform apply "tfplan-foundation-retry"
```

### Temporary Workaround

If the RAI policy still takes time to become available in a region, wait a few minutes and rerun the retry plan.

If blocked and you only need to validate infrastructure shape, temporarily set:

```hcl
enable_responsible_ai_policy = false
```

Then rerun:

```powershell
terraform plan -var-file="terraform.tfvars" -out="tfplan-no-rai"
terraform apply "tfplan-no-rai"
```

Use this workaround only for testing. Re-enable the policy before shipping.

## Error: Foundry Project Search Connection Already Exists

### Symptom

`terraform apply "tfplan-foundation"` fails with:

```text
Error: Resource already exists

with azapi_resource.ai_foundry_project_connection_search

A resource with the ID
"/subscriptions/.../providers/Microsoft.CognitiveServices/accounts/<account>/projects/<project>/connections/<account>-connection"
already exists - to be managed via Terraform this resource needs to be imported into the State.
```

### Likely Cause

The Terraform code created an account-level shared Search connection named:

```text
<ai-foundry-account-name>-connection
```

Azure AI Foundry can automatically surface that shared account connection under the project. Terraform then tried to create the same project-level connection explicitly, causing a conflict.

### Fix Applied

The replica Terraform no longer manages the duplicate project-level Search connection:

```text
Removed azapi_resource.ai_foundry_project_connection_search
```

The recovery scripts were also updated so they no longer target the removed resource:

```text
terraform/scripts/plan-foundry-f2-targeted-integrate.ps1
terraform/scripts/plan-search-standard-rebuild.ps1
terraform/scripts/resume-foundry-zta-rebuild.ps1
```

### Retry Steps

Do not import the auto-created connection for this clean replica test. Use the fixed Terraform and create a new plan:

```powershell
terraform validate
terraform plan -var-file="terraform.tfvars" -out="tfplan-foundation-retry"
terraform apply "tfplan-foundation-retry"
```

### When Import Might Be Appropriate

Only consider import if you intentionally want Terraform to own a resource Azure already created.

For this replica, import is not recommended because the connection is a Foundry-surfaced shared connection and was removed from the desired Terraform model.

## Error: Provider Produced Inconsistent Final Plan During Image Apply

### Symptom

`terraform apply "tfplan-images"` updates `orchestrator`, `dataingest`, and `mcp`, then fails while expanding the `frontend` plan:

```text
Error: Provider produced inconsistent final plan

When expanding the plan for azurerm_container_app.frontend ...
.template[0].container[0].env[3].value:
was
"https://ca-<prefix>-orchestrator--<old-revision>.<domain>.azurecontainerapps.io"
but now
"https://ca-<prefix>-orchestrator--0000001.<domain>.azurecontainerapps.io"
```

### Likely Cause

The frontend `ORCHESTRATOR_BASE_URL` used the orchestrator `latest_revision_fqdn`.

When the orchestrator image changes, Azure Container Apps creates or normalizes a new revision FQDN during the same apply. The AzureRM provider then sees a different value for the frontend env var than the value captured in the saved plan.

This is a provider planning bug triggered by revision-specific FQDNs.

### Fix Applied

The replica now uses stable Container App ingress FQDNs instead of revision-specific FQDNs:

```hcl
ORCHESTRATOR_BASE_URL = "https://${azurerm_container_app.orchestrator.ingress[0].fqdn}"
```

The `frontend_url` output and App Configuration endpoint list also use `ingress[0].fqdn`.

### Retry Steps

Do not rerun the old `tfplan-images` file after this code change.

Create a new plan:

```powershell
terraform validate
terraform plan -var-file="terraform.tfvars" -out="tfplan-images-retry"
terraform apply "tfplan-images-retry"
```

If only the frontend remains out of date, you can make a focused retry plan:

```powershell
terraform plan `
  -var-file="terraform.tfvars" `
  -target=azurerm_container_app.frontend `
  -out="tfplan-frontend-images-retry"

terraform apply "tfplan-frontend-images-retry"
```

After apply, verify all Container Apps:

```powershell
az containerapp list -g $rg `
  --query "[].{name:name,running:properties.runningStatus,image:properties.template.containers[0].image,fqdn:properties.configuration.ingress.fqdn}" `
  -o table
```

## Error: Foundry Capability Host Creation Times Out or Conflicts

### Symptom

Stage 4 fails while creating:

```text
azapi_resource.ai_foundry_account_capability_host
azapi_resource.ai_foundry_project_capability_host
```

Possible errors include:

```text
timeout while waiting for state to become Succeeded
```

or:

```text
There is an existing Capability Host ... cannot create a new Capability Host ...
```

or local read/create permission errors.

### Likely Cause

Azure AI Foundry capability hosts use preview management APIs and may be sensitive to provisioning order, RBAC, identity, and private networking.

In some environments, the account-level capability host is auto-created by Foundry, while the project host still needs to be created or repaired.

### Preferred Fix

For a clean environment, first try Terraform:

```hcl
enable_ai_foundry_capability_hosts = true
```

```powershell
terraform plan -var-file="terraform.tfvars" -out="tfplan-foundry-capability-hosts"
terraform apply "tfplan-foundry-capability-hosts"
```

If it succeeds, keep the flag true.

### Fallback Fix

If Terraform fails, set:

```hcl
enable_ai_foundry_capability_hosts = false
```

Then use the VM Run Command fallback helper:

```powershell
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

Expected project host state:

```text
caphostproj Succeeded
```

### RBAC Note

The jumpbox managed identity may need these roles at the resource group scope:

```text
Azure AI Account Owner
Role Based Access Control Administrator
```

If your identity cannot assign those roles, ask an Azure RBAC administrator.

## Error: App Configuration Writes Fail from Local Machine

### Symptom

Terraform or local Azure CLI cannot write App Configuration keys. Errors may include:

```text
Forbidden
public network access is disabled
client address is not authorized
```

### Likely Cause

In zero-trust mode, App Configuration data-plane access may be private-only. Your local workstation is outside the VNet/private DNS path.

### Fix

Keep:

```hcl
manage_app_config_keys = false
```

Then run the App Config helper from the jumpbox:

```powershell
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

Restart Container Apps afterward so they reload configuration.

## Error: Blob Upload or Search Query Fails from Local Machine

### Symptom

Local upload or Search validation fails, often with network or authorization errors.

### Likely Cause

Storage/Search data-plane access is restricted to private endpoints, or your local identity does not have the needed data-plane role.

### Fix

Run the operation from the jumpbox with VM Run Command, or connect through Bastion and run from the VM.

For smoke document upload, use the Stage 7 jumpbox upload command in `README.md`.

For private DNS/data-plane validation, use:

```powershell
.\scripts\validate-zero-trust-jumpbox.ps1
```

from the jumpbox or through VM Run Command.

## Error: PowerShell Version on Jumpbox Is 5.1

### Symptom

Inside the VM or through VM Run Command:

```powershell
$PSVersionTable.PSVersion
```

shows Windows PowerShell 5.1, or scripts fail because they require PowerShell 7.

### Likely Cause

Windows Server images include Windows PowerShell 5.1 by default. PowerShell 7 is a side-by-side installation and is launched with:

```powershell
pwsh.exe
```

Azure VM Run Command also starts in Windows PowerShell 5.1 unless the command explicitly calls `pwsh.exe`.

### Fix Applied

Terraform now includes a jumpbox VM extension:

```hcl
resource "azurerm_virtual_machine_extension" "jumpbox_powershell7"
```

It installs PowerShell 7 during jumpbox provisioning when this variable is true:

```hcl
install_jumpbox_powershell7 = true
```

The GPT-RAG jumpbox software extension also depends on the PowerShell 7 extension and calls:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

### Verify

```powershell
az vm run-command invoke `
  -g "<resource-group>" `
  -n "<jumpbox-vm-name>" `
  --command-id RunPowerShellScript `
  --scripts "pwsh.exe -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'" `
  --query "value[].message" `
  -o tsv
```

### Running Future VM Commands

When a helper script needs PowerShell 7, wrap it like this:

```powershell
az vm run-command invoke `
  -g "<resource-group>" `
  -n "<jumpbox-vm-name>" `
  --command-id RunPowerShellScript `
  --scripts "pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File C:\github\gpt-rag-terraform\terraform\scripts\<script-name>.ps1" `
  --query "value[].message" `
  -o tsv
```

## How to Add Future Errors

Add each new issue in this format:

```text
## Error: Short Name

### Symptom
Exact error text or representative snippet.

### Likely Cause
What probably caused it.

### Fix
Code/config/command change.

### Retry Steps
Commands to safely continue.
```
