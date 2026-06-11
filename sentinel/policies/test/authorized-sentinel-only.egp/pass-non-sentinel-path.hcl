# Writing to an ACL policy path (sys/policies/acl/) is not a sentinel write;
# the when-guard does not match, so main passes unconditionally.
global "namespace" {
  value = {
    id   = "abc123"
    path = "tenant/"
  }
}

global "request" {
  value = {
    path      = "sys/policies/acl/my-acl-policy"
    operation = "update"
    data = {
      policy = "path \"secret/*\" { capabilities = [\"read\"] }"
    }
  }
}
