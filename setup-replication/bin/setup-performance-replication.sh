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
  vault_api "$1" GET /sys/license/status | jq -e '[.data.autoloaded.features[] | select(. == "Performance Replication")] | any' >/dev/null
}
assert_perf_replication_license() {
  if ! check_perf_replication_license "$1"; then
    printf 'ERROR: The applied Vault Enterprise license for %s does not seem to include support for Performance Replication\n' "$(_target_var "$1" VAULT_ADDR)" >&2
    return 1
  fi
}

check_perf_primary_replication_configures_clusteraddr_correctly() {
  local resp mode
  resp="$(vault_api primary GET /sys/replication/performance/status)"

  if [ -n "${VAULT_CLUSTER_ADDR_primary:-}" ]; then
    if ! jq -e --arg addr "$VAULT_CLUSTER_ADDR_primary" '.data.primary_cluster_addr == $addr' <<<"$resp" >/dev/null 2>&1; then
      return 1
    fi
  else
    if jq -e '.data.primary_cluster_addr' <<<"$resp" >/dev/null 2>&1; then
      # We don't have a VAULT_CLUSTER_ADDR that we want to set (i.e., the load balancer) so defer to the local node info, which is injected by default when not set
      return 1
    fi
  fi
}

disable_perf_primary_replication() {
  vault_api primary POST /sys/replication/performance/primary/disable >/dev/null
}

enable_perf_primary_replication() {
  # NOTE: We may want to put a warning of temp outage in this location
  # too, but it seems redundant given it is already immediately prior
  # to executing this in all other code paths.
  local payload
  payload="{}"
  if [ -n "${VAULT_CLUSTER_ADDR_primary:-}" ]; then
    payload="$(jq --null-input --arg addr "$VAULT_CLUSTER_ADDR_primary" '{"primary_cluster_addr": $addr}')"
  fi
  vault_api primary POST /sys/replication/performance/primary/enable "$payload" >/dev/null
}

update_perf_secondary_replication() {
  local resp pubkey
  pause "Retrieving public keys from ${VAULT_ADDR_secondary}"
  resp="$(vault_api secondary POST /sys/replication/performance/secondary/generate-public-key)"
  pubkey="$(jq -r '.data.secondary_public_key' <<<"$resp")"
  pause "Retrieving invitation to join ${VAULT_ADDR_primary} as a Performance secondary cluster. Note that once the invitation is generated, it expires after 30 minutes."
  resp="$(vault_api primary POST /sys/replication/performance/primary/secondary-token "$(jq --null-input --arg pubkey "$pubkey" --arg ident "$VAULT_SECONDARY_IDENTIFIER" '{"secondary_public_key": $pubkey, "id": $ident, "ttl": "30m"}')")"
  JOIN_TOKEN="$(jq -r '.data.token' <<<"$resp")"

  pause "Accept the invitation to join?"
  vault_api secondary POST /sys/replication/performance/secondary/update-primary "$(jq --null-input --arg token "$JOIN_TOKEN" '{"token": $token}')"
  log_msg "Invitation has been accepted. ${VAULT_ADDR_secondary} is now replicating data from ${VAULT_ADDR_primary}"
  unset JOIN_TOKEN
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

revoke_perf_secondary_connection() {
  vault_api primary POST /sys/replication/performance/primary/revoke-secondary "$(jq --arg ident "$VAULT_SECONDARY_IDENTIFIER" --null-input '{ "id": $ident }')" >/dev/null
}

assert_perf_secondary_configuration_is_correct() {
  local sec_resp prim_resp secondary_id conn_state
  sec_resp="$(vault_api secondary GET /sys/replication/performance/status)"
  prim_resp="$(vault_api primary GET /sys/replication/performance/status)"
  secondary_id="$(jq -r '.data.secondary_id' <<<"$sec_resp")"

  # TODO: Check if secondary_id is one of the known ones in primary's list
  # TODO: Check if connection state is healthy

  if [ -n "${VAULT_CLUSTER_ADDR_primary:-}" ] && ! jq -e --arg addr "${VAULT_CLUSTER_ADDR_primary:-}" '.data.primary_cluster_addr == $addr' <<<"$sec_resp" >/dev/null 2>&1; then
    printf 'ERROR: Performance secondary has a misconfigured address for its performance primary cluster and needs fixing\n' >&2
    return 1
  fi

  if ! jq -e --arg secondary_id "$secondary_id" '[.data.known_secondaries[] | select(. == $secondary_id)] | any' <<<"$prim_resp" >/dev/null 2>&1; then
    printf 'ERROR: Performance secondary is not one of the known secondaries for this Performance primary\n'
    return 1
  fi

  conn_state="$(jq -e --arg secondary_id "$secondary_id" '.data.secondaries[] | select(.node_id == $secondary_id) | .connection_status' <<<"$prim_resp")"
  case "$conn_state" in
  connected) ;;
  *)
    printf 'ERROR: Connection state in the Performance secondary cluster is "%s" instead of the expected value of "ready"\n' "$conn_state" >&2
    return 1
    ;;
  esac
}

