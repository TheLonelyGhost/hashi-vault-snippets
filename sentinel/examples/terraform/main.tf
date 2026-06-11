# authorized-engines: restricts which secrets engine and auth engine types
# may be mounted across the cluster. Applies to mount and enable operations.
#
# EGP paths:
#   sys/mounts/*  - mounting secrets engines
#   sys/auth/*    - enabling auth methods
#
# The /tune suffix is excluded by the policy itself; requests to tune an
# existing mount are not governed by this policy.
resource "vault_egp_policy" "authorized_engines" {
  name              = "authorized-engines"
  paths             = ["sys/mounts/*", "sys/auth/*"]
  enforcement_level = var.enforcement_level
  policy            = file("${path.module}/../../policies/authorized-engines.egp.sentinel")
}

# authorized-sentinel-only: restricts Sentinel policy writes to the root
# and admin namespaces. Prevents tenant namespaces from creating or modifying
# EGP/RGP policies, which could be used to subvert platform governance.
#
# EGP paths:
#   sys/policies/egp/*  - EGP policy write operations
#   sys/policies/rgp/*  - RGP policy write operations
resource "vault_egp_policy" "authorized_sentinel_only" {
  name              = "authorized-sentinel-only"
  paths             = ["sys/policies/egp/*", "sys/policies/rgp/*"]
  enforcement_level = var.enforcement_level
  policy            = file("${path.module}/../../policies/authorized-sentinel-only.egp.sentinel")
}

# no-entityless-tokens: prevents creation of orphan tokens (tokens with no
# parent and no identity entity). Vault Enterprise counts each entity-less
# token as a discrete licensed Client.
#
# EGP paths:
#   auth/token/create         - standard token creation with no_parent flag
#   auth/token/create-orphan  - dedicated orphan creation endpoint
#   auth/token/role/*         - token role creation/update with orphan setting
resource "vault_egp_policy" "no_entityless_tokens" {
  name              = "no-entityless-tokens"
  paths             = ["auth/token/create", "auth/token/create-orphan", "auth/token/role/*"]
  enforcement_level = var.enforcement_level
  policy            = file("${path.module}/../../policies/no-entityless-tokens.egp.sentinel")
}

# ─── RGP Example (stub) ────────────────────────────────────────────────────
#
# RGPs (Role Governing Policies) differ from EGPs in two important ways:
#
#   1. No `paths` argument — RGPs are not bound to a URI path. They apply
#      to any request made by a token that carries the RGP name, regardless
#      of the path being accessed.
#
#   2. Assignment — After creating an RGP resource here, you must attach it
#      to a Vault identity entity, group, or token role. This is done via:
#        - vault_identity_entity_policies  (for entities)
#        - vault_identity_group_policies   (for groups)
#        - The `token_policies` argument on auth method role resources
#        - vault write auth/token/roles/<name> token_policies="..."
#
#      Assigning the policy is out of scope for this example; it is managed
#      wherever the entity, group, or token role is defined.
#
# Uncomment and adapt the block below to deploy an RGP policy:
#
# resource "vault_rgp_policy" "example" {
#   name              = "example-rgp"
#   enforcement_level = var.enforcement_level
#   policy            = file("${path.module}/../../policies/example.rgp.sentinel")
# }
