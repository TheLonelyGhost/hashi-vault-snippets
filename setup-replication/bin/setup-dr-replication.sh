#!/usr/bin/env bash
set -euo pipefail

if ((BASH_VERSINFO[0] < 4)); then
  printf 'ERROR: This script requires a Bash version >= 4.0 to execute.\n' >&2
  exit 1
fi

declare -a _curl_flags
_curl_flags=(--fail --show-error --silent)

log_msg() {
  printf '%s\n' "$*" >&2
}

display_vault_warnings() {
  local pythonscript
  pythonscript="$(
    cat <<'SCRIPT'
import json
import sys

def print_msgs(level, msgs):
    for msg in msgs:
        sys.stderr.write("{}: {}\n\n".format(
          level.upper(),
          msg,
        ))


obj = json.loads(sys.argv[1])
if 'warnings' in obj and isinstance(list, obj['warnings']):
    print_msgs('WARNING', obj['warnings'])
if 'errors' in obj and isinstance(list, obj['errors']):
    print_msgs('ERROR', obj['errors'])
    sys.exit(1)
SCRIPT
  )"

  python3 -c "$pythonscript" "$1"
}

env_var_or_prompt() {
  local var_name
  var_name="$1"
  if ! declare -p "$var_name" >/dev/null 2>&1; then
    if [ $# -gt 1 ]; then
      read -r -p "$2: " "${var_name?}"
    else
      read -r -p "${var_name}=" "${var_name?}"
    fi
  fi
  printf '%s\n' "${!var_name}"
}

pause() {
  if [ -n "${1:-}" ]; then
    printf '%s\n' "${1}" >&2
  fi
  read -p 'Press [ENTER] to continue, [Ctrl-C] to abort' -s -r _
  printf '\n'
}

assert_has_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    if [ $# -gt 1 ]; then
      printf 'MISSING: %s must be installed\n' "$2" >&2
    else
      # shellcheck disable=SC2016
      printf 'MISSING: `%s` command is required\n' "$1" >&2
    fi
    return 2
  fi
}

_target_var() {
  local target var_name var
  target="$1"
  var_name="$2"
  var="${var_name}_${target}"

  printf '%s\n' "${!var}"
}
vault_api_anon() {
  local target method uri_path addr flags resp exitcode
  target="$1"
  method="$2"
  addr="$(_target_var "$target" VAULT_ADDR)"
  uri_path="${3##/}"
  declare -a flags
  flags=(
    "${_curl_flags[@]}"
    --request "$method"
    --header "Accept: application/json"
  )
  if [ $# -gt 3 ]; then
    flags+=(
      --header "Content-Type: application/json"
      --data "$4"
    )
  fi

  set +e
  resp="$(curl "${flags[@]}" "${addr}/v1/${uri_path}")"
  exitcode=$?
  set -e
  if [ -n "$resp" ]; then
    display_vault_warnings "$resp"
  fi
  return $exitcode
}
vault_api() {
  local target method uri_path addr flags resp exitcode
  target="$1"
  method="$2"
  addr="$(_target_var "$target" VAULT_ADDR)"
  uri_path="${3##/}"
  declare -a flags
  flags=(
    "${_curl_flags[@]}"
    --request "$method"
    --header "Accept: application/json"
    --header "X-Vault-Token: $(_target_var "$target" VAULT_TOKEN)"
  )
  if [ $# -gt 3 ]; then
    flags+=(
      --header "Content-Type: application/json"
      --data "$4"
    )
  fi

  set +e
  resp="$(curl "${flags[@]}" "${addr}/v1/${uri_path}")"
  exitcode=$?
  set -e
  if [ -n "$resp" ]; then
    display_vault_warnings "$resp"
  fi
  return $exitcode
}

check_is_unsealed() {
  vault_api_anon "$1" GET /sys/health 2>/dev/null | jq 'if .data.sealed then halt_error(1) else true end' >/dev/null 2>&1
}
assert_is_unsealed() {
  if ! check_is_unsealed "$1"; then
    printf 'ERROR: %s is sealed\n' "$(_target_var "$1" VAULT_ADDR)" >&2
    return 1
  fi
}

check_is_initialized() {
  vault_api_anon "$1" GET /sys/health 2>/dev/null | jq 'if .data.initialized then true else halt_error(1) end' >/dev/null 2>&1
}
assert_is_initialized() {
  if ! check_is_initialized "$1"; then
    printf 'ERROR: %s must be initialized before proceeding\n' "$(_target_var "$1" VAULT_ADDR)" >&2
    return 1
  fi
}

check_is_listening() {
  local url host port
  url="$1"
  host="$(python3 -c 'import sys, urllib.parse; parts = urllib.parse.urlparse(sys.argv[1]); print(parts.hostname)' "$url")"
  port="$(python3 -c 'import sys, urllib.parse; parts = urllib.parse.urlparse(sys.argv[1]); port = parts.port if parts.port is not None else (443 if parts.scheme == "https" else 80); print(port)' "$url")"

  nc -z "$host" "$port" >/dev/null
}
assert_is_listening() {
  local url host port
  url="$1"
  host="$(python3 -c 'import sys, urllib.parse; parts = urllib.parse.urlparse(sys.argv[1]); print(parts.hostname)' "$url")"
  port="$(python3 -c 'import sys, urllib.parse; parts = urllib.parse.urlparse(sys.argv[1]); port = parts.port if parts.port is not None else (443 if parts.scheme == "https" else 80); print(port)' "$url")"

  if ! nc -z "$host" "$port" >/dev/null; then
    printf 'ERROR: %s is not listening on port %s\n' "$host" "$port/tcp" >&2
    return 1
  fi
}

transform_to_cluster_addr() {
  # NOTE: This assumes the cluster_addr is always on 8201/tcp
  local url
  url="$1"
  python3 -c 'import sys, urllib.parse; parts = urllib.parse.urlparse(sys.argv[1]); parts = parts._replace(scheme="https", netloc=f"{parts.hostname}:8201"); print(parts.geturl())' "$url"
}

check_valid_token() {
  vault_api "$1" GET /auth/token/lookup-self >/dev/null 2>&1
}
assert_valid_token() {
  if ! check_valid_token "$1"; then
    printf 'ERROR: Vault token for %s is invalid\n' "$(_target_var "$1" VAULT_ADDR)" >&2
    return 1
  fi
}

get_dr_mode() {
  vault_api "$1" GET /sys/replication/dr/status | jq -r '.data.mode'
}
check_is_dr_disabled() {
  [ "$(get_dr_mode "$1")" == "disabled" ]
}
assert_dr_feature_is_disabled() {
  local mode
  mode="$(get_dr_mode "$1")"

  if [ "$mode" != "disabled" ]; then
    printf 'ERROR: Disaster Recovery replication for %s is "%s", not "disabled"\n' "$(_target_var "$1" VAULT_ADDR)" "$mode" >&2
    return 1
  fi
}
check_is_dr_primary() {
  [ "$(get_dr_mode "$1")" == "primary" ]
}
assert_dr_primary() {
  local mode
  mode="$(get_dr_mode "$1")"

  if [ "$mode" != "primary" ]; then
    printf 'ERROR: Disaster Recovery replication for %s is "%s", not "primary"\n' "$(_target_var "$1" VAULT_ADDR)" "$mode" >&2
    return 1
  fi
}
check_is_dr_secondary() {
  [ "$(get_dr_mode "$1")" == "secondary" ]
}
assert_dr_secondary() {
  local mode
  mode="$(get_dr_mode "$1")"

  if [ "$mode" != "secondary" ]; then
    printf 'ERROR: Disaster Recovery replication for %s is "%s", not "secondary"\n' "$(_target_var "$1" VAULT_ADDR)" "$mode" >&2
    return 1
  fi
}

check_dr_replication_license() {
  vault_api "$1" GET /sys/license/status | jq -e '[.data.autoloaded.features[] | select(. == "DR Replication")] | any' >/dev/null
}
assert_dr_replication_license() {
  if ! check_dr_replication_license "$1"; then
    printf 'ERROR: The applied Vault Enterprise license for %s does not seem to include support for DR Replication\n' "$(_target_var "$1" VAULT_ADDR)" >&2
    return 1
  fi
}

check_dr_primary_replication_is_configured_correctly() {
  local resp mode
  resp="$(vault_api primary GET /sys/replication/dr/status)"
  mode="$(jq -r '.data.mode' <<<"$resp")"

  if [ "$mode" != "primary" ]; then
    return 1
  fi

  if ! jq -e --arg addr "$VAULT_CLUSTER_ADDR_primary" '.data.primary_cluster_addr == $addr' <<<"$resp" >/dev/null 2>&1; then
    return 1
  fi
}

disable_dr_primary_replication() {
  vault_api primary POST /sys/replication/dr/primary/disable >/dev/null
}

enable_dr_primary_replication() {
  # NOTE: We may want to put a warning of temp outage in this location
  # too, but it seems redundant given it is already immediately prior
  # to executing this in all other code paths.
  vault_api primary POST /sys/replication/dr/primary/enable "$(jq --null-input --arg addr "$VAULT_CLUSTER_ADDR_primary" '{"primary_cluster_addr": $addr}')" >/dev/null
}

enable_dr_secondary_replication() {
  local resp pubkey
  pause "Retrieving public keys from ${VAULT_ADDR_secondary}"
  resp="$(vault_api secondary POST /sys/replication/dr/secondary/generate-public-key)"
  pubkey="$(jq -r '.data.secondary_public_key' <<<"$resp")"
  pause "Retrieving invitation to join ${VAULT_ADDR_primary} as a DR secondary cluster. Note that once the invitation is generated, it expires after 30 minutes."
  resp="$(vault_api primary POST /sys/replication/dr/primary/secondary-token "$(jq --null-input --arg pubkey "$pubkey" --arg ident "$VAULT_SECONDARY_IDENTIFIER" '{"secondary_public_key": $pubkey, "id": $ident, "ttl": "30m"}')")"
  JOIN_TOKEN="$(jq -r '.data.token' <<<"$resp")"

  pause "Accept the invitation to join?"
  vault_api secondary POST /sys/replication/dr/secondary/enable "$(jq --null-input --arg token "$JOIN_TOKEN" '{"token": $token}')"
  printf 'Invitation has been accepted. %s is now replicating data from %s\n' "${VAULT_ADDR_secondary}" "${VAULT_ADDR_primary}"
  unset JOIN_TOKEN
}

get_dr_operation_token() {
  local msg
  if [ -z "${DR_OPERATION_TOKEN:-}" ]; then
    msg="$(
      cat <<'EOH'
WARNING! Generating a DR Operation Token requires a quorum of key shares for the DR Primary cluster.

Auto-unseal clusters (e.g., GCP Cloud KMS): A quorum of Recovery Key shares must be presented.
Manual unseal clusters (e.g., Shamir keys): A quorum of Shamir keys must be presented.

Follow instructions documented at https://developer.hashicorp.com/vault/tutorials/enterprise/disaster-recovery#generate-a-dr-operation-token
EOH
    )"
    pause "$msg"
  fi
  DR_OPERATION_TOKEN="$(env_var_or_prompt DR_OPERATION_TOKEN 'Decoded DR Operation Token (will be revoked at the end of this script): ')"
}

disable_dr_secondary_replication() {
  local msg
  msg="$(
    cat <<'EOH'
WARNING! This functionality is still in alpha phases.

A simpler way to reset a DR secondary cluster's replication status is to scale it to zero and
delete all snapshotted data, putting it back in a clean slate. Then re-initialize (and unseal)
the cluster.

If you choose to proceed anyway, a DR Operation Token must be used.
EOH
  )"
  pause "$msg"
  get_dr_operation_token
  vault_api_anon secondary POST /sys/replication/dr/secondary/disable "$(jq --arg token "$DR_OPERATION_TOKEN" --null-input '{"dr_operation_token": $token}')"
}

revoke_dr_secondary_connection() {
  vault_api primary POST /sys/replication/dr/primary/revoke-secondary "$(jq --arg ident "$VAULT_SECONDARY_IDENTIFIER" --null-input '{ "id": $ident }')" >/dev/null
}

check_dr_secondary_is_connected() {
  local resp mode
  resp="$(vault_api primary GET /sys/replication/dr/status)"
  mode="$(jq -r '.data.mode' <<<"$resp")"

  if [ "$mode" != "primary" ]; then
    # This cluster is either misconfigured as a secondary, or has DR feature disabled. Either
    # way, the desired secondary is not currently configured as a secondary on this cluster.
    return 1
  fi
  if ! jq --arg ident "$VAULT_SECONDARY_IDENTIFIER" -e '[.data.known_secondaries[] | select(. == $ident)] | any' <<<"$resp" >/dev/null; then
    return 1
  fi
}

cleanup() {
  if [ -n "${DR_OPERATION_TOKEN:-}" ]; then
    log_msg "Revoking previously generated DR Operation Token"
    vault_api primary POST auth/token/revoke "$(jq --arg token "$DR_OPERATION_TOKEN" --null-input '{"token": $token}')" >/dev/null
  fi
  if [ -n "${JOIN_TOKEN:-}" ]; then
    log_msg "Cleaning up previous, incomplete attempt to join to the cluster"
    revoke_dr_secondary_connection
  fi
}
trap 'cleanup' EXIT

cat <<EOF
=================================================================
|                                                               |
|       Runbook: Setup Disaster Recovery (DR) Replication       |
|                                                               |
=================================================================

CAVEAT: Both the primary and secondary clusters must be both
    initialized and unsealed.
EOF
assert_has_command jq
assert_has_command curl
assert_has_command nc netcat
assert_has_command python3 # Only need what's in the standard library
pause

if [ -z "${VAULT_ADDR_primary:-}" ] || [ -z "${VAULT_TOKEN_primary:-}" ]; then
  msg="$(
    cat <<'EOH'
This section will prompt you for the Vault API information of the Disaster Recovery (DR) PRIMARY cluster.

Please remember that in a DR replication relationship, the DR secondary cluster is receiving live updates
from the primary, but is NOT able to be used until explicitly told the primary cluster is offline and that
the DR secondary should take over for it. Do not expect to use the DR secondary cluster while it remains
in this "secondary" state.
EOH
  )"
  log_msg "$msg"
  VAULT_ADDR_primary="$(env_var_or_prompt VAULT_ADDR_primary)"
  VAULT_TOKEN_primary="$(env_var_or_prompt VAULT_TOKEN_primary)"
