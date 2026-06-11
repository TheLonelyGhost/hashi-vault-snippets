global "namespace" {
  value = {
    id   = "root"
    path = ""
  }
}

global "request" {
  value = {
    path      = "sys/auth/kubernetes"
    operation = "update"
    data = {
      type = "kubernetes"
    }
  }
}
