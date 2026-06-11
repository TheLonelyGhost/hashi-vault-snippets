# An exempt namespace can mount any engine type, including ones not on the allowlist.
global "namespace" {
  value = {
    id   = "admin"
    path = "admin/"
  }
}

global "request" {
  value = {
    path      = "sys/mounts/ssh"
    operation = "update"
    data = {
      type = "ssh"
    }
  }
}
