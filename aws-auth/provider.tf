provider "aws" {
  profile = "vault-account"

  alias = "vault"
}

provider "aws" {
  profile = "fizz"
  alias   = "fizz"
}

provider "vault" {
  skip_child_token = true
}
