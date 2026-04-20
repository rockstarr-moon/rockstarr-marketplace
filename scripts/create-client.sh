#!/usr/bin/env bash
# create-client.sh — provision a new Rockstarr AI client.
#
# Usage:
#   scripts/create-client.sh <client_id> "<Display Name>" <plugin1,plugin2,...>
#
# Example:
#   scripts/create-client.sh rockstarr-ai-pilot "Rockstarr AI — Pilot" rockstarr-infra
#
# Flags:
#   --no-push    Commit locally but do not push to either origin.

# shellcheck disable=SC1091
source "$(dirname "$0")/_lib.sh"

parse_global_flags "$@"
set -- "${GLOBAL_ARGS[@]:-}"

if [[ $# -lt 3 ]]; then
  cat >&2 <<EOF
Usage: $0 <client_id> "<Display Name>" <plugin1,plugin2,...> [--no-push]

  client_id      short slug, e.g. rockstarr-ai-pilot
  Display Name   human-readable, e.g. "Rockstarr AI — Pilot"
  plugins        comma-separated list of plugin names the client is entitled to

EOF
  exit 2
fi

CLIENT_ID="$1"
DISPLAY_NAME="$2"
PLUGINS_CSV="$3"

preflight

if jq -e --arg id "$CLIENT_ID" '.clients | to_entries[] | select(.value.client_id == $id)' "$CLIENTS_FILE" >/dev/null; then
  echo "ERROR: a client with client_id '$CLIENT_ID' already exists." >&2
  exit 1
fi

TOKEN="$(generate_token)"
SHORT="$(short_token "$TOKEN")"
CREATED_AT="$(now_iso)"

ALLOWED_JSON="$(echo "$PLUGINS_CSV" | jq -R 'split(",") | map(select(length > 0))')"

NEW_CLIENTS="$(jq \
  --arg token "$TOKEN" \
  --arg id    "$CLIENT_ID" \
  --arg name  "$DISPLAY_NAME" \
  --arg ts    "$CREATED_AT" \
  --argjson allowed "$ALLOWED_JSON" \
  '.clients[$token] = {
    client_id: $id,
    display_name: $name,
    status: "active",
    allowed_plugins: $allowed,
    version_pins: {},
    created_at: $ts,
    notes: ""
  }' "$CLIENTS_FILE")"
write_clients_file "$NEW_CLIENTS"

regenerate_client_manifest "$TOKEN"

# Detailed message goes to the PRIVATE registry; opaque message to the PUBLIC repo.
commit_registry "create-client: ${CLIENT_ID} (${DISPLAY_NAME})"
commit_public   "add manifest ${SHORT}"

cat <<EOF

Client created.

  client_id     : ${CLIENT_ID}
  display_name  : ${DISPLAY_NAME}
  status        : active
  token         : ${TOKEN}
  allowed       : ${PLUGINS_CSV}

Give this URL to the client (or paste it into their Cowork Settings -> Plugins
-> Add Marketplace):

  ${RAW_BASE}/clients/${TOKEN}/marketplace.json

Keep the token somewhere safe (password manager). It's the only handle for
pausing, churning, or pinning this client later.
EOF
