# Initial bootstrapping

## Prerequisites

- TFE platform is running
- TFE organization has been setup
- TFE workspace has been created within that organization
- TFE workspace has been configured with remote apply
- `terraform login` has been executed for the target TFE platform, providing a valid TFE token
- Vault platform is running and has been initialized

### TFE Permissions

- ability to create a Variable Set
- ability to configure Variable Sets to be globally applied to all workspaces in the organization
- ability to set workspace variables on the target TFE workspace

### Vault Permissions

```hcl
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update"]
}
path "identity/entity" {
  capabilities = ["create"]
}
path "identity/entity/id/*" {
  capabilities = ["read"]
}
path "identity/entity-alias" {
  capabilities = ["create"]
}
path "identity/entity-alias/id/*" {
  capabilities = ["read"]
}
path "sys/auth" {
  capabilities = ["create", "read"]
}
path "sys/auth/*" {
  capabilities = ["create", "read", "update"]
}
path "auth/tfe/*" {
  capabilities = ["create", "read", "update"]
}
```

## Usage

```bash
~/workspace $ cd ./bootstrap
~/workspace $ cat <<'EOH' > ./terraform.auto.tfvars
vault_addr = "https://vault.example.com:8200"
tfe_hostname = "tfe.example.com"

root_ns_workspace_name = "vault-ns-root"
root_ns_workspace_org = "infosec"
EOH

~/workspace $ terraform init
~/workspace $ terraform apply
```

After bootstrapping, see `imports.tf` in this directory (not `bootstrap/`). Note that `imports.tf` is filled with placeholders, the contents of which come from the outputs in the above `terraform apply`.

## Addendum

### Absolute minimum permissions required in Vault

This is the most restrictive policy possible, in terms of security and client licensing concerns. The only way to lock this down further would be to involve Sentinel policies.

```hcl
path "sys/policies/acl/root-operator" {
  capabilities = ["create", "read", "update"]
}
path "sys/policies/acl/baseline-tfe" {
  capabilities = ["create", "read", "update"]
}
path "identity/entity" {
  capabilities = ["create"]

  allowed_parameters = {
    "policies" = ["root-operator"]
  }
}
path "identity/entity/id/*" {
  capabilities = ["read"]
}
path "identity/entity-alias" {
  capabilities = ["create"]
}
path "identity/entity-alias/id/*" {
  capabilities = ["read"]
}
path "sys/auth" {
  capabilities = ["create"]

  allowed_parameters = {
    "type" = ["jwt"]
  }
}
path "sys/auth/tfe" {
  capabilities = ["create", "read", "update"]

  allowed_parameters = {
    "type" = ["jwt"]
    "*" = []
  }
}
path "auth/tfe/config" {
  capabilities = ["create", "read", "update"]
}
path "auth/tfe/role/default" {
  capabilities = ["create", "read", "update"]

  required_parameters = ["token_policies", "claims_mapping", "bound_claims"]
  allowed_parameters = {
    "role_type" = ["jwt"]
    "token_policies" = ["baseline-tfe"]
    "user_claim" = ["terraform_workspace_id"]
    "*" = []
  }
  denied_parameters = {
    "policies" = []
    "verbose_oidc_logging" = []
    "bound_subject" = []
  }
}
```
