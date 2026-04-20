# =============================================================================
# Application VM
# =============================================================================

# -----------------------------------------------------------------------------
# Public IP
# -----------------------------------------------------------------------------
resource "azurerm_public_ip" "app" {
  count               = var.enable_app_vm ? 1 : 0
  name                = "pip-app"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# Network Interface
# -----------------------------------------------------------------------------
resource "azurerm_network_interface" "app" {
  count               = var.enable_app_vm ? 1 : 0
  name                = "nic-app"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.app[0].id
  }
}

# -----------------------------------------------------------------------------
# Virtual Machine
# -----------------------------------------------------------------------------
resource "azurerm_linux_virtual_machine" "app" {
  count                           = var.enable_app_vm ? 1 : 0
  name                            = "vm-app"
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.app[0].id]
  tags                            = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.admin_ssh_public_key_path)
  }

  os_disk {
    name                 = "osdisk-app"
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
