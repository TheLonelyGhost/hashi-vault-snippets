# Mock: service token bound to an identity entity
#
# Copy this global block into your test case when writing RGP tests or any
# policy that inspects token properties. The `entity_id` links this token
# to the entity defined in identity-with-entity.hcl.
#
# Adjust `policies` and `entity_id` to match the scenario under test.
# Set `entity_id = ""` to simulate a token with no identity entity attached
# (e.g., for testing the no-entityless-tokens policy).
#
# Usage: copy the global block below into your test case .hcl file.

global "token" {
  value = {
    entity_id             = "entity-abc-123"
    type                  = "service"
    display_name          = "token-example-entity"
    creation_time         = "2024-06-01T00:00:00Z"
    creation_time_unix    = 1717200000
    creation_ttl_seconds  = 3600
    explicit_max_ttl_seconds = 0
    num_uses              = 0
    period_seconds        = 0
    policies              = ["default", "platform-admin"]
    metadata              = {}
    role                  = ""
    path                  = "auth/token/create"
  }
}
