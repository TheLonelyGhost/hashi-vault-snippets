# Mock: write a Sentinel EGP policy (sys/policies/egp/<name> create/update)
#
# Copy this global block into your test case when simulating a request to
# create or update a Sentinel EGP policy. Use `operation = "update"` for
# both creates and updates (Vault uses "update" for write operations on
# sys/policies/* endpoints).
#
# Swap the path prefix for `sys/policies/rgp/` to simulate an RGP write.
#
# Usage: copy the global block below into your test case .hcl file.

global "request" {
  value = {
    path      = "sys/policies/egp/my-policy"
    operation = "update"
    data = {
      policy           = "main = rule { true }"
      enforcement_level = "soft-mandatory"
      paths            = ["*"]
    }
  }
}
