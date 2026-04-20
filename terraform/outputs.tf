# =============================================================================
# Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Application VM
# -----------------------------------------------------------------------------
output "app_public_ip" {
  description = "Public IP address of the Application VM"
  value       = azurerm_public_ip.app.ip_address
}

output "app_private_ip" {
  description = "Private IP address of the Application VM"
  value       = azurerm_network_interface.app.private_ip_address
}

# -----------------------------------------------------------------------------
# ProxySQL VM
# -----------------------------------------------------------------------------
output "proxy_public_ip" {
  description = "Public IP address of the ProxySQL VM (SSH only)"
  value       = azurerm_public_ip.proxy.ip_address
}

output "proxy_private_ip" {
  description = "Private IP address of the ProxySQL VM"
  value       = azurerm_network_interface.proxy.private_ip_address
}

# -----------------------------------------------------------------------------
# Database VMs
# -----------------------------------------------------------------------------
output "db_public_ips" {
  description = "Public IP addresses of the Database VMs (only master has public IP)"
  value = {
    master = azurerm_public_ip.db["master"].ip_address
  }
}

output "db_private_ips" {
  description = "Private IP addresses of the Database VMs"
  value = {
    for key, node in local.db_nodes : key => azurerm_network_interface.db[key].private_ip_address
  }
}

# -----------------------------------------------------------------------------
# Connection Info Summary
# -----------------------------------------------------------------------------
output "ssh_commands" {
  description = "SSH commands to connect to each VM"
  value = {
    app     = "ssh ${var.admin_username}@${azurerm_public_ip.app.ip_address}"
    proxy   = "ssh ${var.admin_username}@${azurerm_public_ip.proxy.ip_address}"
    master  = "ssh ${var.admin_username}@${azurerm_public_ip.db["master"].ip_address}"
    slave1  = "ssh -J ${var.admin_username}@${azurerm_public_ip.db["master"].ip_address} ${var.admin_username}@${azurerm_network_interface.db["slave1"].private_ip_address}"
    slave2  = "ssh -J ${var.admin_username}@${azurerm_public_ip.db["master"].ip_address} ${var.admin_username}@${azurerm_network_interface.db["slave2"].private_ip_address}"
  }
}
