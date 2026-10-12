# Horus - deployment

Horus is a Linux security and operations automation platform. This repository contains everything needed to run
it from the published, signed container images: Compose files, configuration templates, policy override examples,
monitoring configuration and operational scripts. **No source code is needed or included.**

Both images live in one private Docker Hub repository, `<dockerhub_username>/horus`, and support linux/amd64 and
linux/arm64:

| Tag | Contents |
|---|---|
| `backend-<version>` | API, automation workers, scheduler - one image, the services differ only by command (compiled native modules) |
| `frontend-<version>` | Web UI (Next.js production server) |

Third-party images (PostgreSQL, Redis, nginx, Prometheus, Grafana, Loki, optional Falco / Wazuh) are pulled from
their official repositories at pinned versions.

## Requirements

- Linux host (x86_64 or arm64), 4 CPU / 8 GB RAM minimum (16 GB with the bundled Wazuh, x86_64 only)
- Docker Engine 24+ and Docker Compose 2.24+
- A DNS name and a TLS certificate (a temporary self-signed one can be generated)
- Outbound SSH from the Docker host to the Linux servers Horus manages

## Install

```bash
git clone <this repository> horus-deploy && cd horus-deploy
cp .env.example .env && chmod 600 .env
```

Edit `.env`:

| Variable | Value |
|---|---|
| `HORUS_IMAGE` | `<dockerhub_username>/horus` |
| `HORUS_VERSION` | exact release, e.g. `1.0.0` (images `backend-1.0.0` / `frontend-1.0.0`; never `latest`) |
| `HORUS_BACKEND_DIGEST`, `HORUS_FRONTEND_DIGEST` | recommended: the `sha256:` digests from `release-manifest.json` (pins the exact images; required for signature verification) |
| `HORUS_DOMAIN` | the name users open, e.g. `horus.example.com` |
| `HORUS_ADMIN_PASSWORD` | initial administrator password (must be changed at first login) |
| `HORUS_SIGNING_IDENTITY` | signature identity from `release-manifest.json` (for `scripts/verify-signatures.sh`) |

All other secrets may stay empty: they are generated once into the `horus_secrets` Docker volume. To supply your
own, generate them with `openssl rand -hex 32`.

TLS certificate: put `fullchain.pem` and `privkey.pem` into `nginx/certs/`, or let the installer create a temporary
self-signed certificate (`--self-signed`).

```bash
docker login                       # credentials for the private image repository
./scripts/install.sh               # or: ./scripts/install.sh --self-signed
```

The installer checks the host and `.env`, verifies the image signatures (when `cosign` is installed), pulls the
images, starts the stack, waits for all health checks and runs `scripts/verify.sh`. Then open
`https://<HORUS_DOMAIN>/` and change the administrator password.

Manual equivalent: `docker compose pull && docker compose up -d && docker compose ps && ./scripts/verify.sh`.

## Verify images

Every release image is signed with Sigstore Cosign (keyless, GitHub Actions OIDC). Verify before running:

```bash
cosign verify \
  --certificate-identity-regexp "$HORUS_SIGNING_IDENTITY" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  <dockerhub_username>/horus:backend-1.0.0@sha256:<digest>
```

or simply `./scripts/verify-signatures.sh` (checks both configured images). `release-manifest.json` lists the
digests, the signing identity (`signature.identity` - copy it verbatim into `HORUS_SIGNING_IDENTITY`), the SBOM
files and the agent binary checksums of each release. The scripts refuse a missing or loosened identity;
`./scripts/install.sh --require-signature` additionally refuses to install without a successful verification.

## Network exposure

Only nginx publishes ports: 443 (HTTPS) and 80 (redirect to HTTPS). PostgreSQL, Redis, the API, Prometheus and
Loki are reachable only on internal Docker networks. Grafana is served under `/grafana/` with its own login. All
containers run as non-root users with a read-only root filesystem, all Linux capabilities dropped and
`no-new-privileges`; none mounts the Docker socket.

