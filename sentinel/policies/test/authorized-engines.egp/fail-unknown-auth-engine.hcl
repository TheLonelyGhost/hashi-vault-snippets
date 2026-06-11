global "namespace" {
  value = {
    id   = "root"
    path = ""
  }
}

global "request" {
  value = {
    path      = "sys/auth/ldap"
    operation = "update"
    data = {
      type = "ldap"
    }
  }
}

test {
  rules = {
    main                  = false
    auth_engines_allowlist = false
  }
}
