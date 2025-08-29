terraform {
  cloud {
    hostname     = "tfe.example.com"
    organization = "infosec"

    workspaces {
      name = "vault-ns-root"
    }
  }
}
