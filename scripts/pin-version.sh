#!/usr/bin/env bash
# pin-version.sh — pin (or unpin) a client to a specific plugin version.
#
# Usage:
#   scripts/pin-version.sh <token> <plugin> <version|unpin>
#
# Examples:
#   scripts/pin-version.sh a1b2c3... rockstarr-infra 0.4.11
#   scripts/pin-version.sh a1b2c3... rockstarr-infra unpin
#
# Flags:
#   --no-push    Commit locally but do not push to either origin.

# shellcheck disable=SC1091
source "$(dirname "$0")/_lib.sh"

parse_global_flags "$@"
set -- "${GLOBAL_ARGS[@]:-}"

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <token> <plugin> <version|unpin> [--no-push]" >&2
  exit 2
fi

TOKEN="$1"
PLUGIN="$2"
TARGET="$3"

preflight

CLIENT_JSON="$(read_client "$TOKEN")"
if [[ -z "$CLIENT_JSON" ]]; then
  echo "ERROR: no client with that token." >&2
  exit 1
fi
CLIENT_ID="$(echo "$CLIENT_JSON" | jq -r '.client_id')"
SHORT="$(short_token "$TOKEN")"

if [[ "$TARGET" == "unpin" ]]; then
  NEW_CLIENTS="$(jq \
    --arg token "$TOKEN" \
    --arg p     "$PLUGIN" \
    'del(.clients[$token].version_pins[$p])' "$CLIENTS_FILE")"
  REGISTRY_MSG="pin: ${CLIENT_ID} ${PLUGIN} -> unpinned"
else
  PLUGIN_JSON="$(read_plugin "$PLUGIN")"
  if [[ -z "$PLUGIN_JSON" ]]; then
    echo "ERROR: plugin '$PLUGIN' is not registered. Publish it first." >&2
    exit 1
  fi
  if ! echo "$PLUGIN_JSON" | jq -e --arg v "$TARGET" '.versions | index($v)' >/dev/null; then
    echo "ERROR: version '$TARGET' not found for '$PLUGIN'. Known versions:" >&2
    echo "$PLUGIN_JSON" | jq -r '.versions[]' >&2
    exit 1
  fi
  NEW_CLIENTS="$(jq \
    --arg token "$TOKEN" \
    --arg p     "$PLUGIN" \
    --arg v     "$TARGET" \
    '.clients[$token].version_pins[$p] = $v' "$CLIENTS_FILE")"
  REGISTRY_MSG="pin: ${CLIENT_ID} ${PLUGIN}=${TARGET}"
fi

write_clients_file "$NEW_CLIENTS"
regenerate_client_manifest "$TOKEN"

commit_registry "$REGISTRY_MSG"
commit_public   "update manifest ${SHORT}"

if [[ "$TARGET" == "unpin" ]]; then
  echo "Unpinned ${PLUGIN} for ${CLIENT_ID}; now tracks current_version."
else
  echo "Pinned ${PLUGIN} to ${TARGET} for ${CLIENT_ID}."
fi
