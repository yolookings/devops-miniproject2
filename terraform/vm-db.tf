# =============================================================================
# Database VMs — 1 Master + 2 Slaves
# =============================================================================

# -----------------------------------------------------------------------------
# Local variables for DB node definitions
# -----------------------------------------------------------------------------
locals {
  db_nodes = {
    master = { name = "vm-db-master", index = 0 }
    slave1 = { name = "vm-db-slave1", index = 1 }
    slave2 = { name = "vm-db-slave2", index = 2 }
  }
}

# -----------------------------------------------------------------------------
# Public IPs (for SSH management only)
# Azure for Students commonly has low Public IP quota, so only master gets a public IP.
# -----------------------------------------------------------------------------
resource "azurerm_public_ip" "db" {
  for_each            = { for key, value in local.db_nodes : key => value if key == "master" }
  name                = "pip-${each.value.name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# Network Interfaces
# -----------------------------------------------------------------------------
resource "azurerm_network_interface" "db" {
  for_each            = local.db_nodes
  name                = "nic-${each.value.name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.db.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = each.key == "master" ? azurerm_public_ip.db["master"].id : null
  }
}

# -----------------------------------------------------------------------------
# Virtual Machines
# -----------------------------------------------------------------------------
resource "azurerm_linux_virtual_machine" "db" {
  for_each                        = local.db_nodes
  name                            = each.value.name
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.db[each.key].id]
  tags = merge(var.tags, {
    Role = each.key == "master" ? "db-master" : "db-slave"
  })

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.admin_ssh_public_key_path)
  }

  os_disk {
    name                 = "osdisk-${each.value.name}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}
