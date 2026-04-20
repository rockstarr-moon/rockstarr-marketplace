#!/usr/bin/env bash
# _lib.sh — shared helpers for the four admin scripts.
# Not intended to be executed directly. Sourced via:
#   source "$(dirname "$0")/_lib.sh"
#
# Two-repo model:
#   PUBLIC_REPO  — this checkout. Contains /clients/<token>/marketplace.json
#                  (tokenized, no names). Commits here use opaque messages.
#   REGISTRY_REPO — a PRIVATE checkout at $REGISTRY_PATH. Contains
#                  clients.json and plugins.json (names, state).

set -euo pipefail

# ---------- Path anchoring ------------------------------------------------

PUBLIC_REPO="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$PUBLIC_REPO" ]]; then
  echo "ERROR: must be run from inside the rockstarr-marketplace git repo." >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

if [[ ! -d "$REGISTRY_PATH" ]]; then
  cat >&2 <<EOF
ERROR: registry checkout not found at:
  $REGISTRY_PATH

Expected layout (siblings on disk):
  parent/
    rockstarr-marketplace/            (public, this repo)
    rockstarr-marketplace-registry/   (private, contains clients.json and plugins.json)

Clone the private registry repo as a sibling of this one, or set REGISTRY_PATH
to its actual location before running the script.
EOF
  exit 1
fi

CLIENTS_FILE="${REGISTRY_PATH}/clients.json"
PLUGINS_FILE="${REGISTRY_PATH}/plugins.json"
CLIENTS_DIR="${PUBLIC_REPO}/clients"

for f in "$CLIENTS_FILE" "$PLUGINS_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: missing registry file: $f" >&2
    exit 1
  fi
done

# ---------- Global flags --------------------------------------------------

: "${NO_PUSH:=0}"

parse_global_flags() {
  GLOBAL_ARGS=()
  while (( "$#" )); do
    case "$1" in
      --no-push) NO_PUSH=1 ;;
      *) GLOBAL_ARGS+=("$1") ;;
    esac
    shift
  done
}

# ---------- Preflight -----------------------------------------------------

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command '$cmd' not found. Install it and re-run." >&2
    exit 1
  fi
}

preflight() {
  require_cmd jq
  require_cmd gh
  require_cmd git
  require_cmd openssl

  if ! gh auth status >/dev/null 2>&1; then
    echo "ERROR: gh is not authenticated. Run 'gh auth login' first." >&2
    exit 1
  fi

  # Both checkouts must have clean working trees.
  for repo in "$PUBLIC_REPO" "$REGISTRY_PATH"; do
    if ! (cd "$repo" && git diff --quiet && git diff --cached --quiet); then
      echo "ERROR: working tree is dirty at: $repo" >&2
      echo "Commit or stash local changes first." >&2
      exit 1
    fi
  done
}

# ---------- Tokens and IDs ------------------------------------------------

generate_token() {
  openssl rand -hex 16
}

