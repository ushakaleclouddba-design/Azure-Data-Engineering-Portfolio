################################################################################
# outputs.tf
#
# Values exposed after terraform apply. SQLPilot's apply_terraform tool will
# read these via `terraform output -json` and surface them to the agent so
# subsequent stages (restore_database, day-2 ops) can target the new VM.
#
# Sensitive values (passwords, full connection strings with creds) are
# marked sensitive = true so Terraform redacts them from console output
# but they still come through in -json.
################################################################################

output "resource_group_name" {
  value       = azurerm_resource_group.main.name
  description = "The resource group everything was deployed into. Pass to terraform destroy when done."
}

output "vm_name" {
  value       = azurerm_windows_virtual_machine.main.name
  description = "Name of the deployed SQL VM."
}

output "vm_size" {
  value       = azurerm_windows_virtual_machine.main.size
  description = "Azure VM SKU. Useful to confirm the dry run used the size we expected."
}

output "public_ip_address" {
  value       = azurerm_public_ip.vm.ip_address
  description = "Public IP of the VM. Use this for RDP and SSMS connections."
}

output "sql_connection_string" {
  value       = "Server=tcp:${azurerm_public_ip.vm.ip_address},1433;User Id=${var.admin_username};Password=<see-tfvars>;Encrypt=True;TrustServerCertificate=False"
  description = "SQL connection string template. Replace <see-tfvars> with the admin_password value."
}

output "admin_username" {
  value       = var.admin_username
  description = "Local admin / SQL sysadmin username."
}

# Compact JSON-friendly bundle. SQLPilot's apply_terraform reads this
# single output to get everything it needs in one call:
#   terraform output -json sqlpilot_deployment | ConvertFrom-Json
output "sqlpilot_deployment" {
  value = {
    resource_group  = azurerm_resource_group.main.name
    vm_name         = azurerm_windows_virtual_machine.main.name
    vm_size         = azurerm_windows_virtual_machine.main.size
    location        = azurerm_resource_group.main.location
    public_ip       = azurerm_public_ip.vm.ip_address
    sql_port        = 1433
    admin_username  = var.admin_username
    deployed_at     = timestamp()
  }
  description = "Compact deployment record. SQLPilot reads this to register the new target."
}
