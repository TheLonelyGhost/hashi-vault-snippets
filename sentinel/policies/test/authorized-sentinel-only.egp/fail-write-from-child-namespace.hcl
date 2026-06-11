global "namespace" {
  value = {
    id   = "abc123"
    path = "tenant/"
  }
}

global "request" {
  value = {
    path      = "sys/policies/egp/my-policy"
    operation = "update"
    data = {
      policy            = "main = rule { true }"
      enforcement_level = "soft-mandatory"
      paths             = ["*"]
    }
  }
}

test {
  rules = {
    main = false
  }
}
