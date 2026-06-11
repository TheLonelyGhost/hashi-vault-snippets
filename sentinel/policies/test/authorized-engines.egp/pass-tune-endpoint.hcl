# Tune requests (path ends in /tune) are excluded from the policy's when-guard.
# The is_mounting_secrets_engine flag is false for tune paths, so main passes unconditionally.
global "namespace" {
  value = {
    id   = "root"
    path = ""
  }
}

global "request" {
  value = {
    path      = "sys/mounts/secret/tune"
    operation = "update"
    data = {
      max_lease_ttl = "768h"
    }
  }
}
