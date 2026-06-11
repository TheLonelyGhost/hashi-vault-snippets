# Mock: mount a secrets engine (sys/mounts/<path> update)
#
# Copy this global block into your test case when simulating a request to
# mount a secrets engine. Vault uses `operation = "update"` for both initial
# mounts and subsequent updates; `"create"` is not used here.
#
# Adjust `path` (the mount path after `sys/mounts/`) and `data.type` to the
# engine type under test.
#
# Usage: copy the global block below into your test case .hcl file.

global "request" {
  value = {
    path      = "sys/mounts/secret"
    operation = "update"
    data = {
      type = "kv-v2"
    }
  }
}
