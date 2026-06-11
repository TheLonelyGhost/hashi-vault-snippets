# Mock: identity with a fully-shaped entity and group membership
#
# Copy this global block into your test case when writing RGP tests that
# inspect identity.entity metadata, policies, or group membership.
#
# The `identity` global is injected by Vault for authenticated requests.
# For unauthenticated paths (login endpoints), identity may be partially
# populated via lookahead.
#
# Adjust `metadata`, `policies`, and `groups` values to match the scenario
# under test.
#
# Usage: copy the global block below into your test case .hcl file.

global "identity" {
  value = {
    entity = {
      id               = "entity-abc-123"
      name             = "example-entity"
      creation_time    = "2024-01-01T00:00:00Z"
      last_update_time = "2024-06-01T00:00:00Z"
      metadata = {
        "team" = "platform"
        "env"  = "production"
      }
      merged_entity_ids = []
      aliases           = []
      policies          = ["default"]
    }
    groups = {
      by_id = {
        "grp-001" = {
          id               = "grp-001"
          name             = "platform-admins"
          creation_time    = "2024-01-01T00:00:00Z"
          last_update_time = "2024-06-01T00:00:00Z"
          metadata         = {}
          member_entity_ids = ["entity-abc-123"]
          parent_group_ids  = []
          policies          = ["platform-admin"]
        }
      }
      by_name = {
        "platform-admins" = {
          id               = "grp-001"
          name             = "platform-admins"
          creation_time    = "2024-01-01T00:00:00Z"
          last_update_time = "2024-06-01T00:00:00Z"
          metadata         = {}
          member_entity_ids = ["entity-abc-123"]
          parent_group_ids  = []
          policies          = ["platform-admin"]
        }
      }
    }
  }
}