fi
if [ -z "${VAULT_ADDR_secondary:-}" ] || [ -z "${VAULT_TOKEN_secondary:-}" ]; then
  msg="$(
    cat <<'EOH'
This section will prompt you for the Vault API information of the Disaster Recovery (DR) SECONDARY cluster.

Often the DR Secondary cluster is freshly initialized and unconfigured. As such, using its root token during 
this process of setting it up as a DR secondary cluster is a standard practice. All data in this cluster will 
be ERASED once is becomes a DR secondary, and any attempts to use it will be met with redirects to the DR
Primary cluster or blatant error messages.
EOH
  )"
  log_msg "$msg"
  VAULT_ADDR_secondary="$(env_var_or_prompt VAULT_ADDR_secondary)"
  VAULT_TOKEN_secondary="$(env_var_or_prompt VAULT_TOKEN_secondary)"
fi

if [ -z "${VAULT_SECONDARY_IDENTIFIER:-}" ]; then
  msg="$(
    cat <<'EOH'
When registering the DR secondary cluster with the DR primary, this is the identifier that will be used to
represent the connection. It is recommended to use the collective name of the DR Secondary Vault cluster,
often set as the `cluster_name` attribute in one of the Vault config files on the server nodes (i.e., in 
one of '/etc/vault.d/*.hcl').