check_perf_secondary_is_connected() {
  local resp mode
  resp="$(vault_api primary GET /sys/replication/performance/status)"

  if ! jq --arg ident "$VAULT_SECONDARY_IDENTIFIER" -e '[.data.known_secondaries[] | select(. == $ident)] | any' <<<"$resp" >/dev/null; then
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

CAVEAT: Both the primary and secondary clusters must be both initialized and unsealed.
EOF
assert_has_command jq
assert_has_command curl
assert_has_command nc netcat
assert_has_command python3 # Only need what's in the standard library
pause

if [ -z "${VAULT_ADDR_primary:-}" ] || [ -z "${VAULT_TOKEN_primary:-}" ]; then
  cat >&2 <<'EOH'
This section will prompt you for the Vault API information of the Performance PRIMARY cluster.
EOH
  VAULT_ADDR_primary="$(env_var_or_prompt VAULT_ADDR_primary)"
  VAULT_TOKEN_primary="$(env_var_or_prompt VAULT_TOKEN_primary)"
fi
if [ -z "${VAULT_ADDR_secondary:-}" ] || [ -z "${VAULT_TOKEN_secondary:-}" ]; then
  cat >&2 <<'EOH'
This section will prompt you for the Vault API information of the Performance SECONDARY cluster.
EOH
  VAULT_ADDR_secondary="$(env_var_or_prompt VAULT_ADDR_secondary)"
  VAULT_TOKEN_secondary="$(env_var_or_prompt VAULT_TOKEN_secondary)"
fi
if [ -z "${VAULT_SECONDARY_IDENTIFIER:-}" ]; then
  cat >&2 <<'EOH'
When registering the Performance secondary cluster with the Performance primary, this is the identifier
that will be used to represent the connection. Typically this represents a geographical region or some
indicator of a datacenter along which performance replica clusters are split.

Example: vault-emea
EOH
  VAULT_SECONDARY_IDENTIFIER="$(env_var_or_prompt VAULT_SECONDARY_IDENTIFIER)"
fi

# NOTE: In Performance replication, we want a DNS entry that would always be
# assigned to the DR primary cluster, even during failover. Since we cannot
# intuit that given what we already know, prompt the user for it.
if [ -z "${VAULT_CLUSTER_ADDR_primary:-}" ]; then
  cat >&2 <<'EOH'
Please include the cluster address (e.g., 'https://vault.example.com:8201') for the Performance primary
cluster, if routing replication traffic through a load balancer (recommended).

If you are okay with members of the Performance secondary cluster directly communicating with members
of the Performance primary cluster, please leave this blank. (hint: this may break Performance replication
when entering some Disaster Recovery scenarios)
EOH
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
assert_perf_replication_license primary
assert_perf_replication_license secondary

log_msg 'Preflight Check: Ensuring primary cluster is in a compatible state for performance replication'

primary_perf_mode="$(get_perf_mode primary)"
case "$primary_perf_mode" in
primary | disable) ;;
secondary)
  cat >&2 <<MSG
ERROR: ${VAULT_ADDR_primary} is configured to be a Performance secondary cluster.

This is an incompatible state with becoming a Performance _PRIMARY_ cluster. If you are certain this Vault cluster
must be repurposed as a Performance PRIMARY from its current state, please acknowledge the following warnings.

==============================
========== CAUTION! ==========
==============================
MSG

  printf '\n\n' >&2
  cat >&2 <<EOH
WARNING: This action is irreversible without ERASING all data in this cluster.
EOH
  pause
  printf '\n\n' >&2
  cat >&2 <<EOH
WARNING: Any secrets engines, auth mounts, or anything else configured to be a local-only mount
are not replicated to a Performance secondary cluster.

(If there is a Disaster Recovery secondary cluster that is connected, these local-only mounts will
be replicated to that DR secondary cluster.)
EOH
  pause
  printf '\n\n' >&2
  cat >&2 <<EOH
WARNING: Any attempts to disable ${VAULT_ADDR_primary} as a Performance PRIMARY and re-enable it
as a Performance SECONDARY will ERASE all data in the cluster.
EOH
  pause
  printf '\n\n' >&2

  cat >&2 <<EOH
WARNING: Changing the role of ${VAULT_ADDR_primary} to become a Performance PRIMARY will require
a brief outage of its Vault API while it reconfigures itself.
EOH
  pause
  printf '\n\n' >&2

  pause 'Do you accept all of these conditions and still want to proceed?'

  # This is an extra safety mechanism in case someone accidentally switches the Perf primary and secondary cluster
  # info, then spams the <Enter> key.
  cat >&2 <<'MSG'
