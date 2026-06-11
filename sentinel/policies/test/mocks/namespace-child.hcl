# Mock: child (tenant) namespace
#
# Copy this global block into your test case when the request originates
# from a child namespace that is NOT in any policy's EXEMPT_NAMESPACES list.
# Adjust `id` and `path` to match the specific namespace under test.
#
# Usage: copy the global block below into your test case .hcl file.

global "namespace" {
  value = {
    id   = "abc123"
    path = "tenant/"
  }
}
