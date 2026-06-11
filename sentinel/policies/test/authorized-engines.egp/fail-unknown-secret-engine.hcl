global "namespace" {
  value = {
    id   = "root"
    path = ""
  }
}

global "request" {
  value = {
    path      = "sys/mounts/ssh-host"
    operation = "update"
    data = {
      type = "ssh"
    }
  }
}

test {
  rules = {
    main                    = false
    secrets_engines_allowlist = false
  }
}
