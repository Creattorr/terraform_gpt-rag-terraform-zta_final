variable "subscription_id" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "search_location" {
  type        = string
  default     = null
  description = "Optional Azure AI Search region. Use this when the main deployment region has Search capacity constraints."
}

variable "environment_name" {
  type    = string
  default = "gptrag"
}

variable "resource_group_name" {
  type    = string
  default = "rg-gpt-rag"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "chat_model_name" {
  type    = string
  default = "gpt-4o"
}

variable "chat_model_version" {
  type    = string
  default = "2024-11-20"
}

variable "chat_model_capacity" {
  type    = number
  default = 8
}

variable "embedding_model_name" {
  type    = string
  default = "text-embedding-3-large"
}

variable "embedding_model_version" {
  type    = string
  default = "1"
}

variable "embedding_model_capacity" {
  type    = number
  default = 8
}

variable "search_sku" {
  type    = string
  default = "basic"
}

variable "cosmos_offer_type" {
  type    = string
  default = "Standard"
}

variable "container_app_cpu" {
  type    = number
  default = 1
}

variable "container_app_memory" {
  type    = string
  default = "2Gi"
}

variable "frontend_image" {
  type    = string
  default = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "orchestrator_image" {
  type    = string
  default = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "dataingest_image" {
  type    = string
  default = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "mcp_image" {
  type    = string
  default = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "use_capp_api_key" {
  type    = bool
  default = false
}

variable "container_app_api_keys" {
  type    = map(string)
  default = {}
}

variable "container_app_api_token" {
  type        = string
  default     = null
  sensitive   = true
  description = "Optional shared API token used between frontend and orchestrator. If null, Terraform generates one."
}

variable "enable_responsible_ai_policy" {
  type    = bool
  default = true
}

variable "rai_blocklist_name" {
  type    = string
  default = "gptragBlocklist"
}

variable "rai_policy_name" {
  type    = string
  default = "gptragRAIPolicy"
}

variable "rai_blocklist_items" {
  type = list(object({
    pattern  = string
    is_regex = bool
  }))
  default = []
}

variable "enable_zero_trust" {
  type        = bool
  default     = false
  description = "Create the zero-trust private networking foundation: VNet, delegated Container Apps subnet, private endpoints, and private DNS zones."
}

variable "disable_public_network_access" {
  type        = bool
  default     = false
  description = "Disable public network access after the private endpoint path has been validated. Keep false during the first zero-trust migration apply."
}

variable "container_apps_internal_only" {
  type        = bool
  default     = false
  description = "Restrict Container Apps ingress to the Container Apps environment only. Keep false for VNet-reachable apps in an internal Container Apps environment."
}

variable "enable_container_apps_private_environment" {
  type        = bool
  default     = false
  description = "Move the Container Apps environment into the delegated subnet. This can replace an existing Container Apps environment, so enable only during a planned migration window."
}

variable "manage_app_config_keys" {
  type        = bool
  default     = true
  description = "Manage GPT-RAG App Configuration key-values in Terraform. Set false when the keys are populated by the jumpbox/helper script and should not be recreated by Terraform."
}

variable "zero_trust_address_space" {
  type        = list(string)
  default     = ["10.42.0.0/16"]
  description = "Address space for the GPT-RAG zero-trust virtual network."
}

variable "container_apps_subnet_address_prefix" {
  type        = string
  default     = "10.42.0.0/21"
  description = "Subnet prefix delegated to Microsoft.App/environments for Container Apps."
}

variable "ai_foundry_agent_subnet_address_prefix" {
  type        = string
  default     = "10.42.11.0/24"
  description = "Subnet prefix delegated to Microsoft.App/environments for AI Foundry Agent network injection."
}

variable "ai_foundry_rebuild_suffix" {
  type        = string
  default     = ""
  description = "Optional suffix for rebuilding the AI Foundry account and project when network injection must be present at creation time. Leave empty for the original names."
}

variable "enable_ai_foundry_network_injection" {
  type        = bool
  default     = true
  description = "Create the AI Foundry account with agent subnet network injection. Set false for the first Foundry staging apply if network injection leaves the account stuck in Creating/Failed."
}

variable "enable_ai_foundry_capability_hosts" {
  type        = bool
  default     = true
  description = "Create AI Foundry account and project capability hosts for Agents. Set false while staging the base Foundry account without network injection."
}

variable "private_endpoints_subnet_address_prefix" {
  type        = string
  default     = "10.42.8.0/24"
  description = "Subnet prefix for private endpoints."
}

variable "management_subnet_address_prefix" {
  type        = string
  default     = "10.42.9.0/27"
  description = "Reserved subnet prefix for future Bastion or jumpbox management access."
}

variable "enable_bastion" {
  type        = bool
  default     = false
  description = "Create Azure Bastion for private VM access. Requires enable_zero_trust."
}

variable "enable_jumpbox" {
  type        = bool
  default     = false
  description = "Create a private Windows Data Science VM jumpbox for validating private DNS, private endpoints, and app access. Requires enable_zero_trust."
}

variable "bastion_subnet_address_prefix" {
  type        = string
  default     = "10.42.10.0/26"
  description = "Subnet prefix for Azure Bastion. Azure requires this subnet to be named AzureBastionSubnet and at least /26."
}

variable "jumpbox_admin_username" {
  type        = string
  default     = "testvmuser"
  description = "Admin username for the private Windows jumpbox VM. The GPT-RAG install script expects testvmuser for its one-time login task."
}

variable "jumpbox_admin_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Optional admin password for the Windows jumpbox. If null and enable_jumpbox is true, Terraform generates a password and stores it in state."
}

variable "jumpbox_vm_size" {
  type        = string
  default     = "Standard_D4s_v3"
  description = "VM size for the private Windows Data Science VM jumpbox."
}

variable "deploy_jumpbox_software" {
  type        = bool
  default     = true
  description = "Run the GPT-RAG Windows VM Custom Script Extension to install VS Code, Azure CLI, Git, Node.js, Python 3.11, azd, PowerShell Core, Notepad++, WSL, Docker Desktop login task, GitHub Desktop login task, VS Code extensions, and GPT-RAG repositories."
}

variable "install_jumpbox_powershell7" {
  type        = bool
  default     = true
  description = "Install the baseline GPT-RAG jumpbox tools during VM provisioning: PowerShell 7, Azure CLI, Azure Developer CLI, Git, and Python 3.12. Keep true because Azure VM Run Command starts in Windows PowerShell 5.1 unless pwsh is explicitly called."
}

variable "jumpbox_python312_version" {
  type        = string
  default     = "3.12.10"
  description = "Python 3.12 patch version installed on the Windows jumpbox by the baseline tools bootstrap."
}

variable "jumpbox_required_tools_script_uri" {
  type        = string
  default     = "https://raw.githubusercontent.com/Creattorr/terraform_gpt-rag-terraform-zta_final/main/terraform/scripts/install-jumpbox-required-tools.ps1"
  description = "HTTPS URI used by the VM Custom Script Extension to download the baseline tools installer. Override this if you fork or host the script elsewhere."
}

variable "enable_jumpbox_nat_gateway" {
  type        = bool
  default     = true
  description = "Create a NAT Gateway for the jumpbox management subnet so the private VM has stable outbound access for Azure CLI, package downloads, and validation."
}

variable "enable_jumpbox_workspace_sync" {
  type        = bool
  default     = true
  description = "Add a VM extension that downloads the published Terraform workspace zip from private Storage when the jumpbox is created."
}

variable "jumpbox_workspace_container_name" {
  type        = string
  default     = "jumpbox-workspace"
  description = "Private blob container used to stage the current Terraform workspace for jumpbox sync."
}

variable "jumpbox_workspace_blob_name" {
  type        = string
  default     = "gpt-rag-terraform-workspace.zip"
  description = "Blob name for the packaged Terraform workspace."
}

variable "jumpbox_workspace_destination" {
  type        = string
  default     = "C:\\github\\gpt-rag-terraform"
  description = "Destination folder on the Windows jumpbox where the workspace zip is extracted."
}

variable "jumpbox_workspace_sync_version" {
  type        = string
  default     = "1"
  description = "Bump this value to force the jumpbox workspace sync VM extension to rerun."
}
