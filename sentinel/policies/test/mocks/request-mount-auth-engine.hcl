# Mock: mount an auth engine (sys/auth/<path> update)
#
# Copy this global block into your test case when simulating a request to
# enable an auth method. Vault uses `operation = "update"` for auth engine
# enable operations.
#
# Adjust `path` (the mount path after `sys/auth/`) and `data.type` to the
# auth engine type under test.
#
# Usage: copy the global block below into your test case .hcl file.

global "request" {
  value = {
    path      = "sys/auth/kubernetes"
    operation = "update"
    data = {
      type = "kubernetes"
    }
  }
}
