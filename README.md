# Rockstarr Marketplace (public)

Per-client plugin marketplace for Rockstarr AI. Each client's Cowork pulls a
tokenized manifest from this repo via `raw.githubusercontent.com`. No server,
no Workers — static files in a public repo.

**This repo is public and contains no client names or identifying information.**
Per-client `marketplace.json` files are keyed only by a 32-character opaque
token. Client identity, status, and notes live in a separate **private**
registry repo.

## Repo pair

```
github.com/rockstarrmoon/rockstarr-marketplace           ← public, this repo
github.com/rockstarrmoon/rockstarr-marketplace-registry  ← PRIVATE, source of truth
github.com/rockstarrmoon/rockstarr-plugins               ← public, holds .plugin release assets
```

The admin scripts in `/scripts/` live here for convenience (they contain no
secrets). They read the private registry from a sibling checkout on your
laptop and write to both repos atomically per operation.

## How a client install works

```
  client's Cowork
        │
        ▼  GET https://raw.githubusercontent.com/rockstarrmoon/rockstarr-marketplace/main/clients/<TOKEN>/marketplace.json
 ┌───────────────────────────┐
 │ GitHub raw content CDN    │
 └───────────────────────────┘
        │
        ▼  the manifest points at:
 ┌───────────────────────────┐
 │ GitHub Releases           │ https://github.com/rockstarrmoon/rockstarr-plugins/releases/download/<tag>/<file>.plugin
 │ (in rockstarr-plugins)    │
 └───────────────────────────┘
```

## Folder layout

```
/clients/<token>/marketplace.json   ← tokenized per-client manifest
/scripts/                           ← admin scripts (read private registry)
/examples/                          ← reference shapes for registry records
/README.md
```

There is deliberately **no `/registry/` folder** in this repo. If you see
one, it's a leftover from the scaffold that needs to be `git rm`-ed.

## Operator setup — one-time

You need both repos cloned side-by-side on your laptop:

```bash
cd ~/Desktop/code
gh repo clone rockstarrmoon/rockstarr-marketplace
gh repo clone rockstarrmoon/rockstarr-marketplace-registry
```

The scripts assume `rockstarr-marketplace-registry` is a sibling directory
of `rockstarr-marketplace`. If you keep them elsewhere, export
`REGISTRY_PATH` before running any script.

Then install the required CLI tools:

```bash
brew install gh jq
gh auth login
gh auth setup-git
```

Make the scripts executable:

```bash
chmod +x scripts/*.sh
```

## Day-to-day operations

| Task                           | Command                                             |
|--------------------------------|-----------------------------------------------------|
| New client                     | `scripts/create-client.sh <id> "<name>" <plugins>`  |
| Publish new plugin version     | `scripts/publish-plugin.sh <name> <ver> <file> "<desc>"` |
| Pause a client                 | `scripts/set-status.sh <token> paused`              |
| Mark a client churned          | `scripts/set-status.sh <token> churned`             |
| Reactivate                     | `scripts/set-status.sh <token> active`              |
| Pin a client to a plugin ver   | `scripts/pin-version.sh <token> <plugin> <version>` |
| Remove a pin                   | `scripts/pin-version.sh <token> <plugin> unpin`     |

Each script commits and pushes to both repos. See `/scripts/README.md` for
argument details and recovery notes.

## Cache staleness

`raw.githubusercontent.com` serves with `Cache-Control: max-age=300`, so a
status change can take up to ~5 minutes to propagate to a client's Cowork.
Acceptable for plugin updates; if you ever need faster, we'd need to front
this with a proxy (which we explicitly chose not to).

## Naming

The GitHub org is `rockstarrmoon` (no "and"). The agency brand is
"Rockstarr & Moon" and the web/email domain is `rockstarrandmoon.com` —
don't conflate them.
