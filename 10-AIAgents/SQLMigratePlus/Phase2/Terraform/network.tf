################################################################################
# network.tf
#
# Network plumbing for the dry-run SQL VM:
#   - Resource group (everything lives inside this)
#   - VNet + subnet (Azure requires a VNet even for a single VM)
#   - Public IP (so you can RDP/SSMS in from Node5)
#   - NSG with RDP (3389) and SQL (1433) locked to allowed_source_ip
#   - NIC connecting the VM to all of the above
#
# Naming pattern: <resource-type-prefix>-<vm_name suffix>. Predictable
# enough that terraform destroy gets everything in one pass.
################################################################################

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.vm_name}"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_subnet" "vm" {
  name                 = "subnet-vm"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.1.0/24"]
}

# Public IP. Standard SKU + Static so it survives VM restarts.
# Cheap when the VM is running; consider switching to Dynamic for cost
# savings if VM is stopped/deallocated often.
resource "azurerm_public_ip" "vm" {
  name                = "pip-${var.vm_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# NSG. Two rules: RDP from your IP, SQL from your IP. Both inbound only.
# Default outbound rules (Internet) stay open so the VM can pull updates.
resource "azurerm_network_security_group" "vm" {
  name                = "nsg-${var.vm_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  security_rule {
    name                       = "allow-rdp-from-source-ip"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.allowed_source_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-sql-from-source-ip"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = var.allowed_source_ip
    destination_address_prefix = "*"
  }
}

# Associate NSG to subnet (not to NIC). Doing it at the subnet level means
# any future NICs on the same subnet inherit the same rules.
resource "azurerm_subnet_network_security_group_association" "vm" {
  subnet_id                 = azurerm_subnet.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

# NIC. Connects VM to subnet, attaches public IP for inbound RDP/SQL.
resource "azurerm_network_interface" "vm" {
  name                = "nic-${var.vm_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}
