################################################################################
# Storage / backup-handoff outputs (M3)
#
# These three outputs are what Node5 and the Azure VM need to move a .bak
# file from on-prem to the new SQL VM. The SAS URL is sensitive (it grants
# r/w/l on the container for 24h) so Terraform redacts it from the console
# but still surfaces it via `terraform output -json` and -raw.
################################################################################

output "backup_storage_account" {
  value       = azurerm_storage_account.backups.name
  description = "Name of the storage account holding backup blobs."
}

output "backup_container_url" {
  value       = "${azurerm_storage_account.backups.primary_blob_endpoint}${azurerm_storage_container.backups.name}"
  description = "Full HTTPS URL of the backup container. Append /<filename> + the SAS token to read/write blobs."
}

output "backup_container_sas_url" {
  value       = "${azurerm_storage_account.backups.primary_blob_endpoint}${azurerm_storage_container.backups.name}${data.azurerm_storage_account_blob_container_sas.backups.sas}"
  description = "Container URL with embedded SAS token (24h, rwl). Use with: azcopy copy <file> '<this-url>' or azcopy copy '<this-url>/<file>' <local>. Sensitive: do not commit."
  sensitive   = true
}

# Extend the compact deployment bundle so SQLPilot's agent gets storage
# coordinates in the same single call it already uses today.
output "sqlpilot_storage" {
  value = {
    storage_account_name = azurerm_storage_account.backups.name
    container_name       = azurerm_storage_container.backups.name
    blob_endpoint        = azurerm_storage_account.backups.primary_blob_endpoint
    container_url        = "${azurerm_storage_account.backups.primary_blob_endpoint}${azurerm_storage_container.backups.name}"
  }
  description = "Storage handoff metadata (non-sensitive). Read alongside backup_container_sas_url for full upload/download access."
}
