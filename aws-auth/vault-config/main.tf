locals {
  target_aws_account_nums = var.account_numbers
  vault_fqdn              = var.vault_fqdn
}

resource "vault_auth_backend" "aws" {
  type = "aws"
}

resource "vault_aws_auth_backend_client" "client" {
  backend = vault_auth_backend.aws.path

  use_sts_region_from_client = true
}

resource "vault_aws_auth_backend_config_identity" "identity_config" {
  backend = vault_auth_backend.aws.path

  iam_alias = "role_id" # GUID of the vault auth role, generated on role creation
  iam_metadata = [
    "canonical_arn",
    "account_id",
    "inferred_aws_region",
  ]
}

resource "vault_aws_auth_backend_sts_role" "sts" {
  for_each = toset(local.target_aws_account_nums)

  backend     = vault_auth_backend.aws.path
  account_id  = each.value
  sts_role    = "arn:aws:iam::${each.value}:role/VaultAuth"
  external_id = local.vault_fqdn
}