Please run `./bin/disable-perf-secondary-replication.sh` and re-run this script.
MSG
  exit 0
  ;;
*) ;;
esac

log_msg 'Preflight Check: Ensuring secondary cluster is in a compatible state'
secondary_perf_mode="$(get_perf_mode secondary)"
case "$secondary_perf_mode" in
secondary | disabled)
  # NOTE: These are fine to skip past since we can adapt to either of these situations.
  ;;
primary)
  cat >&2 <<EOH
ERROR: ${VAULT_ADDR_secondary} is configured as a Performance primary cluster.

This is an incompatible state with becoming a Performance _SECONDARY_ cluster. If you are certain this Vault cluster
must be repurposed as a Performance SECONDARY from its current state, please acknowledge the following warnings.

==============================
========== CAUTION! ==========
==============================
EOH
  printf '\n\n' >&2
  cat >&2 <<EOH
WARNING: The act of enabling Performance SECONDARY replication will ERASE all data in that Performance secondary
cluster. ~~> ALL <~~ data within the SECONDARY cluster will be overwritten with data from the Performance PRIMARY.
EOH
  pause
  printf '\n\n' >&2
  cat >&2 <<EOH
WARNING: Changing the role of ${VAULT_ADDR_secondary} to become a Performance SECONDARY will require
a brief outage of its Vault API while it reconfigures itself.
EOH
  pause
  printf '\n\n' >&2

  pause 'Do you accept all of these conditions and still want to proceed?'

  # This is an extra safety mechanism in case someone accidentally switches the Perf primary and secondary cluster
  # info, then spams the <Enter> key.
  cat >&2 <<'MSG'
Please run `./bin/disable-perf-primary-replication.sh` and re-run this script.
MSG
  exit 0
  ;;
*)
  cat >&2 <<EOH
ERROR: Unknown performance replication mode '${secondary_perf_mode}'

This is a bug in the replication setup script.
EOH
  exit 1
  ;;
esac
# if check_perf_secondary_is_connected; then
#   log_msg 'By reaching this point, the desired Performance secondary is not yet configured to replicate.'
#   pause "Would you like to correct this by disabling replication to the Performance secondary cluster named '${VAULT_SECONDARY_IDENTIFIER}'?"
#   revoke_perf_secondary_connection
#   log_msg "Error has been mitigated. Any connection named '${VAULT_SECONDARY_IDENTIFIER}' has been revoked, disabling replication from ${VAULT_ADDR_primary} to it."
# fi

pause 'Preflight checks completed successfully.'

if ! check_perf_primary_replication_configures_clusteraddr_correctly; then
  if [ "$primary_perf_mode" != "disabled" ]; then
    cat >&2 <<MSG
WARNING: Performance replication appears to be misconfigured for ${VAULT_ADDR_primary}

==============================
========== CAUTION! ==========
==============================

The Performance replication feature must be disabled and then re-enabled to be repaired. Impact
of these actions are as follows:

1. Any currently connected Performance secondary clusters will permanently
   disconnected from this Vault cluster, requiring replication to be setup
   once more.

2. Availability of the Vault API on the Performance primary cluster (this 
   one) may be briefly interrupted. This interruption is expected to take
   5 seconds or less.

No actions have been taken yet, so aborting this process now will result in no impact to any
Vault cluster. Do you consent?
MSG
    pause
    disable_perf_primary_replication
    log_msg "Performance replication has been (temporarily) disabled."
    pause "Performance replication feature is about to be re-enabled, resulting in a brief interruption to the Vault API. Proceed?"
    enable_perf_primary_replication
  else
    cat >&2 <<MSG
WARNING: Performance replication is not enabled on ${VAULT_ADDR_primary}

==============================
========== CAUTION! ==========
==============================

The Performance replication feature must be enabled before proceeding. Impact of this action
is as follows:

1. A brief outage of the Vault API will occur, expected to last no longer
   than 5 seconds

No actions have been taken yet, so aborting this process now will result in no impact to any
Vault cluster. Do you consent?
MSG
    pause
    enable_perf_primary_replication
  fi
fi

if [ "$secondary_perf_mode" == "secondary" ]; then
  if ! assert_perf_secondary_configuration_is_correct; then
    update_perf_secondary_replication
  else
    log_msg "Nothing to do! Everything is configured correctly."
  fi
else
  enable_perf_secondary_replication
fi

log_msg "Performance replication connection has been established. Data is being fully replicated to the Performance secondary and may take several minutes. To monitor progress, see the Vault Web UI at ${VAULT_ADDR_secondary}"