Example: vault-chimp
EOH
  )"
  log_msg "$msg"
  VAULT_SECONDARY_IDENTIFIER="$(env_var_or_prompt VAULT_SECONDARY_IDENTIFIER)"
fi

if [ -z "${VAULT_CLUSTER_ADDR_primary:-}" ]; then
  msg="$(
    cat <<'EOH'
Please include the cluster address (e.g., 'https://vault.example.com:8201') for the DR Primary cluster, if routing replication traffic through a load balancer (recommended).

If you are okay with members of the DR secondary cluster directly communicating with members of the DR primary cluster, please leave this blank.
EOH
  )"
  log_msg "$msg"
  VAULT_CLUSTER_ADDR_primary="$(env_var_or_prompt VAULT_CLUSTER_ADDR_primary)"
fi

log_msg 'Preflight Check: Ensuring both clusters have expected levels of connectivity'

assert_is_listening "${VAULT_ADDR_primary}"
assert_is_listening "${VAULT_ADDR_secondary}"
if [ -n "${VAULT_CLUSTER_ADDR_primary:-}" ]; then
  assert_is_listening "${VAULT_CLUSTER_ADDR_primary}"
fi

log_msg 'Preflight Check: Ensuring both clusters are initialized and unsealed'

assert_is_initialized primary
assert_is_unsealed primary

