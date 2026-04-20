#!/usr/bin/env bash
# set-status.sh — flip a client between active / paused / churned.
#
# paused and churned both produce an empty plugins[] manifest, so the client's
# existing installs keep working but no upgrades flow. active restores the
# full plugin list from the registry.
#
# Usage:
#   scripts/set-status.sh <token> <active|paused|churned>
#
# Flags:
#   --no-push    Commit locally but do not push to either origin.

# shellcheck disable=SC1091
source "$(dirname "$0")/_lib.sh"

parse_global_flags "$@"
set -- "${GLOBAL_ARGS[@]:-}"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <token> <active|paused|churned> [--no-push]" >&2
  exit 2
fi

TOKEN="$1"
STATUS="$2"

case "$STATUS" in
  active|paused|churned) ;;
  *) echo "ERROR: status must be one of: active, paused, churned" >&2; exit 1 ;;
esac

preflight

CLIENT_JSON="$(read_client "$TOKEN")"
if [[ -z "$CLIENT_JSON" ]]; then
  echo "ERROR: no client with that token." >&2
  exit 1
fi

CLIENT_ID="$(echo "$CLIENT_JSON" | jq -r '.client_id')"
SHORT="$(short_token "$TOKEN")"

NEW_CLIENTS="$(jq \
  --arg token "$TOKEN" \
  --arg s     "$STATUS" \
  '.clients[$token].status = $s' "$CLIENTS_FILE")"
write_clients_file "$NEW_CLIENTS"

regenerate_client_manifest "$TOKEN"

commit_registry "set-status: ${CLIENT_ID} -> ${STATUS}"
commit_public   "update manifest ${SHORT}"

echo "Status for ${CLIENT_ID} is now: ${STATUS}"
