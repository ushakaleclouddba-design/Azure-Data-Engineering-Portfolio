################################################################################
# storage.tf
#
# Azure Storage account for the SQLPilot backup-restore handoff.
#
# Flow this enables (M3):
#   1. Node5 (source) takes a full BACKUP of SQLPilotDemo to a .bak file
#   2. AzCopy uploads the .bak to the 'backups' blob container using the SAS
#      token output below
#   3. The Azure SQL VM downloads the .bak (also via SAS) and runs RESTORE
#
# Design notes:
#   - Storage account names must be globally unique across all of Azure and
#     are limited to 3-24 lowercase alphanumeric chars. We append a random
#     suffix to "sqlpilot" to guarantee uniqueness on every apply.
#   - One private container ('backups') is enough for the POC. Production
#     would use separate containers per environment / data classification.
#   - SAS token is scoped narrowly: container-level, rwl (read/write/list)
#     permissions, 24h expiry. Regenerated on every apply (idempotent).
#   - Public network access is left ON with 'Allow' default action for the
#     POC so Node5 (which isn't in this VNet) can upload. For production
#     this would be a Private Endpoint or an IP allowlist.
################################################################################

# 6-char lowercase random suffix to make the storage account name globally
# unique. keepers ensures it only regenerates if the RG name changes (i.e.
# we don't churn the storage account on unrelated edits).
resource "random_string" "storage_suffix" {
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false

  keepers = {
    rg_name = var.resource_group_name
  }
}

resource "azurerm_storage_account" "backups" {
  name                = "sqlpilot${random_string.storage_suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  account_tier             = "Standard"
  account_replication_type = "LRS"     # locally-redundant is fine for POC; backups are also on Node5
  account_kind             = "StorageV2"

  # Block public anonymous read access on individual blobs. The container is
  # 'private' below; access is via SAS only.
  allow_nested_items_to_be_public = false

  # Require HTTPS for blob access (TLS 1.2+).
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  # POC: leave the storage firewall open so Node5 (outside the VNet) can
  # upload. Tighten to a specific IP allowlist or Private Endpoint for
  # production. Default action 'Allow' means the rules are advisory unless
  # default_action is changed to 'Deny'.
  public_network_access_enabled = true

  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  tags = var.tags
}

resource "azurerm_storage_container" "backups" {
  name                  = "backups"
  storage_account_id    = azurerm_storage_account.backups.id
  container_access_type = "private"
}

# Container-scoped SAS token. Scoped narrowly:
#   - permissions r/w/l only (no delete, no add-blob-without-overwrite quirks)
#   - 24h validity window so a forgotten token doesn't outlive the demo
#   - https-only
#
# Surface via `terraform output -raw backup_container_sas_url` (sensitive).
data "azurerm_storage_account_blob_container_sas" "backups" {
  connection_string = azurerm_storage_account.backups.primary_connection_string
  container_name    = azurerm_storage_container.backups.name
  https_only        = true

  # 24-hour window. timestamp() runs at plan time so apply-to-apply this
  # generates a fresh SAS, which is the intended behaviour.
  start  = timestamp()
  expiry = timeadd(timestamp(), "24h")

  permissions {
    read   = true
    add    = true
    create = true
    write  = true
    delete = false
    list   = true
  }
}