assert_is_initialized secondary
assert_is_unsealed secondary

log_msg 'Preflight Check: Ensuring VAULT_TOKEN for each cluster is valid'

assert_valid_token primary
assert_valid_token secondary

log_msg 'Preflight Check: Ensuring each cluster is licensed for replication features'
assert_dr_replication_license primary
assert_dr_replication_license secondary

log_msg 'Preflight Check: Ensuring secondary cluster is not already connected and replicating to a primary cluster'
if ! assert_dr_feature_is_disabled secondary; then
  pause 'Would you like to correct this by disabling DR replication?'
  disable_dr_secondary_replication
  log_msg "Error has been mitigated. DR replication feature on ${VAULT_ADDR_secondary} has been disabled, putting it in a clean state."
fi
if ! check_dr_secondary_is_not_connected; then
  log_msg 'By reaching this point, the desired DR secondary is not yet configured to replicate. If you are certain'
  pause "Would you like to correct this by disabling replication to the DR secondary cluster named '${VAULT_SECONDARY_IDENTIFIER}'?"
  revoke_dr_secondary_connection
  log_msg "Error has been mitigated. Any connection named '${VAULT_SECONDARY_IDENTIFIER}' has been revoked, disabling replication from ${VAULT_ADDR_primary} to it."
fi

