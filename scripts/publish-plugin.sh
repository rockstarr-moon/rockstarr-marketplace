#!/usr/bin/env bash
# publish-plugin.sh — cut a new plugin release and bump every active client.
#
# Three steps in order:
#   1. `gh release create` in rockstarr-plugins, attaching the .plugin file.
#   2. Updates plugins.json in the PRIVATE registry repo.
#   3. Regenerates every client's manifest in the PUBLIC repo. Pinned clients
#      stay put; everyone else moves to the new version.
#
# Usage:
#   scripts/publish-plugin.sh <name> <version> <path/to/file.plugin> "<description>"
#
# Flags:
#   --no-push    Commit locally but do not push. (The GitHub release is still
#                created — gh is out-of-band.)

# shellcheck disable=SC1091
source "$(dirname "$0")/_lib.sh"

parse_global_flags "$@"
set -- "${GLOBAL_ARGS[@]:-}"

if [[ $# -lt 4 ]]; then
  cat >&2 <<EOF
Usage: $0 <name> <version> <path/to/file.plugin> "<description>" [--no-push]
EOF
  exit 2
fi

PLUGIN_NAME="$1"
VERSION="$2"
ARTIFACT_PATH="$3"
DESCRIPTION="$4"

preflight

if [[ ! -f "$ARTIFACT_PATH" ]]; then
  echo "ERROR: artifact not found at '$ARTIFACT_PATH'" >&2
  exit 1
fi

EXISTING_PLUGIN="$(read_plugin "$PLUGIN_NAME")"
if [[ -z "$EXISTING_PLUGIN" ]]; then
  TAG_PREFIX="${PLUGIN_NAME}-v"
  ARTIFACT_FILENAME="${PLUGIN_NAME}.plugin"
  NEW_PLUGINS="$(jq \
    --arg name "$PLUGIN_NAME" \
    --arg desc "$DESCRIPTION" \
    --arg ver  "$VERSION" \
    --arg repo "${OWNER}/${PLUGINS_REPO}" \
    --arg tag  "$TAG_PREFIX" \
    --arg file "$ARTIFACT_FILENAME" \
    '.plugins[$name] = {
      description: $desc,
      current_version: $ver,
      versions: [$ver],
      release_repo: $repo,
      release_tag_prefix: $tag,
      artifact_filename: $file
    }' "$PLUGINS_FILE")"
else
  if echo "$EXISTING_PLUGIN" | jq -e --arg v "$VERSION" '.versions | index($v)' >/dev/null; then
    echo "ERROR: version '$VERSION' is already registered for $PLUGIN_NAME." >&2
    exit 1
  fi
  NEW_PLUGINS="$(jq \
    --arg name "$PLUGIN_NAME" \
    --arg desc "$DESCRIPTION" \
    --arg ver  "$VERSION" \
    '.plugins[$name].description = $desc
     | .plugins[$name].current_version = $ver
     | .plugins[$name].versions += [$ver]' "$PLUGINS_FILE")"
fi

TAG_PREFIX="$(echo "$NEW_PLUGINS" | jq -r --arg n "$PLUGIN_NAME" '.plugins[$n].release_tag_prefix')"
ARTIFACT_FILENAME="$(echo "$NEW_PLUGINS" | jq -r --arg n "$PLUGIN_NAME" '.plugins[$n].artifact_filename')"
TAG_NAME="${TAG_PREFIX}${VERSION}"

TMP_ARTIFACT="$(mktemp -d)/${ARTIFACT_FILENAME}"
cp "$ARTIFACT_PATH" "$TMP_ARTIFACT"

echo "Creating release $TAG_NAME in ${OWNER}/${PLUGINS_REPO}..."
gh release create "$TAG_NAME" "$TMP_ARTIFACT" \
  --repo "${OWNER}/${PLUGINS_REPO}" \
  --title "${PLUGIN_NAME} ${VERSION}" \
  --notes "$DESCRIPTION"

# Commit registry + public only after gh succeeds.
write_plugins_file "$NEW_PLUGINS"
regenerate_all_manifests

commit_registry "publish: ${PLUGIN_NAME} v${VERSION}"
commit_public   "bump manifests for ${PLUGIN_NAME} v${VERSION}"

cat <<EOF

Plugin published.

  plugin        : ${PLUGIN_NAME}
  version       : ${VERSION}
  release tag   : ${TAG_NAME}
  artifact URL  : ${RELEASE_BASE}/${TAG_NAME}/${ARTIFACT_FILENAME}

All active clients that include '${PLUGIN_NAME}' in allowed_plugins (and don't
pin an older version) have been regenerated to point at v${VERSION}.
EOF
