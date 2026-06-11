global "request" {
  value = {
    path      = "auth/token/create-orphan"
    operation = "update"
    data      = {}
  }
}

test {
  rules = {
    main                           = false
    blocked_create_orphan_endpoint = false
  }
}
