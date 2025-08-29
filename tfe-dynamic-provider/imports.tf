import {
  id = "root-operator"
  to = vault_policy.superadmin
}
import {
  id = "baseline-tfe"
  to = vault_policy.baseline_tfe
}
import {
  id = "tfe"
  to = vault_jwt_auth_backend.tfe
}
import {
  id = "auth/tfe/role/default"
  to = vault_jwt_auth_backend_role.tfe_default
}
import {
  id = "PLACEHOLDER" # NOTE: See bootstrapping outputs for entity id
  to = vault_identity_entity.ns_root
}
import {
  id = "PLACEHOLDER" # NOTE: See bootstrapping outputs for alias id
  to = vault_identity_entity_alias.ns_root
}