pause 'Preflight checks completed successfully.'

if check_is_dr_primary primary; then
  log_msg 'Detected the DR replication feature is enabled on the primary cluster'
  if ! check_dr_primary_replication_is_configured_correctly; then
    log_msg "DR replication appears to be misconfigured on ${VAULT_ADDR_primary}"
    msg="$(
      cat <<'EOH'

==============================
========== CAUTION! ==========
==============================

The DR replication feature must be disabled and then re-enabled to be
repaired. Impact of these actions are as follows:

1. Any currently connected DR secondary clusters will permanently
   disconnected from this Vault cluster, requiring replication to
   be setup once more.

2. Availability of the Vault API on the DR primary cluster (this one)
   may be briefly interrupted. This interruption is expected to take
   5 seconds or less.

No actions have been taken yet, so aborting this process now will
result in no impact to any Vault cluster. Do you consent?
EOH
    )"
    pause "$msg"
    disable_dr_primary_replication
    log_msg "DR replication has been (temporarily) disabled."
    pause "DR replication feature is about to be re-enabled, resulting in a brief interruption to the Vault API. Proceed?"
    enable_dr_primary_replication
    log_msg "DR replication feature has been repaired."
  else
    log_msg "DR replication appears to be configured correctly."
  fi
else
  log_msg "DR replication is not enabled on ${VAULT_ADDR_primary}"
  msg="$(
    cat <<'EOH'

==============================
========== CAUTION! ==========
==============================

The DR replication feature must be enabled before proceeding. Impact
of this action is as follows:

1. A brief outage of the Vault API will occur, expected to last no
   longer than 5 seconds

No actions have been taken yet, so aborting this process now will
result in no impact to any Vault cluster. Do you consent?
EOH
  )"
  pause "$msg"
  enable_dr_primary_replication
fi

enable_dr_secondary_replication

log_msg "Disaster Recovery replication connection has been established. Data is being fully replicated to the DR secondary and may take several minutes. To monitor progress, see the Vault Web UI at ${VAULT_ADDR_secondary}"
