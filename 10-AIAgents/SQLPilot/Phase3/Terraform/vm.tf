################################################################################
# vm.tf
#
# The SQL Server VM. Two resources:
#
#   1. azurerm_windows_virtual_machine - the raw Windows VM, built from
#      Microsoft's SQL marketplace image (which has SQL Server pre-installed).
#
#   2. azurerm_mssql_virtual_machine - the SQL Server IaaS extension. This
#      is what tells Azure "this VM is running SQL Server, manage it as
#      such" (auto-patching, auto-backup, SQL-aware shutdown, etc.). Without
#      it, Azure treats the VM as a generic Windows machine and you lose
#      the SQL-specific portal features.
#
# Source image:  publisher microsoftsqlserver, offer sql2022-ws2022,
# sku sqldev-gen2. That's SQL Server 2022 Developer Edition on Windows
# Server 2022 - free for non-production, full Enterprise feature set.
################################################################################

resource "azurerm_windows_virtual_machine" "main" {
  name                = var.vm_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.vm_size

  # Windows NetBIOS hostnames are capped at 15 characters. Our Azure resource
  # name (var.vm_name) can be longer for clarity, but computer_name (what
  # Windows itself sees as the machine name) must stay under the limit.
  computer_name = "sqlpilot-01"

  admin_username = var.admin_username
  admin_password = var.admin_password

  network_interface_ids = [
    azurerm_network_interface.vm.id,
  ]

  # OS disk: 127 GB Premium SSD. 127 GB is the minimum for the SQL
  # marketplace image; the image is ~50 GB and SQL needs working room.
  os_disk {
    name                 = "osdisk-${var.vm_name}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 127
  }

  # Microsoft SQL Server image reference. Pinning to "latest" means
  # patches roll in on rebuild; for production you'd pin a version.
  source_image_reference {
    publisher = "microsoftsqlserver"
    offer     = var.sql_image_offer
    sku       = var.sql_image_sku
    version   = "latest"
  }

  # Don't auto-shutdown by default. If you want this for cost control,
  # add an azurerm_dev_test_global_vm_shutdown_schedule resource later.

  tags = var.tags
}

# SQL Server IaaS extension. This is the Azure-side configuration that
# turns the bare Windows-with-SQL-installed image into a managed SQL VM.
#
# What it gives us:
#   - License type tracking (PAYG vs BYOL vs DR)
#   - Storage layout configuration (data/log/tempdb on separate disks)
#   - Connectivity mode (PUBLIC = SQL accessible via public IP, with
#     SQL Authentication enabled)
#   - Auto-patching window
#
# For the dry run we go minimal: PAYG licensing on Developer edition
# (which is free anyway, so PAYG cost is effectively zero), no separate
# data disks (single OS disk), PUBLIC connectivity so SSMS works from
# Node5.
resource "azurerm_mssql_virtual_machine" "main" {
  virtual_machine_id               = azurerm_windows_virtual_machine.main.id
  sql_license_type                 = "PAYG"
  r_services_enabled               = false
  sql_connectivity_port            = 1433
  sql_connectivity_type            = "PUBLIC"
  sql_connectivity_update_password = var.admin_password
  sql_connectivity_update_username = var.admin_username

  # tags - the mssql resource inherits VM tags by association; no
  # explicit tags block needed here.
}