`HORUS_PROXY_MODE=http-dev` serves plain HTTP on port 80 - **for development or isolated labs only**.

## Update

```bash
./scripts/update.sh 1.1.0 sha256:<backend digest> sha256:<frontend digest>
```

The update runs a preflight, verifies signatures, checks that the new release knows the current database schema,
writes a backup to `backups/`, records the running images in `.horus-deployments`, starts the new release (database
migrations run automatically in the `api` container) and verifies health. Read the release notes first - they list
migration and breaking changes.

## Rollback

```bash
./scripts/rollback.sh                 # previous images; allowed when the release did not change the schema
./scripts/rollback.sh --with-backup   # previous images + the backup taken before the update
```

Database migrations are forward-only. When an update changed the schema, an older release cannot run on the new
schema; `--with-backup` restores the pre-update backup, so changes made after the update are lost. Each release
note states whether it contains migrations.

## Backup and restore

```bash
./scripts/backup.sh backups              # database dump + secrets volume + .env -> backups/horus-<ts>.tar.gz
./scripts/restore.sh backups/horus-<ts>.tar.gz
```

The archive contains the master key and `.env`: store it encrypted and offline. Restoring on a new host only needs
this repository, the images and the archive:

```bash
git clone <this repository> horus-deploy && cd horus-deploy
tar -xzf /path/horus-<ts>.tar.gz env && mv env .env && chmod 600 .env    # same image references
./scripts/install.sh && ./scripts/restore.sh /path/horus-<ts>.tar.gz
```

The restore checks the archive, restores into a separate database in one transaction, refuses a backup from a newer
release, and keeps the previous database as `horus_pre_restore_<ts>`.

## Policies

Shipped policies are inside the image. Put overrides into `policies/` (see `policies/README.md` and
`policies/examples/`).

## Wazuh (optional)

Horus runs without Wazuh. To use an existing Wazuh, set `HORUS_WAZUH_ENABLED=true` and the `HORUS_WAZUH_*` values.
To run the bundled single-node Wazuh (x86_64, +8 GB RAM, `sysctl -w vm.max_map_count=262144`):

```bash
# set WAZUH_INDEXER_PASSWORD, WAZUH_API_PASSWORD, WAZUH_DASHBOARD_PASSWORD in .env (required, no defaults)
./scripts/wazuh-init.sh
docker compose -f docker-compose.wazuh.yml up -d
```

Wazuh agents on your servers connect to ports 1514/1515 of the Docker host. The Wazuh dashboard listens on
127.0.0.1:8443 by default.

## Falco on the Docker host (optional)

```bash
docker compose --profile falco up -d falco
```

Managed servers get Falco through Horus itself (Runtime Security).

## Horus agent (optional)

Release assets contain native agent binaries (`horus-agent-<version>-linux-amd64|arm64`, glibc 2.36+) with SHA-256
checksums in `release-manifest.json`:

```bash
sha256sum -c horus-agent-1.0.0-linux-amd64.sha256
install -m 0755 horus-agent-1.0.0-linux-amd64 /usr/local/bin/horus-agent
horus-agent enroll --url https://<HORUS_DOMAIN> --code <one-time code from Assets -> Agent>
```

Each agent receives its own asset-bound token (stored hashed by Horus, revocable; re-enrolment rotates it).

## Hızlı kurulum (Türkçe)

```bash
git clone <bu depo> horus-deploy && cd horus-deploy
cp .env.example .env && chmod 600 .env     # HORUS_IMAGE, HORUS_VERSION, HORUS_DOMAIN, HORUS_ADMIN_PASSWORD doldurun
docker login
./scripts/install.sh                        # sertifika yoksa: ./scripts/install.sh --self-signed
```

Güncelleme `scripts/update.sh`, geri dönüş `scripts/rollback.sh`, yedek `scripts/backup.sh`, geri yükleme
`scripts/restore.sh` ile yapılır. Ayrıntılar yukarıdaki bölümlerdedir.
