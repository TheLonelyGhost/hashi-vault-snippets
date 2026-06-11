global "namespace" {
  value = {
    id   = "root"
    path = ""
  }
}

global "request" {
  value = {
    path      = "sys/mounts/secret"
    operation = "update"
    data = {
      type = "kv-v2"
    }
  }
}
