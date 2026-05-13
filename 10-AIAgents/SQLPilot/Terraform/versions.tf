################################################################################
# versions.tf
#
# Lock the AzureRM provider to a known-good major version. The 4.x line is
# current as of May 2026; pinning to ~> 4.0 lets patch updates flow in but
# blocks any breaking major-version change.
#
# Terraform itself is pinned to >= 1.6 because we use the optional() type
# constructor in variables (1.3+) and the moved {} block (1.1+) elsewhere.
################################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  # features {} is required on the AzureRM provider even when no nested
  # block is needed. Leaving it empty applies sensible defaults.
  features {}
}
