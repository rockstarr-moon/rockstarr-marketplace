# Rockstarr Marketplace (GitHub edition)

Per-client plugin marketplace for Rockstarr AI, hosted as static JSON files
in this repo. Each client's Cowork instance pulls a manifest directly from
`raw.githubusercontent.com` — no server, no Workers, no KV. Client access
is gated by a 32-character token in the URL path.

This repo replaces the earlier Cloudflare Worker implementation.

## How it works

```
  client's Cowork
        │
        ▼  GET https://raw.githubusercontent.com/<owner>/rockstarr-marketplace/main/clients/<TOKEN>/marketplace.json
 ┌───────────────────────────┐
 │ GitHub (raw content CDN)  │
 └───────────────────────────┘
        │  ▲
        │  │ the manifest points at:
        ▼  │
 ┌───────────────────────────┐
 │ GitHub Releases           │ https://github.com/<owner>/rockstarr-plugins/releases/download/<tag>/<file>.plugin
 │ (in rockstarr-plugins)    │
 └───────────────────────────┘
```

The admin scripts in `/scripts/` are the only way records should change.
They edit the registry files, regenerate affected client manifests, and
`git push` — the push IS the deploy.

## Folder layout

```
/clients/<token>/marketplace.json   ← the URL each client uses
/registry/clients.json              ← source of truth for all client records
/registry/plugins.json              ← plugin catalog (version, description, release info)
/scripts/                           ← create-client, publish-plugin, set-status, pin-version
/examples/                          ← reference shapes for registry records
```

## One-time setup — Jon does this part

### 1. Create the two GitHub repos

Both public. Either via the web UI at https://github.com/new, or via the
`gh` CLI once you've run `gh auth login`:

```bash
gh repo create rockstarrmoon/rockstarr-marketplace --public \
  --description "Per-client plugin manifests for Rockstarr AI."

gh repo create rockstarrmoon/rockstarr-plugins --public \
  --description "GitHub Releases host the .plugin binaries consumed by the marketplace."
```

If the `rockstarrmoon` org doesn't exist yet, either create it at
https://github.com/organizations/plan (free tier is fine) or substitute
your personal account name — everything else below still works, just swap
the `<owner>` placeholder.

### 2. Push this scaffold into `rockstarr-marketplace`

From your laptop, with this folder copied somewhere permanent (e.g.
`~/Code/rockstarr-marketplace`):

```bash
cd ~/Code/rockstarr-marketplace
git init
git add .
git commit -m "Seed marketplace scaffold"
git branch -M main
git remote add origin git@github.com:rockstarrmoon/rockstarr-marketplace.git
git push -u origin main
```

### 3. Initialize the plugins repo

Nothing to push yet — GitHub Releases live on an otherwise empty repo.
Later, `scripts/publish-plugin.sh` runs `gh release create` against this repo.

```bash
cd ~/Code
gh repo clone rockstarrmoon/rockstarr-plugins
cd rockstarr-plugins
git commit --allow-empty -m "Initial"
git push -u origin main
```

### 4. Install prerequisites

The scripts (phase 2 of this migration) assume you have:

- `git` — already installed if you got this far.
- `gh` — the GitHub CLI. `brew install gh` on macOS, then `gh auth login`.
- `jq` — JSON on the command line. `brew install jq`.

## Day-to-day operations (after phase 2 scripts ship)

| Task                           | Command                                             |
|--------------------------------|-----------------------------------------------------|
| New client                     | `scripts/create-client.sh <id> "<name>" <plugins>`  |
| Publish new plugin version     | `scripts/publish-plugin.sh <name> <ver> <file> "<desc>"` |
| Pause a client                 | `scripts/set-status.sh <token> paused`              |
| Mark a client churned          | `scripts/set-status.sh <token> churned`             |
| Reactivate                     | `scripts/set-status.sh <token> active`              |
| Pin a client to a plugin ver   | `scripts/pin-version.sh <token> <plugin> <version>` |
| Remove a pin                   | `scripts/pin-version.sh <token> <plugin> unpin`     |

Each script commits and pushes. A client manifest goes live the moment the
push lands, with ~5 minutes of CDN cache staleness on
`raw.githubusercontent.com`.

## Naming and the `<owner>` placeholder

Throughout this repo, `<owner>` means the GitHub user or org that owns the
two repos — i.e. whatever you typed in step 1 above (likely
`rockstarrmoon`). The scripts will read this from a `.env` / config file
so it's set in one place.

## What's NOT in this scaffold yet

Phase 2 of the migration adds the four admin scripts. Phase 3 publishes the
first plugin release and creates your first client (yourself, for
end-to-end testing). Phase 4 retires the Cloudflare Worker code. See the
migration plan in the Rockstarr project notes for the full sequence.
