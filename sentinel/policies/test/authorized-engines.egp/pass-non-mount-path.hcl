# A non-mount path (e.g., reading a secret) is not governed by this policy.
# The `when` guard means main evaluates to true for unmatched paths.
global "namespace" {
  value = {
    id   = "root"
    path = ""
  }
}

global "request" {
  value = {
    path      = "secret/data/myapp/config"
    operation = "read"
    data      = {}
  }
}
