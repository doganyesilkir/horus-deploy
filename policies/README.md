# Policy overrides

The complete Horus policy set ships inside the backend image. This directory is mounted read-only at
`/app/policy-overrides` and only needs the files you want to change - use the **same relative path** as the
shipped file:

| Override file | Effect |
|---|---|
| `fim/fim.yaml`, `scoring/default.yaml`, `scoring/risk.yaml`, `firewall/firewall.yaml`, `retention/retention.yaml`, ... | deep-merged over the shipped document: maps merge, **lists and scalars replace**, `null` removes a key |
| `baselines/<name>.yaml` | adds a baseline (or replaces a shipped file with the same name); may `extends:` a shipped one |
| `correlation/`, `hunting/`, `runbooks/`, `compliance/` `*.yaml` | added to the shipped rules; the same file name replaces the shipped file |

Files under `examples/` are never loaded. Copy one to its target path, edit it, then apply without a restart
(Settings -> Policies -> Reload, or `POST /api/v1/policies/reload`). Invalid files are logged and ignored; the
shipped policy stays in force.
