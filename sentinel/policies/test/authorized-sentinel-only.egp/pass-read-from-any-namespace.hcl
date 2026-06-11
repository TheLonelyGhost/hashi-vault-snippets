# A read operation on a sentinel policy path is not a write; the when-guard
# (is_sentinel_write requires op in ["create","update"]) means main passes.
global "namespace" {
  value = {
    id   = "abc123"
    path = "tenant/"
  }
}

global "request" {
  value = {
    path      = "sys/policies/egp/my-policy"
    operation = "read"
    data      = {}
  }
}
