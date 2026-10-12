# Operations guide: scripts, updates, backups, restore and rollback

← [Back to README](../../README.md) · English | [Türkçe](../tr/operations.md)

All scripts are POSIX shell scripts in `scripts/`. Run them from the repository root on the Docker host (inside WSL
on Windows). They read `.env`, never print secret values and stop on the first error.

- [install.sh](#installsh)
- [update.sh](#updatesh)
- [rollback.sh](#rollbacksh)
- [backup.sh](#backupsh)
- [restore.sh](#restoresh)
- [verify.sh](#verifysh)
- [verify-signatures.sh](#verify-signaturessh)
- [wazuh-init.sh](#wazuh-initsh)
- [init-secrets.sh](#init-secretssh)
- [Deployment history: .horus-deployments](#deployment-history-horus-deployments)
- [Day-to-day commands](#day-to-day-commands)
- [Recommended routine](#recommended-routine)

## install.sh

```bash
./scripts/install.sh [--self-signed] [--no-pull] [--require-signature]
```

| Option | Effect |
|---|---|
| `--self-signed` | Creates a temporary self-signed certificate for `HORUS_DOMAIN` when `nginx/certs/` is empty |
| `--no-pull` | Uses images already present locally (air-gapped hosts: `docker load` them first) |
| `--require-signature` | Refuses to install unless `cosign` verifies both images |

Steps: preflight → signature verification (when `cosign` is installed) → `docker compose pull` →
`docker compose up -d` → wait for health checks (max. 10 minutes) → `verify.sh` → record in `.horus-deployments`.

**Preflight checks:** Docker and Compose ≥ 2.24, `.env` exists (warns if not `chmod 600`), `HORUS_IMAGE` without
tag/digest, exact `HORUS_VERSION` (no `latest`), digest format, `HORUS_WORKER_CPUS` ≤ host CPUs, TLS files in
`https` mode, free disk space (warns below 5 GB), valid Compose configuration. A new installation also needs
`HORUS_ADMIN_PASSWORD`.

## update.sh

```bash
./scripts/update.sh <version> [<backend digest> <frontend digest>]
./scripts/update.sh 1.1.0 sha256:<backend> sha256:<frontend>
```

Steps:

1. Preflight, then pull `backend-<version>` / `frontend-<version>` (with digests when given).
2. Signature verification when `cosign` is installed and both digests are given - otherwise a warning.
3. **Schema check:** the new backend image must know the database's current migration revision, so a downgrade
   cannot happen by accident. If not, nothing is changed.
4. **Backup** into `backups/` and a record of the current release (version, digests, schema revision, backup file)
   in `.horus-deployments`.
5. `HORUS_VERSION` and the digests are written to `.env`; the stack is restarted (the `api` container applies
   database migrations).
6. Health wait and `verify.sh`. On failure the script tells you to run `rollback.sh`.

Get the new values from the new release:

```bash
git fetch --tags && git checkout v1.1.0
jq -r '.version, .backend.digest, .frontend.digest' release-manifest.json
```

> [!NOTE]
> `update.sh` changes only `HORUS_VERSION` and the two digests in `.env`. When a release adds new settings, compare
> your `.env` with the new `.env.example`. If the signing identity changes, update `HORUS_SIGNING_IDENTITY` too.

## rollback.sh

```bash
./scripts/rollback.sh                 # previous release, images only
./scripts/rollback.sh --with-backup   # previous release + the backup taken by update.sh
```

Uses the last `update from` record in `.horus-deployments`. Without `--with-backup` it refuses when the database was
migrated to a schema the previous release does not know - migrations are forward-only. With `--with-backup` the
pre-update backup is restored, **so everything changed after the update is lost**.

## backup.sh

```bash
./scripts/backup.sh [<directory>]     # default: backups/
```

Creates `<directory>/horus-<UTC timestamp>.tar.gz` (mode `600`) containing:

| Member | Content |
|---|---|
| `horus.dump` | PostgreSQL dump (`pg_dump --format=custom`) |
| `secrets.tar.gz` | The `horus_secrets` volume, including the master key |
| `env` | Your `.env` (when present) |

> [!WARNING]
> The archive contains all secrets of the installation. Encrypt it (for example with `age` or `gpg`) and keep copies
> off-host. Test restores regularly.

Example nightly cron job on the Docker host:

```cron
15 2 * * *  cd /opt/horus-deploy && ./scripts/backup.sh /srv/horus-backups >> /var/log/horus-backup.log 2>&1
```

## restore.sh

```bash
./scripts/restore.sh backups/horus-<timestamp>.tar.gz
```

1. Checks the archive (both members present, the secrets contain the database password) - nothing is changed
   if it is incomplete.
2. Stops `api`, `worker`, `worker-periodic`, `beat`; restores the secrets volume; recreates `postgres` and `redis`.
3. Aligns the database role password with the restored secret.
4. Restores the dump into a separate database **in one transaction**, stopping at the first error.
5. **Refuses a backup from a newer release** (unknown schema revision) - the current database stays untouched.
6. Switches databases and keeps the previous one as `horus_pre_restore_<timestamp>`; starts the services again
   (older schemas are migrated on start).

The archive's `env` member is **not** applied automatically - compare it with your `.env`.

**Restore on a new host:**

```bash
git clone --branch v1.0.0 https://github.com/doganyesilkir/horus-deploy.git && cd horus-deploy
tar -xzf /path/horus-<ts>.tar.gz env && mv env .env && chmod 600 .env
# a new host needs HORUS_ADMIN_PASSWORD for install.sh - set a temporary strong value if it is empty
./scripts/install.sh --self-signed       # or with your certificate in nginx/certs/
./scripts/restore.sh /path/horus-<ts>.tar.gz
```

After checking the restored data, drop the safety copy:

```bash
docker compose exec -T postgres psql -U horus -d postgres -c 'DROP DATABASE horus_pre_restore_<timestamp>'
```

## verify.sh

```bash
./scripts/verify.sh
```

| Check | Expectation |
|---|---|
| Services | running and healthy |
| HTTPS | `/api/v1/health` returns 200 over HTTPS with an HSTS header (`https` mode) |
| Redirect | HTTP redirects to HTTPS; the web UI loads |
| `/metrics` | not reachable through the proxy |
| Hardening | non-root user, read-only root filesystem, all capabilities dropped (Falco: only BPF, PERFMON, SYS_RESOURCE, SYS_PTRACE), `no-new-privileges`, not privileged, no host network/PID/IPC, no Docker socket |
| Exposure | only nginx publishes ports |

Exit code `0` means everything passed.

## verify-signatures.sh

```bash
./scripts/verify-signatures.sh
```

Needs `cosign`, both digests and `HORUS_SIGNING_IDENTITY` in `.env`. Runs, for each image:

```bash
cosign verify \
  --certificate-identity-regexp "$HORUS_SIGNING_IDENTITY" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  <HORUS_IMAGE>:backend-<version>@<digest>
```

The identity is validated first: only the exact format of the Horus release workflow is accepted.

## wazuh-init.sh

```bash
./scripts/wazuh-init.sh
```

Bundled Wazuh only. Writes `wazuh/config/wazuh_indexer/internal_users.yml` with bcrypt hashes of
`WAZUH_INDEXER_PASSWORD` and `WAZUH_DASHBOARD_PASSWORD` (computed by the Wazuh indexer image in a container without
network). Run once before the first `docker compose -f docker-compose.wazuh.yml up -d`. The generated file is
ignored by git.

## init-secrets.sh

Not run by hand. The one-shot `horus-init` container runs it on every `docker compose up`: for each secret it uses
the value from `.env` when set, keeps an existing value otherwise, or generates a new random one. It also writes the
Redis configuration.

## Deployment history: .horus-deployments

`install.sh`, `update.sh` and `rollback.sh` append to `.horus-deployments` (ignored by git): timestamps, the running
image digests and, for updates, the previous version, digests, schema revision and backup file. `rollback.sh`
reads it - keep it.

## Day-to-day commands

```bash
docker compose ps                          # status
docker compose logs -f --tail 100 api      # follow a service
docker compose restart nginx               # e.g. after replacing the certificate
docker compose stop && docker compose start
docker compose down                        # stop and remove containers (volumes and data are kept)
```

> [!CAUTION]
> `docker compose down -v` **deletes all volumes**, including the database and the secrets (master key). Only use it
> to remove an installation for good - after taking a backup.

## Recommended routine

| When | What |
|---|---|
| Daily | `backup.sh` (cron), copy off-host |
| After every change to the deployment | `verify.sh` |
| Before an update | read `RELEASE_NOTES.md`, verify signatures, `update.sh` with digests |
| Monthly | test a restore on a separate host |
