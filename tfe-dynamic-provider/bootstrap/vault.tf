data "vault_policy_document" "baseline_tfe" {
  rule {
    description  = "Allow tokens to query themselves"
    path         = "auth/token/lookup-self"
    capabilities = ["read"]
  }
  rule {
    description  = "Allow tokens to renew themselves"
    path         = "auth/token/renew-self"
    capabilities = ["update"]
  }
  rule {
    description  = "Allow tokens to revoke themselves"
    path         = "auth/token/revoke-self"
    capabilities = ["update"]
  }
}
resource "vault_policy" "baseline_tfe" {
  name   = "baseline-tfe"
  policy = data.vault_policy_document.baseline_tfe.hcl
}

resource "vault_jwt_auth_backend" "tfe" {
  type        = "jwt"
  path        = "tfe"
  description = "https://developer.hashicorp.com/terraform/enterprise/workspaces/dynamic-provider-credentials/vault-configuration"

  oidc_discovery_url = "https://${var.tfe_hostname}"
  bound_issuer       = "https://${var.tfe_hostname}"

  default_role = "default"
}

resource "vault_jwt_auth_backend_role" "default" {
  backend = vault_jwt_auth_backend.tfe.path

  role_name  = "default"
  role_type  = "jwt"
  user_claim = "terraform_workspace_id"

  token_no_default_policy = true
  token_policies          = [vault_policy.baseline_tfe.name]

  bound_audiences   = [local.jwt_audience]
  bound_claims_type = "glob"
  bound_claims = {
    terraform_workspace_id = data.tfe_workspace.vault_config.id
    # terraform_organization_name = join(",", distinct(var.tfe_organizations))
  }

  claim_mappings = {
    "terraform_organization_id"   = "tfe_organization_id"
    "terraform_organization_name" = "tfe_organization"
    "terraform_project_id"        = "tfe_project_id"
    "terraform_project_name"      = "tfe_project"
    "terraform_workspace_id"      = "tfe_workspace_id"
    "terraform_workspace_name"    = "tfe_workspace"

    # NOTE: These are helpful for troubleshooting via Vault audit logs, but can lead to high churn and performance issues. Enable at your own risk:
    #
    # "terraform_run_id"    = "tfe_run_id"
    # "terraform_run_phase" = "tfe_run_phase"
  }
}

data "vault_policy_document" "superadmin" {
  rule {
    description  = "Do anything, unless specifically prevented"
    path         = "*"
    capabilities = ["create", "read", "update", "delete", "list", "sudo", "subscribe"]
  }
}
resource "vault_policy" "superadmin" {
  name   = "root-operator"
  policy = data.vault_policy_document.superadmin.hcl
}
