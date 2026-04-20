# Examples

Reference shapes for the files the admin scripts read and write. The scripts
will enforce these shapes automatically — these examples exist so a human can
eyeball what a valid record looks like.

- `client-manifest.json` — the per-client file that lands at
  `/clients/<token>/marketplace.json` and is what Cowork fetches.
- `clients-entry.json` — the shape of a single client record inside
  `registry/clients.json`, keyed by the 32-char token.
- `plugins-entry.json` — the shape of a single plugin record inside
  `registry/plugins.json`, keyed by plugin name.

## Status values (clients.json)

| Status    | Effect on manifest                                                |
|-----------|-------------------------------------------------------------------|
| `active`  | Manifest lists all `allowed_plugins` at their effective version.  |
| `pinned`  | Same as active, but scripts warn before bumping any pinned plugin.|
| `paused`  | Manifest regenerated with empty `plugins: []`.                    |
| `churned` | Manifest regenerated with empty `plugins: []`.                    |

`paused` and `churned` are semantically different for our records but
operationally identical: the client's existing installs keep working, but no
upgrades flow.

## Version pin format (clients.json → version_pins)

```json
"version_pins": {
  "rockstarr-infra": "0.4.11"
}
```

An empty object means no pins — the client tracks each plugin's
`current_version` from `registry/plugins.json`.
