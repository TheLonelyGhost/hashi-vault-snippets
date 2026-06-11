global "request" {
  value = {
    path      = "auth/token/role/my-role"
    operation = "create"
    data = {
      orphan = "true"
    }
  }
}

test {
  rules = {
    main                                = false
    blocked_create_token_role_with_orphan = false
  }
}
