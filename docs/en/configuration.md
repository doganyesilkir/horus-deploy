# Configuration reference

← [Back to README](../../README.md) · English | [Türkçe](../tr/configuration.md)

Horus is configured through `.env` in the repository root (copied from `.env.example`). The file is read by
Docker Compose and by the scripts. Keep it `chmod 600` - the preflight warns otherwise.

- [Release manifest](#release-manifest)
- [Images](#images)
- [Access and TLS](#access-and-tls)
- [First administrator](#first-administrator)
- [Secrets](#secrets)
- [Automation safety](#automation-safety)
- [UI and password policy](#ui-and-password-policy)
- [Runtime security (Falco)](#runtime-security-falco)
- [Wazuh](#wazuh)
- [Secret backend (Vault)](#secret-backend-vault)
- [Image signatures](#image-signatures)
- [Policy overrides](#policy-overrides)

## Release manifest

Every release checkout contains `release-manifest.json`, the authoritative description of the release:

| Field | Meaning |
|---|---|
| `version` | Release version, e.g. `1.0.0` |
| `repository` | Docker Hub repository of both images |
| `backend.tag`, `backend.digest` | `backend-<version>` and its multi-architecture `sha256` digest |
| `frontend.tag`, `frontend.digest` | `frontend-<version>` and its digest |
| `backend.platforms`, `frontend.platforms` | `linux/amd64`, `linux/arm64` |
| `signature.identity`, `signature.oidc_issuer` | Cosign keyless signing identity of the release workflow |
| `sbom.files` | CycloneDX SBOMs of the images |
| `agent` | File names, architectures and SHA-256 checksums of the optional agent binaries |

```bash
jq . release-manifest.json
```

The release's `.env.example` is generated from this manifest, so a fresh `cp .env.example .env` already contains
the right image, version, digests and identity.

## Images

| Variable | Default | Description |
|---|---|---|
| `HORUS_IMAGE` | `<dockerhub_username>/horus` | Repository without tag or digest |
| `HORUS_VERSION` | release version | Exact version; images `backend-<version>` / `frontend-<version>`. `latest` is refused |
| `HORUS_BACKEND_DIGEST` | release digest | `sha256:...` - pins the backend image (api, workers, scheduler) |
| `HORUS_FRONTEND_DIGEST` | release digest | `sha256:...` - pins the web UI image |

With a digest, Compose uses `<image>:<tag>@<digest>`: the tag documents the version, the digest guarantees the
content. Without digests the scripts warn, and signature verification is not possible.

## Access and TLS

| Variable | Default | Description |
|---|---|---|
| `HORUS_DOMAIN` | - | DNS name users open; also the CN/SAN of a `--self-signed` certificate |
| `HORUS_PROXY_MODE` | `https` | `https`: TLS on 443 with HSTS, 80 redirects. `http-dev`: plain HTTP on 80 - development only |
| `HORUS_BIND_ADDRESS` | `0.0.0.0` | Host address nginx binds to (e.g. a single interface) |
| `HORUS_HTTPS_PORT` / `HORUS_HTTP_PORT` | `443` / `80` | Published host ports |
| `HORUS_COOKIE_SECURE` | `auto` | Session cookies are `Secure` when the request arrived over HTTPS |
| `HORUS_FORWARDED_ALLOW_IPS` | empty | Trusted proxies for `X-Forwarded-For` (empty: Docker-internal networks only) |

Certificates: `nginx/certs/fullchain.pem` and `nginx/certs/privkey.pem` (see [nginx/certs/README.md](../../nginx/certs/README.md)).
After replacing them run `docker compose restart nginx`.

## First administrator

| Variable | Default | Description |
|---|---|---|
| `HORUS_ADMIN_USERNAME` | `admin` | Created only when the database has no users |
| `HORUS_ADMIN_EMAIL` | `admin@horus.local` | E-mail of that account |
| `HORUS_ADMIN_PASSWORD` | - | Required for a new installation; weak or example values are refused. Must be changed at first login |

After the first login the value is no longer used and can be removed from `.env`.

## Secrets

Leave these **empty** to have them generated once (random, per installation) into the `horus_secrets` Docker volume
by the `horus-init` container, or set your own values (`openssl rand -hex 32`):

| Variable | Used for |
|---|---|
| `HORUS_MASTER_KEY` | Encryption of stored SSH keys and integration secrets - **back it up** |
| `HORUS_JWT_SECRET` | Signing of session tokens |
| `POSTGRES_PASSWORD`, `REDIS_PASSWORD` | Internal database and queue |
| `GRAFANA_ADMIN_PASSWORD` | Grafana `admin` account (`/grafana/`) |
| `HORUS_INGEST_TOKEN` | Event ingestion of the platform itself (e.g. the local Falco container) |

Read a generated value (for example the Grafana password):

```bash
docker run --rm -v horus_secrets:/s:ro alpine:3.24.2 cat /s/grafana_admin_password; echo
```

## Automation safety

| Variable | Default | Description |
|---|---|---|
| `HORUS_OPERATION_MODE` | `APPROVAL` | `OBSERVE` (no changes), `APPROVAL` (changes need approval), `AUTONOMOUS` - initial value, changeable in Settings |
| `HORUS_ALLOW_SELF_APPROVAL` | `true` | `false` enforces the four-eyes principle |
| `HORUS_PRODUCTION_REQUIRED_APPROVALS` | `2` | Approvals for high-risk jobs on production assets |
| `HORUS_JOB_TIMEOUT_SECONDS` | `1800` | Hard limit per automation job |
| `HORUS_WORKER_CONCURRENCY` | `4` | Parallel jobs per worker |
| `HORUS_WORKER_CPUS` | `2.0` | CPU limit of the worker container - must not exceed the host's CPUs |
| `HORUS_IP_WHITELIST` | `127.0.0.1/32` | IPs/CIDRs automation must never block - add your management networks |
| `HORUS_SCHEDULE_TIMEZONE` | `UTC` | Time zone of new task schedules |
| `HORUS_SERVICE_STATUS_INTERVAL_SECONDS` | `60` | Background refresh of service states |
| `HORUS_FIREWALL_ROLLBACK_TIMEOUT` | `120` | Seconds before an unconfirmed firewall change is rolled back on the server |

## UI and password policy

| Variable | Default |
|---|---|
| `HORUS_DEFAULT_LANGUAGE` | `tr` (`tr` or `en`) |
| `HORUS_PASSWORD_MIN_LENGTH` | `12` |
| `HORUS_PASSWORD_REQUIRE_UPPER` / `_LOWER` / `_DIGIT` / `_SPECIAL` | `true` |
| `HORUS_PASSWORD_CHANGE_MAX_ATTEMPTS` | `5` |

## Runtime security (Falco)

| Variable | Description |
|---|---|
| `HORUS_FALCO_INGEST_URL` | URL your managed servers use to send Falco events to Horus, e.g. `https://horus.example.com` |
| `HORUS_FALCO_HOSTNAME` | Host name reported by the optional Falco container on the Docker host |

## Wazuh

External Wazuh with the standard `docker-compose.yml`:

| Variable | Description |
|---|---|
| `HORUS_WAZUH_ENABLED` | `true` to enable the integration |
| `HORUS_WAZUH_API_URL`, `HORUS_WAZUH_API_USER`, `HORUS_WAZUH_API_PASSWORD` | Wazuh manager API (port 55000) |
| `HORUS_WAZUH_INDEXER_URL`, `HORUS_WAZUH_INDEXER_USER`, `HORUS_WAZUH_INDEXER_PASSWORD` | Wazuh indexer (port 9200) |
| `HORUS_WAZUH_VERIFY_TLS`, `HORUS_WAZUH_CA_BUNDLE` | TLS verification (keep `true`; point the CA bundle at your Wazuh CA) |

Bundled Wazuh (`docker-compose.wazuh.yml`) - required, no defaults are ever used:

| Variable | Description |
|---|---|
| `WAZUH_INDEXER_PASSWORD`, `WAZUH_API_PASSWORD`, `WAZUH_DASHBOARD_PASSWORD` | 8-64 characters with upper case, lower case, digit and symbol |
| `WAZUH_DASHBOARD_BIND`, `WAZUH_DASHBOARD_PORT` | Wazuh dashboard, `127.0.0.1:8443` by default |

See [integrations.md](integrations.md#wazuh).

## Secret backend (Vault)

| Variable | Description |
|---|---|
| `HORUS_SECRET_BACKEND` | `database` (default: encrypted in PostgreSQL) or `vault` (HashiCorp Vault KV v2 for new credentials) |
| `HORUS_VAULT_ADDR`, `HORUS_VAULT_MOUNT`, `HORUS_VAULT_PREFIX`, `HORUS_VAULT_NAMESPACE`, `HORUS_VAULT_VERIFY_TLS` | Vault connection |
| `HORUS_VAULT_TOKEN_FILE` | Path **inside the containers** of a mounted token file - never put the token itself into `.env` |

To mount the token file, add a `docker-compose.override.yml` next to `docker-compose.yml` (Compose reads it
automatically) that mounts the file read-only into the `api`, `worker` and `worker-periodic` services.

## Image signatures

| Variable | Description |
|---|---|
| `HORUS_SIGNING_IDENTITY` | `signature.identity` from `release-manifest.json`, copied verbatim. The scripts accept only the exact Horus release identity format and refuse missing or loosened values |

## Policy overrides

Shipped policies are inside the image. Files in [`policies/`](../../policies/README.md) are mounted read-only and
override them (same relative paths; single documents are deep-merged). `policies/examples/` is never loaded.
Changed files are picked up automatically (Horus re-reads a policy file when it changes) - no restart is needed.
To force a reload, call `POST /api/v1/policies/reload` with an account that has the `policies:write` permission.
