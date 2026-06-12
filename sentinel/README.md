# Sentinel Policies

## Choosing a Policy Type

Start with an **ACL policy**. They require no Enterprise license, are fastest, and
are evaluated only for tokens/identities they're attached to. Use Sentinel (EGP/RGP)
only when ACL logic is insufficient. Sentinel runs on every matching request and
adds latency that may be unacceptable for runtime secret fetches.

| | ACL | EGP | RGP |
|---|---|---|---|
| **Requires Enterprise?** | No | Yes | Yes |
| **Fires on** | Requests by tokens/entities carrying the policy | All requests matching a URI path glob | All requests by tokens/entities carrying the policy |
| **Bound to** | Tokens, entities, groups | URI path globs | Tokens, entities, groups |
| **Sentinel logic?** | No | Yes | Yes |
| **Performance** | Fastest | Slowest | Slow |
| **Typical use** | "Can this identity read this path?" | "Nobody can do X at this path" | "Apply these boundaries to already-assigned, ACL-granted permissions" |

For background, see the [HashiCorp developer docs](https://developer.hashicorp.com/vault/docs/enterprise/sentinel).

## Repository Layout

`policies/` contains files named `<purpose>.egp.sentinel` or `<purpose>.rgp.sentinel`.
Tests live under `policies/test/`, with one subdirectory per policy (named after
the policy file, minus `.sentinel`) and shared mock globals under `policies/test/mocks/`.

```
examples/
├── github-workflows/
└── terraform/
policies/
├── <policy>.egp.sentinel
├── <other>.rgp.sentinel
├── ...
└── test/
    ├── <policy>.egp/                   # policy filename without `.sentinel`
    │   ├── fail-<scenario>.hcl
    │   ├── pass-<scenario>.hcl
    │   └── ...
    ├── <other>.rgp/
    │   ├── fail-<scenario>.hcl
    │   ├── pass-<scenario>.hcl
    │   └── ...
    └── mocks/
        ├── <module>-<identifier>.hcl    # module being one of `identity`, `namespace`, ...
        └── ...

```

## Prerequisites

- **Sentinel CLI** — [install](https://developer.hashicorp.com/sentinel/install).
  Pin to the Sentinel version embedded in your target Vault Enterprise release
  ([release notes](https://developer.hashicorp.com/vault/docs/updates/release-notes)).
- **Terraform CLI** — [install](https://developer.hashicorp.com/terraform/install).
- **Vault Enterprise sandbox** — token with write access to `sys/policies/egp/*`
  and `sys/policies/rgp/*`.

## Development Loop

```
Edit policy → update tests → sentinel test → sentinel fmt → git commit → repeat
```

```bash
sentinel test policies/                                   # all tests
sentinel test policies/authorized-engines.egp.sentinel    # single policy
sentinel test -verbose policies/                          # verbose
```

## Writing a Policy

### Filename

```
policies/<descriptive-name>.egp.sentinel   # Endpoint Governing Policy
policies/<descriptive-name>.rgp.sentinel   # Role Governing Policy
```

Use kebab-case. The type suffix determines the test directory name.

### Available Vault Globals

Vault injects these at runtime — no `import` needed:

| Global | Type | Description |
|---|---|---|
| `namespace.id` | string | Namespace ID |
| `namespace.path` | string | Namespace path (`""` = root, `"admin/"` = admin) |
| `request.path` | string | URI path (leading `/` stripped) |
| `request.operation` | string | `"read"`, `"update"`, `"create"`, `"delete"`, `"list"` |
| `request.data` | map | Request body |
| `token.policies` | list(string) | Policies on the requesting token |
| `token.entity_id` | string | Entity ID bound to the token |
| `identity.entity.metadata` | map(string) | Entity metadata |
| `identity.groups.by_id` | map | Group id → group object |

([Full reference](https://developer.hashicorp.com/vault/docs/enterprise/sentinel/properties))

### Policy Structure

```sentinel
import "strings"

EXEMPT_NAMESPACES = ["admin/"]

is_exempt = func() {
  return namespace.path in EXEMPT_NAMESPACES
}

my_condition = rule when <precondition> {
  <boolean expression>
}

# <message shown when Sentinel blocks the action>
main = rule when <precondition> {
  my_condition or is_exempt()
}
```

`rule when <expr>` guards rules to specific operations/paths. When the `when` condition
is false, the rule passes automatically.

## Writing Tests

### Structure

```
policies/
├── my-policy.egp.sentinel
└── test/
    ├── mocks/                 ← shared global blocks
    └── my-policy.egp/        ← named after policy, without .sentinel
        ├── pass-<scenario>.hcl
        └── fail-<scenario>.hcl
```

### Test Case Format

```hcl
global "namespace" {
  value = { id = "root", path = "" }
}

global "request" {
  value = {
    path      = "sys/mounts/secret"
    operation = "update"
    data      = { type = "kv-v2" }
  }
}

test {
  rules = {
    main = false
    secrets_engines_allowlist = false
  }
}
```

If the `test {}` block is omitted, the test asserts `main = true`.

### EGP Tests

Mock `namespace` and `request`. Cover: a passing case, a failing case, any exemption paths, and any `when`-guard bypasses.

### RGP Tests

Mock `identity` and `token` (not `request.path`):

```hcl
global "identity" {
  value = {
    entity = {
      id = "entity-abc-123", name = "example-entity"
      metadata = { "team" = "platform" }
      policies = [], aliases = [], merged_entity_ids = []
    }
    groups = { by_id = {}, by_name = {} }
  }
}

global "token" {
  value = { entity_id = "entity-abc-123", type = "service", policies = ["platform-admin"] }
}
```

### Shared Mocks

`policies/test/mocks/` contains ready-to-copy `global` blocks:

| File | Provides |
|---|---|
| `namespace-root.hcl` | `global "namespace"` for root namespace |
| `namespace-admin.hcl` | `global "namespace"` for `admin/` |
| `namespace-child.hcl` | `global "namespace"` for non-exempt child |
| `request-mount-secrets-engine.hcl` | `global "request"` for `sys/mounts/*` update |
| `request-mount-auth-engine.hcl` | `global "request"` for `sys/auth/*` update |
| `request-sentinel-policy-write.hcl` | `global "request"` for `sys/policies/egp/*` write |
| `request-token-create.hcl` | `global "request"` for `auth/token/create` |
| `identity-with-entity.hcl` | `global "identity"` with entity + group membership |
| `token-with-entity.hcl` | `global "token"` with entity binding |

> [!note]
>
> The `mock { module { source = "..." } }` pattern only works for explicit `import`
> statements. Vault's injected globals (`namespace`, `request`, `token`, `identity`)
> must use `global` blocks.

## Deploying to Sandbox

The `examples/terraform/` directory deploys all policies to a Vault Enterprise cluster.

```bash
~/workspace $ cd examples/terraform
~/workspace $ terraform init

~/workspace $ export VAULT_ADDR="https://vault-sandbox.example.com:8200"
~/workspace $ export VAULT_TOKEN="<sandbox-vault-token>"
~/workspace $ export TF_VAR_enforcement_level="soft-mandatory"  # allows override while validating

~/workspace $ terraform plan
~/workspace $ terraform apply
```

Verify:

```bash
vault list sys/policies/egp
vault list sys/policies/rgp
vault read sys/policies/egp/authorized-engines
```

## Promoting to Production

No direct `terraform apply` to production. All changes follow the PR flow:

```
PR opened
  └─ CI: sentinel test        ← blocks merge on failure
  └─ CI: terraform plan (sandbox)

PR merged to main
  └─ CI: terraform apply → sandbox (auto)

sandbox apply succeeds
  └─ GitHub Actions "production" environment gate (requires reviewer approval)
  └─ CI: terraform apply → production (enforcement_level: hard-mandatory)
```

### One-Time GitHub Setup

Go to **Settings → Environments → New environment**, name it `production`, and
add required reviewers. The `terraform-apply-production` job in `.github/workflows/sentinel-test.yml`
pauses at this gate.

### Required Secrets

| Secret | Used by |
|---|---|
| `SANDBOX_VAULT_ADDR` | plan-sandbox, apply-sandbox |
| `SANDBOX_VAULT_TOKEN` | plan-sandbox, apply-sandbox |
| `PROD_VAULT_ADDR` | apply-production |
| `PROD_VAULT_TOKEN` | apply-production |
