output "workspace_entity" {
  description = "Vault Entity and Entity Alias, which represent the entity for the TFE workspace managing Vault's root namespace. Import this into the next workspace after bootstrapping."
  value = {
    id       = vault_identity_entity.ws.id
    alias_id = vault_identity_entity_alias.ws.id
  }
}
