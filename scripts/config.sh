#!/usr/bin/env bash
# config.sh — single source of truth for repo names and paths.
# Sourced by every admin script. Edit ONE place if a name ever changes.

# GitHub owner (user or org) that owns the repos.
OWNER="rockstarrmoon"

# The PUBLIC repo holding per-client manifests + these scripts.
MARKETPLACE_REPO="rockstarr-marketplace"

# The PRIVATE repo holding clients.json and plugins.json (names, state).
REGISTRY_REPO="rockstarr-marketplace-registry"

# The repo whose GitHub Releases host the .plugin binaries.
PLUGINS_REPO="rockstarr-plugins"

# Base URL served by GitHub's raw CDN. Clients paste
#   ${RAW_BASE}/clients/<token>/marketplace.json
# into Cowork.
RAW_BASE="https://raw.githubusercontent.com/${OWNER}/${MARKETPLACE_REPO}/main"

# Base URL for plugin release downloads.
RELEASE_BASE="https://github.com/${OWNER}/${PLUGINS_REPO}/releases/download"

# Human-readable owner for the manifest "owner" field.
OWNER_DISPLAY_NAME="Rockstarr & Moon"
MARKETPLACE_DISPLAY_NAME="Rockstarr AI"

# Where the private registry checkout lives on this machine.
# Default: a sibling of the public marketplace checkout. Override by setting
# REGISTRY_PATH before calling a script, e.g.:
#   REGISTRY_PATH=~/Code/rockstarr-marketplace-registry scripts/create-client.sh ...
if [[ -z "${REGISTRY_PATH:-}" ]]; then
  _public_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  REGISTRY_PATH="$(cd "${_public_root}/.." && pwd)/${REGISTRY_REPO}"
fi
export REGISTRY_PATH
