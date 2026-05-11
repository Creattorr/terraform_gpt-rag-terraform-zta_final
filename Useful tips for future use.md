# Useful Tips for Future Use

This note captures two recurring GPT-RAG ZTA topics:

1. What control-plane and data-plane RBAC means for managed identities.
2. Where GPT-RAG settings live and how to apply changes to the four services.

## 1. Managed Identity RBAC: Control Plane vs Data Plane

In Azure, giving an identity access to the resource itself is not always enough. Many services have two layers of permissions.

### Control Plane

Control plane means permission to manage Azure resources through Azure Resource Manager.

Examples:

```text
Create a Storage Account
Update an Azure AI Search service
Create a Container App
Read App Configuration resource metadata
Create role assignments
Create Azure AI Foundry connections
```

Typical roles:

```text
Contributor
Reader
Azure AI Account Owner
Role Based Access Control Administrator
Cognitive Services Contributor
```

### Data Plane

Data plane means permission to use the service's actual data or runtime API.

Examples:

```text
Read/write blobs inside a Storage container
Read keys or values from App Configuration
Query documents inside Azure AI Search
Write vectors/chunks into Azure AI Search
Read secrets from Key Vault
Read/write Cosmos DB records
Pull images from ACR
```

Typical roles:

```text
Storage Blob Data Contributor
App Configuration Data Reader
Search Index Data Reader
Search Index Data Contributor
Key Vault Secrets User
Cosmos DB Built-in Data Contributor
AcrPull
```

### Why This Matters for GPT-RAG

For example, the Data Ingestion app identity may have permission to see the Azure AI Search service resource in Azure, but that does not automatically mean it can write documents into the Search index.

It needs both kinds of access:

```text
Control plane:
Can reference/manage the Search service resource.

Data plane:
Can upload chunks/documents into the Search index.
```

Another example: the orchestrator identity may be allowed to read the App Configuration resource metadata, but the app still fails unless it has:

```text
App Configuration Data Reader
```

because the actual GPT-RAG settings are data-plane key-values inside App Configuration.

Management-friendly explanation:

```text
Azure separates permissions for managing a service from permissions for using the data inside that service.
In ZTA GPT-RAG, every application identity needed both the correct management permissions and the correct runtime data access permissions.
Missing either one could break the deployment or runtime, even if the resource itself existed successfully.
```

### Where RBAC Is Defined in Terraform

In this Terraform code, managed identity and RBAC access is mainly managed in:

```text
terraform/main.tf
```

The general pattern is:

```hcl
resource "azurerm_role_assignment" "..." {
  scope                = <which Azure resource this role applies to>
  role_definition_name = <Azure role name>
  principal_id         = <managed identity principal id>
}
```

Managed identities are created in `terraform/main.tf` around:

```text
azurerm_user_assigned_identity.frontend
azurerm_user_assigned_identity.orchestrator
azurerm_user_assigned_identity.dataingest
azurerm_user_assigned_identity.mcp
azurerm_user_assigned_identity.executor
```

The Data Ingestion identity is created as:

```hcl
resource "azurerm_user_assigned_identity" "dataingest" {
  name                = "id-${local.prefix}-dataingest"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}
```

That identity is attached to the Data Ingestion Container App:

```hcl
resource "azurerm_container_app" "dataingest" {
  name                         = local.container_app_specs[2].name
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.dataingest.id]
  }

  registry {
    server   = azurerm_container_registry.this.login_server
    identity = azurerm_user_assigned_identity.dataingest.id
  }
}
```

The app also receives the identity client ID:

```hcl
env {
  name  = "AZURE_CLIENT_ID"
  value = azurerm_user_assigned_identity.dataingest.client_id
}
```

### Data Ingestion Role Examples

`AcrPull`

```hcl
resource "azurerm_role_assignment" "dataingest_acr" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.dataingest.principal_id
}
```

Purpose: lets Data Ingestion pull its container image from ACR.

`App Configuration Data Reader`

```hcl
resource "azurerm_role_assignment" "dataingest_appconfig" {
  scope                = azurerm_app_configuration.this.id
  role_definition_name = "App Configuration Data Reader"
  principal_id         = azurerm_user_assigned_identity.dataingest.principal_id
}
```

