variable "subscription_id" {
  type        = string
  nullable    = false
  description = "Subscription UUID containing the shared ACA environment."
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "Use the Azure subscription UUID."
  }
}

variable "environment" {
  type        = string
  default     = "dev"
  nullable    = false
  description = "Environment component for LiveDocs and default Products-owned ACA environment names."
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Choose dev, test, or prod."
  }
}

variable "shared_environment" {
  description = "Existing ACA environment lookup. Null selects the Products environment for this environment name."
  type = object({
    name                = string
    resource_group_name = string
  })
  default = null
  validation {
    condition = var.shared_environment == null ? true : (
      can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,58}[a-zA-Z0-9]$", var.shared_environment.name)) &&
      can(regex("^[a-zA-Z0-9_-]{1,90}$", var.shared_environment.resource_group_name))
    )
    error_message = "Supply the existing ACA environment name and resource group, not a URL."
  }
}

variable "livedocs_image" {
  type        = string
  nullable    = false
  description = "Successfully published public LiveDocs image, pinned by its SHA-256 digest."
  validation {
    condition     = can(regex("^mb0101/ecommerce-store-livedocs@sha256:[0-9a-f]{64}$", var.livedocs_image))
    error_message = "Use mb0101/ecommerce-store-livedocs@sha256:<64 lowercase hex characters>; latest and unverified PR images are not accepted."
  }
}

variable "external_ingress_enabled" {
  type        = bool
  default     = false
  nullable    = false
  description = "Explicitly publish the baked documentation over HTTPS. No authentication is added by this stack."
}

variable "min_replicas" {
  type        = number
  default     = 0
  nullable    = false
  description = "0 permits scale-to-zero. Temporarily use 1 for a demo/console; maximum always remains 1."
  validation {
    condition     = contains([0, 1], var.min_replicas)
    error_message = "Choose 0 or 1."
  }
}
