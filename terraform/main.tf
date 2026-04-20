# =============================================================================
# Terraform Configuration - E-Commerce Database Architecture
# Provider & Resource Group
# =============================================================================

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.116.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Project     = "devops-miniproject2"
    Environment = "development"
    ManagedBy   = "terraform"
  }
}
