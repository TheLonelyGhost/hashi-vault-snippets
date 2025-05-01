#!/usr/bin/env bash
set -euo pipefail

declare -a _curl_flags
_curl_flags=(--fail --show-error --silent)

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
  local msg
  msg="Press [ENTER] to continue, [Ctrl-C] to abort"
  if [ -n "${1:-}" ]; then
    msg="$*\n${msg}"
  fi
  read -p "$msg" -s -r _
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
  local target method uri_path addr flags
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

  curl "${flags[@]}" "${addr}/v1/${uri_path}"
}
vault_api() {
  local target method uri_path addr flags
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

  curl "${flags[@]}" "${addr}/v1/${uri_path}"
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

check_valid_token() {
  vault_api "$1" GET /auth/token/lookup-self >/dev/null 2>&1
}
assert_valid_token() {
  if ! check_valid_token "$1"; then
    printf 'ERROR: Vault token for %s is invalid\n' "$(_target_var "$1" VAULT_ADDR)" >&2
    return 1
  fi
}

get_perf_mode() {
  vault_api "$1" GET /sys/replication/performance/status | jq -r '.data.mode'
}
check_is_perf_replication_disabled() {
  [ "$(get_perf_mode "$1")" == "disabled" ]
}
assert_perf_replication_feature_is_disabled() {
  local mode
  mode="$(get_perf_mode "$1")"

  if [ "$mode" != "disabled" ]; then
    printf 'ERROR: Performance replication for %s is "%s", not "disabled"\n' "$(_target_var "$1" VAULT_ADDR)" "$mode" >&2
    return 1
  fi
}
check_is_perf_primary() {
  [ "$(get_perf_mode "$1")" == "primary" ]
}
assert_perf_primary() {
  local mode
  mode="$(get_perf_mode "$1")"

  if [ "$mode" != "primary" ]; then
    printf 'ERROR: Performance replication for %s is "%s", not "primary"\n' "$(_target_var "$1" VAULT_ADDR)" "$mode" >&2
    return 1
  fi
}
check_is_perf_secondary() {
  [ "$(get_perf_mode "$1")" == "secondary" ]
}
assert_perf_secondary() {
  local mode
  mode="$(get_perf_mode "$1")"

  if [ "$mode" != "secondary" ]; then
    printf 'ERROR: Performance replication for %s is "%s", not "secondary"\n' "$(_target_var "$1" VAULT_ADDR)" "$mode" >&2
    return 1
  fi
}

check_perf_replication_license() {
  vault_api "$1" GET /sys/license/status | jq -e '.data.autoloaded.features[] | contains("Performance Replication")' >/dev/null
}
assert_perf_replication_license() {
  if ! check_perf_replication_license "$1"; then
    printf 'ERROR: The applied Vault Enterprise license for %s does not seem to include support for Performance Replication\n' "$(_target_var "$1" VAULT_ADDR)" >&2
    return 1
  fi
}

check_perf_primary_replication_is_configured_correctly() {
  local resp mode
  resp="$(vault_api primary GET /sys/replication/performance/status)"
  mode="$(jq -r '.data.mode' <<<"$resp")"

  if [ "$mode" != "primary" ]; then
    return 1
  fi

  if ! jq -e --arg addr "$VAULT_CLUSTER_ADDR_primary" '.data.primary_cluster_addr == $addr' <<<"$resp" >/dev/null 2>&1; then
    return 1
  fi
}

disable_perf_primary_replication() {
  vault_api primary POST /sys/replication/performance/primary/disable >/dev/null
}

enable_perf_primary_replication() {
  # NOTE: We may want to put a warning of temp outage in this location
  # too, but it seems redundant given it is already immediately prior
  # to executing this in all other code paths.
  vault_api primary POST /sys/replication/performance/primary/enable "$(jq --null-input --arg addr "$VAULT_CLUSTER_ADDR_primary" '{"primary_cluster_addr": $addr}')" >/dev/null
}

enable_perf_secondary_replication() {
  local resp pubkey
  pause "Retrieving public keys from ${VAULT_ADDR_secondary}"
  resp="$(vault_api secondary POST /sys/replication/performance/secondary/generate-public-key)"
  pubkey="$(jq -r '.data.secondary_public_key' <<<"$resp")"
  pause "Retrieving invitation to join ${VAULT_ADDR_primary} as a Performance secondary cluster. Note that once the invitation is generated, it expires after 30 minutes."
  resp="$(vault_api primary POST /sys/replication/performance/primary/secondary-token "$(jq --null-input --arg pubkey "$pubkey" --arg ident "$VAULT_SECONDARY_IDENTIFIER" '{"secondary_public_key": $pubkey, "id": $ident, "ttl": "30m"}')")"
  JOIN_TOKEN="$(jq -r '.data.token' <<<"$resp")"

  pause "Accept the invitation to join?"
  vault_api secondary POST /sys/replication/performance/secondary/enable "$(jq --null-input --arg token "$JOIN_TOKEN" '{"token": $token}')"
  log_msg "Invitation has been accepted. ${VAULT_ADDR_secondary} is now replicating data from ${VAULT_ADDR_primary}"
  unset JOIN_TOKEN
}

disable_perf_secondary_replication() {
  cat >&2 <<'EOH'
ERROR! This functionality is too dangerous to automate!

Disabling a Performance replication secondary results in that secondary cluster's data being wiped. Any
local mounts will irrecoverably be lost. To ensure you mean to do this, scale all instances in the
performance replica secondary cluster to zero, delete all stored data in those nodes (i.e., delete any
PersistentVolumeClaim resources if deployed on Kubernetes), and re-initialize (and unseal) the cluster.

Once completed, you may attempt to run this script again.
EOH
  exit 1
}

revoke_perf_secondary_connection() {
  vault_api primary POST /sys/replication/performance/primary/revoke-secondary "$(jq --arg ident "$VAULT_SECONDARY_IDENTIFIER" --null-input '{ "id": $ident }')" >/dev/null
}

check_perf_secondary_is_connected() {
  local resp mode
  resp="$(vault_api primary GET /sys/replication/performance/status)"
  mode="$(jq -r '.data.mode' <<<"$resp")"

  if [ "$mode" != "primary" ]; then
    # This cluster is either misconfigured as a secondary, or has Performance replication feature
    # disabled. Either way, the desired secondary is not currently configured as a secondary on
    # this cluster.
    return 1
  fi
  if ! jq --arg ident "$VAULT_SECONDARY_IDENTIFIER" -e '.data.known_secondaries[] | contains($ident)' <<<"$resp" >/dev/null; then
    return 1
  fi
}

cleanup() {
  if [ -n "${JOIN_TOKEN:-}" ]; then
    log_msg "Cleaning up previous, incomplete attempt to join to the cluster"
    revoke_perf_secondary_connection
  fi
}
trap 'cleanup' EXIT

cat <<EOF
======================================================
|                                                    |
|       Runbook: Setup Performance Replication       |
|                                                    |
======================================================

CAVEAT: Both the primary and secondary clusters must be both
    initialized and unsealed.
EOF
assert_has_command jq
assert_has_command curl
assert_has_command nc netcat
assert_has_command python3 # Only need what's in the standard library
pause ""

# shellcheck disable=SC2034
VAULT_ADDR_primary="$(env_var_or_prompt VAULT_ADDR_primary)"
# shellcheck disable=SC2034
VAULT_TOKEN_primary="$(env_var_or_prompt VAULT_TOKEN_primary)"
# shellcheck disable=SC2034
VAULT_ADDR_secondary="$(env_var_or_prompt VAULT_ADDR_secondary)"
# shellcheck disable=SC2034
VAULT_TOKEN_secondary="$(env_var_or_prompt VAULT_TOKEN_secondary)"
# shellcheck disable=SC2034
VAULT_SECONDARY_IDENTIFIER="$(env_var_or_prompt VAULT_SECONDARY_IDENTIFIER)"

# NOTE: In Performance replication, we want a DNS entry that would always be
# assigned to the DR primary cluster, even during failover. Since we cannot
# intuit that given what we already know, prompt the user for it.
VAULT_CLUSTER_ADDR_primary="$(env_var_or_prompt VAULT_CLUSTER_ADDR_primary 'The Vault Cluster Address, using the vanity DNS name for the Performance Primary cluster, in the format "https://vault.example.com:8201"')"

log_msg 'Preflight Check: Ensuring both clusters have expected levels of connectivity'

assert_is_listening "${VAULT_ADDR_primary}"
assert_is_listening "${VAULT_ADDR_secondary}"
assert_is_listening "${VAULT_CLUSTER_ADDR_primary}"

log_msg 'Preflight Check: Ensuring both clusters are initialized and unsealed'

assert_is_initialized primary
assert_is_unsealed primary

assert_is_initialized secondary
assert_is_unsealed secondary

log_msg 'Preflight Check: Ensuring VAULT_TOKEN for each cluster is valid'

assert_valid_token primary
assert_valid_token secondary

log_msg 'Preflight Check: Ensuring each cluster is licensed for replication features'
assert_perf_replication_license primary
assert_perf_replication_license secondary

log_msg 'Preflight Check: Ensuring secondary cluster is not already connected and replicating to a primary cluster'
if ! assert_perf_replication_feature_is_disabled secondary; then
  pause 'Would you like to correct this by disabling Performance replication?'
  disable_perf_secondary_replication
  # log_msg "Error has been mitigated. Performance replication feature on ${VAULT_ADDR_secondary} has been disabled, putting it in a clean state."
fi
if check_perf_secondary_is_connected; then
  log_msg 'By reaching this point, the desired Performance secondary is not yet configured to replicate. If you are certain'
  pause "Would you like to correct this by disabling replication to the Performance secondary cluster named '${VAULT_SECONDARY_IDENTIFIER}'?"
  revoke_perf_secondary_connection
  log_msg "Error has been mitigated. Any connection named '${VAULT_SECONDARY_IDENTIFIER}' has been revoked, disabling replication from ${VAULT_ADDR_primary} to it."
fi

pause 'Preflight checks completed successfully.'

if check_is_perf_primary primary; then
  log_msg 'Detected the Performance replication feature is enabled on the primary cluster'
  if ! check_perf_primary_replication_is_configured_correctly; then
    log_msg "Performance replication appears to be misconfigured on ${VAULT_ADDR_primary}"
    msg="$(
      cat <<'EOH'

==============================
========== CAUTION! ==========
==============================

The Performance replication feature must be disabled and then re-enabled to be
repaired. Impact of these actions are as follows:

1. Any currently connected Performance secondary clusters will permanently
   disconnected from this Vault cluster, requiring replication to be setup
   once more.

2. Availability of the Vault API on the Performance primary cluster (this 
   one) may be briefly interrupted. This interruption is expected to take
   5 seconds or less.

No actions have been taken yet, so aborting this process now will
result in no impact to any Vault cluster. Do you consent?
EOH
    )"
    pause "$msg"
    disable_perf_primary_replication
    log_msg "Performance replication has been (temporarily) disabled."
    pause "Performance replication feature is about to be re-enabled, resulting in a brief interruption to the Vault API. Proceed?"
    enable_perf_primary_replication
    log_msg "Performance replication feature has been repaired."
  else
    log_msg "Performance replication appears to be configured correctly."
  fi
else
  log_msg "Performance replication is not enabled on ${VAULT_ADDR_primary}"
  msg="$(
    cat <<'EOH'

==============================
========== CAUTION! ==========
==============================

The Performance replication feature must be enabled before proceeding. Impact
of this action is as follows:

1. A brief outage of the Vault API will occur, expected to last no longer
   than 5 seconds

No actions have been taken yet, so aborting this process now will
result in no impact to any Vault cluster. Do you consent?
EOH
  )"
  pause "$msg"
  enable_perf_primary_replication
fi

enable_perf_secondary_replication

log_msg "Performance replication connection has been established. Data is being fully replicated to the Performance secondary and may take several minutes. To monitor progress, see the Vault Web UI at ${VAULT_ADDR_secondary}"
