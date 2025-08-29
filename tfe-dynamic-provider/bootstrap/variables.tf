locals {
  jwt_audience = "hashicorp-vault"
}

variable "vault_addr" {
  type = string

  default = "https://vault.example.com:8200"
}

variable "tfe_hostname" {
  type = string

  default = "app.terraform.io"
}

variable "root_ns_workspace_name" {
  type = string

  default = "vault-ns-root"
}

variable "root_ns_workspace_org" {
  type = string

  default = "infosec"
}
