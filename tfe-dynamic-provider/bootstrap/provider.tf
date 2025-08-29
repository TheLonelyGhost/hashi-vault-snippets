provider "vault" {
  // NOTE: Specify `VAULT_TOKEN` accordingly
  address = var.vault_addr

  add_address_to_env = true
}

provider "tfe" {
  hostname = var.tfe_hostname
  // NOTE: Specify `TFE_TOKEN` and (if necessary) `TFE_SSL_SKIP_VERIFY` accordingly
}
