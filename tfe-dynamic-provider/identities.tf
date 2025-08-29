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

resource "vault_identity_entity" "ns_root" {
  name = "Vault NS - root"

  policies = [vault_policy.superadmin.name]
}
resource "vault_identity_entity_alias" "ns_root" {
  canonical_id   = vault_identity_entity.ns_root.id
  name           = "PLACEHOLDER" # TODO: hardcode the workspace id (e.g., `ws-2lkdafi3`) for the workspace managing this root namespace
  mount_accessor = vault_jwt_auth_backend.tfe.accessor
}
