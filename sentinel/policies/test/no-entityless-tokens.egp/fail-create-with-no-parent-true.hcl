global "request" {
  value = {
    path      = "auth/token/create"
    operation = "update"
    data = {
      no_parent = "true"
    }
  }
}

test {
  rules = {
    main                              = false
    blocked_create_token_with_no_parent = false
  }
}