Purpose: lets Data Ingestion read GPT-RAG runtime settings from App Configuration.

`Storage Blob Data Contributor`

```hcl
resource "azurerm_role_assignment" "dataingest_storage_contributor" {
  scope                = azurerm_storage_account.solution.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.dataingest.principal_id
}
```

Purpose: lets Data Ingestion read source documents and write/update blob-related ingestion artifacts.

`Key Vault Secrets User`

```hcl
resource "azurerm_role_assignment" "dataingest_kv" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.dataingest.principal_id
}
```

Purpose: lets Data Ingestion read secrets from Key Vault.

`Cognitive Services OpenAI User`

```hcl
resource "azurerm_role_assignment" "dataingest_foundry_openai_user" {
  scope                = azapi_resource.ai_foundry_account.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.dataingest.principal_id
}
```

Purpose: lets Data Ingestion call Azure OpenAI/Foundry model deployments, especially embeddings.

`Cognitive Services User`

```hcl
resource "azurerm_role_assignment" "dataingest_foundry_user" {
  scope                = azapi_resource.ai_foundry_account.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_user_assigned_identity.dataingest.principal_id
}
```

Purpose: gives general runtime access to the Foundry/Cognitive Services account.

`Search Index Data Contributor`

```hcl
resource "azurerm_role_assignment" "dataingest_search_contributor" {
  scope                = azurerm_search_service.solution.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azurerm_user_assigned_identity.dataingest.principal_id
}
```

Purpose: lets Data Ingestion write chunks/vectors into the Azure AI Search index.

## 2. Where GPT-RAG Settings Live

Most GPT-RAG settings are not in the four Container Apps directly.

The Container Apps get only bootstrap environment variables, then load the real runtime configuration from Azure App Configuration.

### Terraform App Configuration Contract

In Terraform, the App Configuration contract starts in:

```text
terraform/main.tf
```

Look for:

```hcl
# App Configuration contract used by GPT-RAG services and post-provision scripts
```

When Terraform manages the keys directly, they are created by:

```hcl
resource "azapi_resource" "app_config_keys" {
  for_each = var.manage_app_config_keys ? {
    for item in local.app_config_items :
    "${item.label}:${item.name}" => item
  } : {}

  type                      = "Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01"
  name                      = format("%s$%s", each.value.name, each.value.label)
  parent_id                 = azurerm_app_configuration.this.id
  schema_validation_enabled = false

  body = {
    properties = {
      value       = each.value.value
      contentType = each.value.content_type
    }
  }
}
```

In the ZTA flow, the safer default is usually:

```hcl
manage_app_config_keys = false
```

That means settings are written by the helper script instead:

```text
terraform/scripts/set-gpt-rag-appconfig-arm.ps1
```

That helper writes keys such as:

```text
CHAT_DEPLOYMENT_NAME
EMBEDDING_DEPLOYMENT_NAME
PROMPTS_CONTAINER
PROMPT_SOURCE
AGENT_STRATEGY
SEARCH_RAG_INDEX_NAME
SEARCH_SERVICE_QUERY_ENDPOINT
SEARCH_CONNECTION_ID
MODEL_DEPLOYMENTS
CRON_RUN_BLOB_INDEX
CRON_RUN_BLOB_PURGE
```

Example App Configuration item definitions from Terraform:

```hcl
{
  name         = "CHAT_DEPLOYMENT_NAME"
  value        = "chat"
  label        = "gpt-rag"
  content_type = "text/plain"
}

{
  name         = "PROMPTS_CONTAINER"
  value        = azurerm_cosmosdb_sql_container.prompts.name
  label        = "gpt-rag"
  content_type = "text/plain"
}

{
  name         = "PROMPT_SOURCE"
  value        = "file"
  label        = "gpt-rag"
  content_type = "text/plain"
}

{
  name         = "AGENT_STRATEGY"
  value        = "single_agent_rag"
  label        = "gpt-rag"
  content_type = "text/plain"
}

{
  name         = "SEARCH_RAG_INDEX_NAME"
  value        = "ragindex-${local.prefix}"
  label        = "gpt-rag"
  content_type = "text/plain"
}

{
  name         = "CRON_RUN_BLOB_INDEX"
  value        = "10 * * * *"
  label        = "gpt-rag-ingestion"
  content_type = "text/plain"
}
```

