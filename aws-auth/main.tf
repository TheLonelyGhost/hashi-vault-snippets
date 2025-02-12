locals {
  vault_foothold_account_numbers = [
    "000000001",
    "000000002",
  ]
  target_account_numbers = concat(local.vault_foothold_account_numbers, [
    "000000003",
    "000000004",
    "000000005",
    "000000006",
    "000000007",
    "000000008",
    "000000009",
  ])
  vault_fqdn = "vault.example.com"
}

module "host_account" {
  source = "./host-account"

  for_each = toset(local.vault_foothold_account_numbers)

  account_number = each.value

  providers = {
    aws = aws.vault
  }
}

module "target_account" {
  source = "./target-account"

  for_each = toset(local.target_account_numbers)

  vault_fqdn      = local.vault_fqdn
  account_numbers = local.vault_foothold_account_numbers

  providers = {
    aws = aws.fizz
  }
}

module "config" {
  source = "./vault-config"

  vault_fqdn      = local.vault_fqdn
  account_numbers = local.target_account_numbers

  providers = {
    vault = vault
  }
}
