# Mock: create a Vault token (auth/token/create)
#
# Copy this global block into your test case when simulating a request to
# the token creation endpoint. Adjust `data` fields to match the scenario
# under test (e.g., add `no_parent = "true"` to test orphan-token logic).
#
# Note: `no_parent` and `orphan` are serialized as strings ("true"/"false")
# in Sentinel's view of request.data, not as booleans.
#
# Usage: copy the global block below into your test case .hcl file.

global "request" {
  value = {
    path      = "auth/token/create"
    operation = "update"
    data      = {}
  }
}