### How Each Service Reads Settings

Orchestrator reads App Configuration labels in this order:

```text
gpt-rag-orchestrator
gpt-rag
no label
```

In the source code, this is handled by:

```text
components/gpt-rag-orchestrator/src/connectors/appconfig.py
```

Relevant code:

```python
orchestrator_label_selector = SettingSelector(label_filter='gpt-rag-orchestrator', key_filter='*')
base_label_selector = SettingSelector(label_filter='gpt-rag', key_filter='*')
no_label_selector = SettingSelector(label_filter=None, key_filter='*')

self.client = load(
    selects=[orchestrator_label_selector, base_label_selector, no_label_selector],
    endpoint=endpoint,
    credential=self.credential,
    key_vault_options=AzureAppConfigurationKeyVaultOptions(credential=self.credential)
)
```

Ingestion reads:

```text
gpt-rag-ingestion
gpt-rag
no label
```

In the source code, this is handled by:

```text
components/gpt-rag-ingestion/tools/appconfig.py
```

Relevant code:

```python
app_label_selector = SettingSelector(label_filter='gpt-rag-ingestion', key_filter='*')
base_label_selector = SettingSelector(label_filter='gpt-rag', key_filter='*')
no_label_selector = SettingSelector(label_filter=None, key_filter='*')

self.client = load(
    selects=[app_label_selector, base_label_selector, no_label_selector],
    endpoint=endpoint,
    credential=self.credential,
    key_vault_options=AzureAppConfigurationKeyVaultOptions(credential=self.credential),
)
```

MCP also reads from App Configuration, mainly the `gpt-rag` label.

The four Container Apps get bootstrap variables like:

```text
APP_CONFIG_ENDPOINT
AZURE_CLIENT_ID
AZURE_TENANT_ID
APP_API_TOKEN
```

from Terraform.

Terraform sets those bootstrap values in each Container App. Example:

```hcl
env {
  name  = "APP_CONFIG_ENDPOINT"
  value = azurerm_app_configuration.this.endpoint
}

env {
  name  = "AZURE_TENANT_ID"
  value = var.tenant_id
}

env {
  name  = "AZURE_CLIENT_ID"
  value = azurerm_user_assigned_identity.orchestrator.client_id
}
```

## 3. Where LLM Prompts Are

For orchestrator, prompt selection is controlled by:

```python
self.prompt_source = self.cfg.get("PROMPT_SOURCE", "file")
```

Full surrounding code:

```python
self.project_endpoint = self.cfg.get("AI_FOUNDRY_PROJECT_ENDPOINT")
self.account_endpoint = self.cfg.get("AI_FOUNDRY_ACCOUNT_ENDPOINT")
self.model_name = self.cfg.get("CHAT_DEPLOYMENT_NAME")
self.prompt_source = self.cfg.get("PROMPT_SOURCE", "file")
self.openai_api_version = self.cfg.get("OPENAI_API_VERSION", "2025-04-01-preview")
```

If:

```text
PROMPT_SOURCE = file
```

then prompts come from files inside the orchestrator image:

```text
components/gpt-rag-orchestrator/src/prompts/
```

The main single-agent RAG prompt is:

```text
components/gpt-rag-orchestrator/src/prompts/single_agent_rag/main.txt
```

That prompt is used when the orchestrator creates the Foundry agent:

```python
instructions=await self._read_prompt("main")
```

Full agent creation snippet:

```python
agent = await project_client.agents.create_agent(
    model=self.model_name,
    name="gpt-rag-agent",
    instructions=await self._read_prompt("main"),
    tools=self.tools_list,
    tool_resources=self.tool_resources
)
```

If:

```text
PROMPT_SOURCE = cosmos
```

then prompts are read from the Cosmos DB `prompts` container.

Cosmos prompt loading code:

