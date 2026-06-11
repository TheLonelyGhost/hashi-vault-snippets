global "namespace" {
  value = {
    id   = "root"
    path = ""
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