# First 8 chars — used in public-repo commit messages as a debuggable but
# opaque handle. Collisions are vanishingly unlikely at our client count.
short_token() {
  local token="$1"
  echo "${token:0:8}"
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ---------- Registry IO ---------------------------------------------------

read_client() {
  local token="$1"
  jq --arg t "$token" '.clients[$t] // empty' "$CLIENTS_FILE"
}

read_plugin() {
  local name="$1"
  jq --arg n "$name" '.plugins[$n] // empty' "$PLUGINS_FILE"
}

write_clients_file() {
  local new_json="$1"
  local tmp
  tmp="$(mktemp)"
  echo "$new_json" | jq '.' > "$tmp"
  mv "$tmp" "$CLIENTS_FILE"
}

write_plugins_file() {
  local new_json="$1"
  local tmp
  tmp="$(mktemp)"
  echo "$new_json" | jq '.' > "$tmp"
  mv "$tmp" "$PLUGINS_FILE"
}

# ---------- Manifest generation ------------------------------------------

manifest_url() {
  local plugin_name="$1"
  local version="$2"
  local plugin_json
  plugin_json="$(read_plugin "$plugin_name")"
  if [[ -z "$plugin_json" ]]; then
    echo "ERROR: plugin '$plugin_name' is not registered. Publish it first." >&2
    return 1
  fi
  local prefix filename
  prefix="$(echo "$plugin_json" | jq -r '.release_tag_prefix')"
  filename="$(echo "$plugin_json" | jq -r '.artifact_filename')"
  echo "${RELEASE_BASE}/${prefix}${version}/${filename}"
}

effective_version() {
  local token="$1"
  local plugin_name="$2"
  local client_json plugin_json pinned current
  client_json="$(read_client "$token")"
  plugin_json="$(read_plugin "$plugin_name")"
  if [[ -z "$plugin_json" ]]; then
    return 0
  fi
  pinned="$(echo "$client_json" | jq -r --arg n "$plugin_name" '.version_pins[$n] // empty')"
  if [[ -n "$pinned" ]]; then
    echo "$pinned"
    return 0
  fi
  current="$(echo "$plugin_json" | jq -r '.current_version')"
  echo "$current"
}

regenerate_client_manifest() {
  local token="$1"
  local client_json
  client_json="$(read_client "$token")"
  if [[ -z "$client_json" ]]; then
    echo "ERROR: no client with token $token" >&2
    return 1
  fi

  local status
  status="$(echo "$client_json" | jq -r '.status')"

  local dest_dir="${CLIENTS_DIR}/${token}"
  mkdir -p "$dest_dir"
  local dest="${dest_dir}/marketplace.json"

  if [[ "$status" == "paused" || "$status" == "churned" ]]; then
    jq -n \
      --arg name "$MARKETPLACE_DISPLAY_NAME" \
      --arg owner "$OWNER_DISPLAY_NAME" \
      '{name: $name, owner: {name: $owner}, plugins: []}' > "$dest"
    return 0
  fi

  local plugins_array="[]"
  local allowed
  allowed="$(echo "$client_json" | jq -r '.allowed_plugins[]?')"
  while IFS= read -r plugin_name; do
    [[ -z "$plugin_name" ]] && continue
    local version
    version="$(effective_version "$token" "$plugin_name")"
    if [[ -z "$version" ]]; then
      echo "WARN: client ${token:0:8} is allowed '$plugin_name' but it's not published yet; skipping." >&2
      continue
    fi
    local url desc
    url="$(manifest_url "$plugin_name" "$version")"
    desc="$(read_plugin "$plugin_name" | jq -r '.description')"
    plugins_array="$(echo "$plugins_array" | jq \
      --arg name "$plugin_name" \
      --arg desc "$desc" \
      --arg ver  "$version" \
      --arg url  "$url" \
      '. + [{
        name: $name,
        description: $desc,
        version: $ver,
        source: { source: "url", url: $url }
      }]')"
  done <<< "$allowed"

  jq -n \
    --arg name "$MARKETPLACE_DISPLAY_NAME" \
    --arg owner "$OWNER_DISPLAY_NAME" \
    --argjson plugins "$plugins_array" \
    '{name: $name, owner: {name: $owner}, plugins: $plugins}' > "$dest"
}

regenerate_all_manifests() {
  local tokens
  tokens="$(jq -r '.clients | keys[]' "$CLIENTS_FILE")"
  while IFS= read -r token; do
    [[ -z "$token" ]] && continue
    regenerate_client_manifest "$token"
  done <<< "$tokens"
}

# ---------- Git commit helpers -------------------------------------------

# Commit staged changes in a specific repo path and push if NO_PUSH is unset.
_commit_in() {
  local repo_path="$1"
  local message="$2"
  (
    cd "$repo_path"
    git add -A
    if git diff --cached --quiet; then
      return 0  # nothing to commit here
    fi
    git commit -m "$message"
    if [[ "$NO_PUSH" != "1" ]]; then
      git push
    fi
  )
}

# The registry repo is private — messages here can be detailed.
commit_registry() {
  local message="$1"
  _commit_in "$REGISTRY_PATH" "$message"
}

# The public repo is public — messages here must not leak names or state.
# Callers should pass opaque messages built from short_token().
commit_public() {
  local message="$1"
  _commit_in "$PUBLIC_REPO" "$message"
}
