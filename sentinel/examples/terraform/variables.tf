variable "enforcement_level" {
  type        = string
  default     = "soft-mandatory"
  description = <<-EOT
    Enforcement level for all policies in this example.

    Use "soft-mandatory" in sandbox environments to allow policy overrides
    while validating behavior. Use "hard-mandatory" in production to prevent
    any bypass.

    Valid values: "advisory", "soft-mandatory", "hard-mandatory"
  EOT

  validation {
    condition     = contains(["advisory", "soft-mandatory", "hard-mandatory"], var.enforcement_level)
    error_message = "enforcement_level must be one of: advisory, soft-mandatory, hard-mandatory"
  }
}