```python
async def _read_prompt_cosmos(self, prompt_name, placeholders=None):
    prompt_json = await self.cosmos.get_document(
        "prompts",
        f"{self.strategy_type.value}_{prompt_name}"
    )
    prompt = prompt_json.get("content", "")
    return prompt
```

File prompt loading code:

```python
async def _read_prompt_file(self, prompt_name, placeholders=None):
    prompt_file_path = os.path.join(self._prompt_dir(), f"{prompt_name}.txt")

    with open(prompt_file_path, "r") as f:
        prompt = f.read().strip()
        return prompt
```

Search tool settings are also read from App Configuration:

```python
azure_ai_conn_id = cfg.get("SEARCH_CONNECTION_ID", "")
index_name = cfg.get("SEARCH_RAG_INDEX_NAME", "ragindex")

self.ai_search = AzureAISearchTool(
    index_connection_id=azure_ai_conn_id,
    index_name=index_name,
    query_type=AzureAISearchQueryType.SIMPLE,
    top_k=cfg.get("SEARCH_TOP_K", 5, int),
    filter="",
)
```

Ingestion schedule settings are read from App Configuration/environment:

```python
s_blob_index = _schedule(
    "CRON_RUN_BLOB_INDEX",
    run_blob_index,
    "blob_index_files",
    "blob_index_files"
)

s_blob_purge = _schedule(
    "CRON_RUN_BLOB_PURGE",
    run_blob_purge,
    "blob_purge_deleted_files",
    "blob_purge_deleted_files"
)
```

Ingestion chunking settings are read in chunkers, for example:

```python
self.max_chunk_size = int(app_config_client.get("CHUNKING_NUM_TOKENS", "2048"))
self.minimum_chunk_size = int(app_config_client.get("CHUNKING_MIN_CHUNK_SIZE", "100"))
```

## 4. How to Apply Changes

### Change App Configuration Only

Use this path for runtime settings such as:

```text
SEARCH_TOP_K
AGENT_STRATEGY
PROMPT_SOURCE
CRON_RUN_BLOB_INDEX
CHUNKING_NUM_TOKENS
SEARCH_RAG_INDEX_NAME
```

Update App Configuration:

```powershell
az appconfig kv set `
  --name appcs-<prefix> `
  --key SEARCH_TOP_K `
  --label gpt-rag `
  --value 10
```

Then restart the relevant Container App so it reloads config.

For orchestrator settings:

```powershell
az containerapp revision restart `
  -g <resource-group> `
  -n ca-<prefix>-orchestrator `
  --revision <active-revision-name>
```

For ingestion settings, use label:

```text
gpt-rag-ingestion
```

and restart:

```text
ca-<prefix>-dataingest
```

### Change Prompt Files

If `PROMPT_SOURCE=file` and you change files under:

```text
components/gpt-rag-orchestrator/src/prompts/
```

then rebuild and redeploy the orchestrator image:

```powershell
az acr build --registry <acr-name> --image gpt-rag-orchestrator:v2.1.1 .\components\gpt-rag-orchestrator
```

Update `terraform.tfvars`:

```hcl
orchestrator_image = "<acr-login-server>/gpt-rag-orchestrator:v2.1.1"
```

Then apply:

```powershell
terraform plan -var-file="terraform.tfvars" -out="tfplan-orchestrator-image"
terraform apply "tfplan-orchestrator-image"
```

### Change Application Code in Any of the Four Services

The four GPT-RAG services are:

```text
components/gpt-rag-ui
components/gpt-rag-orchestrator
components/gpt-rag-ingestion
components/gpt-rag-mcp
```

For any code change:

```text
1. Edit code.
2. Build/push a new image tag to ACR.
3. Update the corresponding image variable in terraform.tfvars.
4. Run terraform plan/apply.
```

Example:

```powershell
az acr build --registry <acr-name> --image gpt-rag-ui:v2.1.1 .\components\gpt-rag-ui
```

Then update:

```hcl
frontend_image = "<acr-login-server>/gpt-rag-ui:v2.1.1"
```

Then apply:

```powershell
terraform plan -var-file="terraform.tfvars" -out="tfplan-ui-image"
terraform apply "tfplan-ui-image"
```

Use a new tag each time. Do not reuse the same image tag unless you also force a new Container App revision.
