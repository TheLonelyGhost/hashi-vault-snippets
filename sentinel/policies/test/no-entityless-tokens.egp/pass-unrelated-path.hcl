# A path unrelated to token creation matches none of the three regex when-guards.
# All three sub-rules default to true, so main passes.
global "request" {
  value = {
    path      = "secret/data/myapp/config"
    operation = "read"
    data      = {}
  }
}
