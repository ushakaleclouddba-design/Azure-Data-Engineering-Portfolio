################################################################################
# variables.tf
#
# Inputs for the SQLPilot dry-run infrastructure module. Every var has a
# sensible default tuned for "smallest credible SQL VM" so you can run
# terraform apply with no -var arguments.
#
# To customize later, override via terraform.tfvars or -var flags.
################################################################################

variable "resource_group_name" {
  type        = string
  default     = "rg-sqlpilot-dryrun-eastus2"
  description = "Name of the Azure resource group to create. Everything else lives inside it, so destroying this RG cleans up the whole dry run."
}

variable "location" {
  type        = string
  default     = "eastus2"
  description = "Azure region. eastus2 chosen for balance of price and SQL VM image availability."
}

variable "vm_name" {
  type        = string
  default     = "sql-vm-sqlpilot-01"
  description = "Name of the SQL Server VM. Used as the hostname inside Azure DNS."
}

variable "vm_size" {
  type        = string
  default     = "Standard_D2s_v5"
  description = "Azure VM size. D2s_v5 is the smallest credible SQL Server VM (2 vCPU, 8 GB RAM)."
}

variable "admin_username" {
  type        = string
  default     = "sqlpilotadmin"
  description = "Local admin username for Windows and SQL sysadmin."
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Local admin password. Set via TF_VAR_admin_password env var or terraform.tfvars (gitignored). Must be 12+ chars and meet Windows complexity rules."

  validation {
    condition     = length(var.admin_password) >= 12
    error_message = "admin_password must be at least 12 characters."
  }
}

variable "allowed_source_ip" {
  type        = string
  description = "Your public IP (with /32 mask) that NSG rules will allow for RDP and SQL. Tighten before running. Format: 'a.b.c.d/32'. To find yours: (Invoke-RestMethod ifconfig.me/ip) + '/32'."
}

variable "sql_image_offer" {
  type        = string
  default     = "sql2022-ws2022"
  description = "Azure Marketplace publisher offer for SQL Server. sql2022-ws2022 = SQL Server 2022 on Windows Server 2022."
}

variable "sql_image_sku" {
  type        = string
  default     = "sqldev-gen2"
  description = "Image SKU. sqldev-gen2 = SQL Server 2022 Developer Edition (free for non-production), Gen2 VM."
}

variable "tags" {
  type = map(string)
  default = {
    project     = "SQLPilot"
    purpose     = "dry-run"
    owner       = "Kale"
    environment = "lab"
  }
  description = "Tags applied to every resource. Useful for cost tracking and cleanup queries."
}
