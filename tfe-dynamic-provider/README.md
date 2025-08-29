# Manage access to Vault via TFE workload identity

> **NOTE:** For the purposes of this snippet, "TFE" collectively means self-managed Terraform Enterprise or HCP Terraform (a.k.a., Terraform Cloud). There is no meaningful difference between the two in this particular context.

## Setup

See [BOOTSTRAP](./BOOTSTRAP.md) for initial setup.

## Regular usage

Tips:

- Make use of terraform references. When assigning a policy, refer to it via `vault_policy.foo.name` instead of `"my_policy"`. This will help reduce impact of typos which, in some cases, are very difficult to detect.
- Start small, import a few things created outside of Terraform, and hardcode.
    - Import a resource created elsewhere (via `import` blocks) and continue changing it until `terraform plan` indicates there are no more changes.
    - Once it is imported, carefully apply whatever transformations to make it conform to your chosen standard
    - Start by hardcoding resulting names in Terraform (e.g., `"my_policy"`), then iteratively replace with references (e.g., `vault_policy.foo.name`)
- Manage only 1 Vault namespace with a given TFE workspace
    - Without a delineation like this, the number of resources managed by Terraform could grow to require `-target` to be used on `terraform plan` or `apply` and lengthen times to execute a small change.
- Optimize for copy-paste, not for module development. Avoid using Terraform modules for organization, except where necessary to relieve naming collisions (e.g., the `super_admin` part of `resource "vault_policy" "super_admin" {`).
    - Annotate for copy-paste
    - As complexity grows, create groupings of code that can be copied from another source (e.g., a README code block)
    - As complexity grows further, only _then_ institute a local Terraform module (i.e., avoid publishing to TFE Private Module Registry)
    - As reusability grows further, consider packaging as a published Terraform module in the TFE Private Module Registry
- Minimize calls to non-Vault data sources.
    - Instead of pushing a KV secret into a unique location, prefer to come up with a convention for KV mount structure and follow that convention in multiple locations.
    - Calls to data sources will slow down a Terraform run, or make a given Terraform phase refuse to continue without `-target` due to overwhelming complexity. Use of data sources can increase that there there is another option to avoid that situation entirely.
- Organize auth methods in a file prefixed with `auth_`, such as `auth_tfe.tf` containing settings for the JWT auth method enabling the TFE platform.
    - Manage each discrete auth role under that auth method in the same file.
    - Where feasible, manage entity aliases near the auth role.
