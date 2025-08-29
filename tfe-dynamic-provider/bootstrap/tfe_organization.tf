resource "tfe_variable_set" "vault_connection" {
  name         = "vault-connection"
  organization = var.root_ns_workspace_org
  global       = true
}

resource "tfe_variable" "vault_connection" {
  for_each = {
    # Env var => Value
    "TERRAFORM_VAULT_SKIP_CHILD_TOKEN"             = "true"
    "TFC_DEFAULT_VAULT_ADDR"                       = var.vault_addr
    "TFC_DEFAULT_VAULT_RUN_ROLE"                   = vault_jwt_auth_backend.tfe.default_role
    "TFC_DEFAULT_VAULT_AUTH_PATH"                  = vault_jwt_auth_backend.tfe.path
    "TFC_DEFAULT_VAULT_WORKLOAD_IDENTITY_AUDIENCE" = local.jwt_audience
    # "TFC_DEFAULT_VAULT_ENCODED_CACERT" = "" # TODO: In case we do not honor the signing authority for Vault Server...
  }

  key             = each.key
  value           = each.value
  category        = "env"
  description     = "https://developer.hashicorp.com/terraform/enterprise/workspaces/dynamic-provider-credentials/vault-configuration"
  variable_set_id = tfe_variable_set.vault_connection.id
}
