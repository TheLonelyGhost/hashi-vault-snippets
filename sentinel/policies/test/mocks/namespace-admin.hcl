# Mock: admin namespace
#
# Copy this global block into your test case when the request originates
# from the `admin/` namespace. Namespace paths always end in `/` except
# the root namespace.
#
# Usage: copy the global block below into your test case .hcl file.

global "namespace" {
  value = {
    id   = "admin"
    path = "admin/"
  }
}
