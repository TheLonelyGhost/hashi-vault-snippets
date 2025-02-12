variable "vault_fqdn" {
  type        = string
  description = "The fully-qualified domain name of the Vault service (e.g., \"vault.example.com\")"
}

variable "account_numbers" {
  type        = list(string)
  description = "Possible AWS Account Numbers of the where Vault has a foothold credential used to verify incoming AWS identities. Typically this is the same account number as where Vault is hosted."
}
