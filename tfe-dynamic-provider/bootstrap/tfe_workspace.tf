locals {
  workspace_id = data.tfe_workspace.vault_config.id
}
data "tfe_workspace" "vault_config" {
  name         = var.root_ns_workspace_name
  organization = var.root_ns_workspace_org
}

resource "tfe_variable" "enable_vault" {
  key         = "TFC_VAULT_PROVIDER_AUTH"
  value       = "true"
  category    = "env"
  description = "https://developer.hashicorp.com/terraform/enterprise/workspaces/dynamic-provider-credentials/vault-configuration"

  workspace_id = local.workspace_id
}

resource "vault_identity_entity" "ws" {
  policies = [vault_policy.superadmin.name]
}
resource "vault_identity_entity_alias" "ws" {
  name           = local.workspace_id
  mount_accessor = vault_jwt_auth_backend.tfe.accessor
  canonical_id   = vault_identity_entity.ws.id
}
