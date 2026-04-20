# scripts/ — admin tools for the marketplace

Four scripts do all day-to-day operations. Each one edits the private
registry, regenerates any affected public manifests, and commits + pushes to
**both** repos.

## The two-repo model

Every script touches two git checkouts:

1. **Registry checkout** (private). Holds `clients.json` and `plugins.json` —
   client names, status, version pins. Messages in this repo's git log can be
   detailed (e.g. `create-client: rockstarr-ai-pilot`).
2. **Public checkout** (this repo). Holds the tokenized
   `/clients/<token>/marketplace.json` files. Messages use the first 8 chars
   of the token (`add manifest 5789bc86`) so the public git log never reveals
   who a token belongs to.

By default the scripts look for the registry checkout at
`../rockstarr-marketplace-registry` (a sibling directory). Override with
`REGISTRY_PATH`:

```bash
REGISTRY_PATH=~/some/other/path scripts/create-client.sh ...
```

## Prerequisites

- `jq`, `gh`, `git`, `openssl` on PATH
- `gh auth login` completed
- Both repo checkouts have clean working trees (scripts refuse to run
  otherwise — they don't want to mix unrelated changes into their commits)

## Universal flag

- `--no-push` — commit locally in both repos but don't push. Useful for
  rehearsing a change or recovering after a mistake.

## `create-client.sh`

```bash
scripts/create-client.sh <client_id> "<Display Name>" <plugin1,plugin2,...>
```

Generates a 32-char hex token, adds a record to `clients.json` with
`status: "active"` and the given allowed plugins, writes
`clients/<token>/marketplace.json` in the public repo, and prints the
manifest URL.

**Example:**

```bash
scripts/create-client.sh rockstarr-ai-pilot "Rockstarr AI — Pilot" rockstarr-infra
```

## `publish-plugin.sh`

```bash
scripts/publish-plugin.sh <name> <version> <path/to/file.plugin> "<description>"
```

Three steps:

1. `gh release create` in `rockstarrmoon/rockstarr-plugins`, uploading the
   `.plugin` file under its canonical filename and tagging `<name>-v<version>`.
2. Updates `plugins.json` in the registry — registers the plugin if new,
   otherwise bumps `current_version` and appends to `versions[]`.
3. Regenerates **every** client manifest in the public repo. Pinned clients
   stay put; others advance to the new version.

**Example:**

```bash
scripts/publish-plugin.sh rockstarr-infra 0.4.11 \
  ./rockstarr-infra-0.4.11.plugin \
  "Scaffolds the client folder, ingests the workbook, and generates the style guide."
```

If `gh release create` fails (e.g. tag already exists), nothing is committed
to either repo — fix the issue and re-run.

## `set-status.sh`

```bash
scripts/set-status.sh <token> <active|paused|churned>
```

| Status    | Public manifest                                                |
|-----------|----------------------------------------------------------------|
| `active`  | Full list from `allowed_plugins`.                              |
| `paused`  | `{plugins: []}`. Client keeps what they've installed.          |
| `churned` | Same as paused. Bookkeeping-only distinction.                  |

## `pin-version.sh`

```bash
scripts/pin-version.sh <token> <plugin> <version>
scripts/pin-version.sh <token> <plugin> unpin
```

While pinned, `publish-plugin.sh` won't advance the client's manifest for
that plugin.

## Recovery notes

**Undo a publish.** `gh release delete <tag> --repo rockstarrmoon/rockstarr-plugins`,
then hand-edit `plugins.json` in the registry to remove the version + reset
`current_version`. Commit the registry, regenerate all manifests (easiest: any
subsequent script call does this automatically), commit the public repo.

**Bad manifest for one client.** Re-run `scripts/set-status.sh <token>
active` to regenerate from registry state, or hand-edit the manifest and
commit.

**Lost registry.** See `rockstarr-marketplace-registry/README.md` —
this is the scenario the private repo exists to prevent. Back it up.

**Scripts are committing as the wrong user.** Run `git config --global
user.email "..."` with the email tied to your GitHub account. The
`--amend --reset-author` trick works for the most recent commit in a given
repo if it matters.
