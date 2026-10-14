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
- [wazuh-backup.sh and wazuh-restore.sh](#wazuh-backupsh-and-wazuh-restoresh)
- [Bundled Wazuh upgrade](#bundled-wazuh-upgrade)
- [Platform check](#platform-check)
- [init-secrets.sh](#init-secretssh)
- [Deployment history: .horus-deployments](#deployment-history-horus-deployments)
- [Day-to-day commands](#day-to-day-commands)
- [Recommended routine](#recommended-routine)

## install.sh

```bash
./scripts/install.sh [--self-signed] [--no-pull] [--require-signature] [--with-wazuh]
```

| Option | Effect |
|---|---|
| `--self-signed` | Creates a temporary self-signed certificate for `HORUS_DOMAIN` when `nginx/certs/` is empty |
| `--no-pull` | Uses images already present locally (air-gapped hosts: `docker load` them first) |
| `--require-signature` | Refuses to install unless `cosign` verifies both images |
| `--with-wazuh` | Adds the bundled Wazuh: `COMPOSE_FILE=docker-compose.wazuh.yml` in `.env`, Wazuh checks, `wazuh-init.sh` once |

Steps: preflight → [platform check](#platform-check) → (Wazuh: passwords, `vm.max_map_count`, password hashes) →
signature verification (when `cosign` is installed) → `docker compose pull` → `docker compose up -d` → wait for health
checks (max. 10 minutes, 20 with Wazuh) → `verify.sh` → record in `.horus-deployments`.

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

1. Preflight and [platform check](#platform-check) of every image of the new release (with the deployment files you
   checked out), then pull `backend-<version>` / `frontend-<version>` (with digests when given).
2. Signature verification when `cosign` is installed and both digests are given - otherwise a warning.
3. **Schema check:** the new backend image must know the database's current migration revision, so a downgrade
   cannot happen by accident. If not, nothing is changed.
4. **Backup** into `backups/` and a record of the current release (version, digests, schema revision, backup file)
   in `.horus-deployments`. When the new deployment files change the bundled Wazuh version, `wazuh-backup.sh` also
   stops Wazuh and copies its volumes (see [Bundled Wazuh upgrade](#bundled-wazuh-upgrade)).
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
network, after checking that the image exists for the Docker host's platform). `install.sh --with-wazuh` runs it
when the file is missing; run it yourself only to change these passwords. The generated file is ignored by git.

## wazuh-backup.sh and wazuh-restore.sh

```bash
./scripts/wazuh-backup.sh [<dir>]                   # default: backups -> backups/wazuh-<timestamp>/
./scripts/wazuh-restore.sh backups/wazuh-<timestamp>
```

`wazuh-backup.sh` **stops** the Wazuh services (a running indexer cannot be copied consistently) and copies every
Wazuh volume - indexer data, manager configuration and databases, agent keys, queues, Filebeat state, dashboard
configuration - into one archive per volume plus a `MANIFEST` with the image versions. It does not restart Wazuh.
The data is streamed from the Docker host, so remote Docker contexts work. Keep the archives like `.env`: they contain
agent keys and all indexed events.

- **Space check first.** While Wazuh still runs, the script measures the volumes and compares the uncompressed size
  (+5 % and 512 MiB, an upper bound - the gzip archives are usually smaller) with the free space of the target
  directory. Too little space stops it with `insufficient disk space for the Wazuh backup` before anything is stopped.
  The vulnerability-detection content in the `wazuh_queue` volume alone is several GB.
  `HORUS_WAZUH_BACKUP_SPACE_CHECK=0` skips the check at your own risk.
- **Complete or nothing.** Archives are written to `<dir>/.wazuh-<timestamp>.partial` and renamed to
  `<dir>/wazuh-<timestamp>` only when every volume was copied and verified. On any error - a full disk, a read error -
  the partial directory is removed, the script exits non-zero and the stopped Wazuh containers are started again
  unchanged - except during an upgrade, when the deployment files already belong to the new Wazuh version: then Wazuh
  stays stopped (the old containers would read the new configuration files) and the message says how to continue.
  Unix sockets in the manager volumes are runtime endpoints and are skipped without a message.

`wazuh-restore.sh` only accepts a backup of the same Compose project. Run it from the **current** checkout (older
releases do not ship it): it stops Wazuh, empties and refills each volume and starts **nothing**. Then check out the
deployment files of the release the backup was taken with (its `MANIFEST` lists the images) and start that release -
starting the newer files would migrate the restored data forward again.

## Bundled Wazuh upgrade

A Horus release can change the bundled Wazuh version (for example 4.9.2 → **4.14.8**). The indexer data and the
manager databases are migrated forward on the first start and **cannot be downgraded**; the only way back is a copy
taken before. Same commands on x86_64 and ARM64:

```bash
git fetch --tags && git checkout v<new version>      # new deployment files incl. Wazuh configuration
jq -r '.version, .backend.digest, .frontend.digest' release-manifest.json
./scripts/update.sh <version> sha256:<backend> sha256:<frontend>
```

`update.sh` notices that the running `wazuh-manager` image differs from the new one, checks the platform of every new
image first and runs `wazuh-backup.sh` before anything is started. Then the stack starts with the new Wazuh: the
certificates in `wazuh/certs/` and the passwords stay as they are (no reset, no default password). A Wazuh that was
started by hand with `docker compose -f docker-compose.wazuh.yml` is adopted (`COMPOSE_FILE` is added to `.env`), and
`install.sh --with-wazuh` backs up a running Wazuh of another version in the same way.

**Wazuh 4.9.2 → 4.14.8 - what changes in the deployment files**

- Indexer configuration, security files and certificates are mounted under `/usr/share/wazuh-indexer/config/`
  (`opensearch.yml`, `opensearch-security/internal_users.yml`, `certs/`); `wazuh.indexer.yml` uses the new paths.
- Certificate generator `0.0.4` with `CERT_TOOL_VERSION=4.14` (only used when `wazuh/certs/` is empty).
- The manager configuration loads the `malicious-ioc` lists of the 4.14 ruleset.
- Health checks for the manager and the dashboard; they start after the indexer / manager is healthy.
- `platform: linux/amd64` is gone - every image is multi-arch.

**Going back** after a Wazuh upgrade (data written since the backup is lost):

```bash
./scripts/wazuh-restore.sh backups/wazuh-<timestamp>   # from the current checkout; Wazuh stays stopped
git checkout v<previous version>
./scripts/rollback.sh             # Horus images (or docker compose up -d when only Wazuh is affected)
```

On an **x86_64 host with an existing 4.9.2**, this path is the only one with data to migrate. On ARM64 there is no
4.9.2 data: those images never ran there (`exec format error`), so the upgrade is a first installation.

## Platform check

`install.sh`, `update.sh` and `wazuh-init.sh` ask the **Docker daemon** for its platform
(`docker version` → `Server.Os/Arch`), not the machine running the script - remote Docker contexts and `DOCKER_HOST`
work. Then every image of the selected Compose files is looked up in its registry (`docker manifest inspect`, in
parallel) and must list that platform; attestation manifests (`unknown/unknown`) do not count. A missing platform,
an unknown tag or a registry error (login, network, rate limit) stops the script **before** anything is pulled or
changed and lists the affected images. With `--no-pull`, images already present locally are checked locally. There is
no emulation fallback.

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
