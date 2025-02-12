variable "vault_fqdn" {
  type        = string
  description = "The fully-qualified domain name of the Vault service (e.g., \"vault.example.com\")"
}

variable "account_numbers" {
  type        = list(string)
  description = "A list of AWS Account Numbers where AWS auth is expected to be configured"
}
