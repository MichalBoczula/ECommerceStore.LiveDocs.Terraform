variable "subscription_id" {
  description = "Azure subscription UUID; use the same subscription in Azure CLI."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "Use the Azure subscription UUID."
  }
}

variable "environment" {
  type        = string
  default     = "dev"
  nullable    = false
  description = "Archive environment; choose a separate backend key for each environment."
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Choose dev, test, or prod."
  }
}

variable "name_suffix" {
  type        = string
  nullable    = false
  description = "Stable, globally unique 3-8 lowercase letters/digits for the dedicated archive account."
  validation {
    condition     = can(regex("^[a-z0-9]{3,8}$", var.name_suffix))
    error_message = "Use 3-8 lowercase letters or digits and keep the suffix stable."
  }
}

variable "location" {
  type        = string
  default     = "northeurope"
  nullable    = false
  description = "Azure region identifier for the persistent archive and CI identities."
  validation {
    condition     = can(regex("^[a-z][a-z0-9]+$", var.location))
    error_message = "Use an Azure region identifier such as northeurope."
  }
}

variable "enable_reader_federation" {
  type        = bool
  default     = false
  nullable    = false
  description = "Enable only after protecting livedocs-archive-build and livedocs-archive-pr GitHub environments as documented. Never trust the bare pull_request subject."
}

variable "operator_object_id" {
  type        = string
  default     = null
  description = "Optional human Entra object UUID for read-only archive verification. CI identities have separate roles."
  validation {
    condition     = var.operator_object_id == null ? true : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.operator_object_id))
    error_message = "Use the operator's Entra object UUID, or null."
  }
}
