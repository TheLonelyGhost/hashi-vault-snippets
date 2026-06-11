# Mock: root namespace
#
# Copy this global block into your test case when the request originates
# from the Vault root namespace. The root namespace path is an empty string
# and never ends in `/`.
#
# Usage: copy the global block below into your test case .hcl file.

global "namespace" {
  value = {
    id   = "root"
    path = ""
  }
}
