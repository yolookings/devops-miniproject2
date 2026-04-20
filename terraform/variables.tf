# =============================================================================
# Input Variables
# =============================================================================

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------
variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "rg-ecommerce-devops"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "southeastasia"
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "vnet_address_space" {
  description = "Address space for the Virtual Network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_app_prefix" {
  description = "Address prefix for the application subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_proxy_prefix" {
  description = "Address prefix for the ProxySQL subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "subnet_db_prefix" {
  description = "Address prefix for the database subnet"
  type        = string
  default     = "10.0.3.0/24"
}

# -----------------------------------------------------------------------------
# Virtual Machines
# -----------------------------------------------------------------------------
variable "vm_size" {
  description = "Size of the Virtual Machines"
  type        = string
  default     = "Standard_B1s"
}

variable "enable_app_vm" {
  description = "Create dedicated application VM. Set false to run app service on proxy node."
  type        = bool
  default     = false
}

variable "admin_username" {
  description = "Admin username for all VMs"
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key_path" {
  description = "Path to the SSH public key file for VM authentication"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------
variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "devops-miniproject2"
    Environment = "development"
    ManagedBy   = "terraform"
  }
}
