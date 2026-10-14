# Horus 1.0.0

First release distributed as signed, pre-built images with a separate deployment repository. No source code is
needed to install, update, back up or restore Horus.

## Breaking changes

- **Deployment model.** Install from the deployment repository (`docker compose` with published images) instead of
  building from source. Images come from one private Docker Hub repository `<dockerhub_username>/horus`
  (`backend-<version>`, `frontend-<version>`, linux/amd64 + linux/arm64), selected in `.env` with `HORUS_IMAGE`,
  `HORUS_VERSION` and the optional digests; `latest` is refused by the scripts.
- **HTTPS by default.** nginx serves 443 with HSTS and redirects 80. Put the certificate into `nginx/certs/`
  (or `scripts/install.sh --self-signed`). Plain HTTP only with `HORUS_PROXY_MODE=http-dev` (development).
- **Policies.** Shipped policies are inside the image. `./policies` is now mounted as an override directory
  (`/app/policy-overrides`): only changed files are needed (deep-merged); a full copy of the old directory still
  works but freezes the shipped defaults - keep only real changes.
- **Ansible / automation files** are no longer bind-mounted from the host; they come from the image.
- **Networks.** PostgreSQL and Redis moved to an internal `data` network; the frontend network is internal; only
  nginx publishes ports.
- **Bundled Wazuh 4.14.8 on linux/amd64 and linux/arm64.** `docker-compose.wazuh.yml` replaces
  `docker-compose.full.yml` and now runs Wazuh 4.14.8 (manager, indexer, dashboard) with certificate generator 0.0.4 -
  all multi-arch, no `platform: linux/amd64` pin (Wazuh 4.9.2 / generator 0.0.2 were amd64-only: `exec format error`
  on ARM64). Install with `./scripts/install.sh --with-wazuh`: it stores `COMPOSE_FILE=docker-compose.wazuh.yml` in
  `.env` and writes the indexer user hashes of your `.env` passwords once (the published Wazuh default hashes are
  gone). The indexer configuration, security files and certificates moved to `/usr/share/wazuh-indexer/config/`.
- **Platform check.** `install.sh`, `update.sh` and `wazuh-init.sh` read the platform of the Docker daemon (remote
  contexts work) and stop before pulling unless every image of the stack offers it (no emulation fallback).

## New: Domain monitoring

**Domain Monitoring** (menu: Operations) checks domains and HTTP(S) addresses from the Horus server: reachability,
response time, time-weighted uptime for 24 h / 7 d / 30 d with measurement coverage (unmeasured time is never counted
as available), outages and TLS certificates (expiry, issuer, chain and host-name verification). Checks run in the
workers with bounded concurrency; SSRF protection blocks internal, link-local and cloud metadata addresses
(IPv4 / IPv6, DNS rebinding, redirects) unless an administrator allowlists internal networks. Notifications on
outage (after 3 failed checks by default), recovery and certificate expiry at 30 / 14 / 7 / 3 / 1 days. New
permissions `monitors:read` / `monitors:manage`. Raw results are kept 90 days (`HORUS_MONITOR_RETENTION_DAYS`), daily
summaries as long as the monitor exists. Guide: `docs/en/domain-monitoring.md`.

## Migration changes

Schema head: `0030`.
- `0029` backup policies: database engine of a dump.
- `0030` domain monitoring: five new tables (`domain_monitors`, `domain_monitor_checks`, `domain_monitor_outages`,
  `domain_monitor_hourly`, `domain_monitor_daily`); existing tables and data are not changed.

Installations on an older schema are migrated forward automatically when the `api` container starts.

## Security fixes

- Backend runtime image moved to Debian 13; OpenSSH client 10.6p1 built from the signed upstream release
  (Debian's 10.0p1 carries CVE-2026-60002, a client use-after-free reachable from managed hosts).
- No CRITICAL vulnerabilities in either image; remaining HIGH findings are unfixed upstream and not reachable in
  the hardened containers (reviewed list shipped with the release).
- Horus business logic is shipped as compiled native modules; images contain no tests, compilers, source maps,
  keys or credentials (audited per release).
- Images are signed (Cosign keyless) and carry CycloneDX SBOM attestations.
- Native agent binaries (`horus-agent-1.0.0-linux-amd64|arm64`) with SHA-256 checksums; per-asset revocable
  tokens as before.

## Upgrade notes (from a source-based 0.9.x deployment)

1. `scripts/backup.sh` in the old checkout (database + secrets volume + `.env`).
2. `docker compose down` in the old checkout (volumes are kept).
3. Clone the deployment repository, `cp .env.example .env`, copy your secrets and settings from the old `.env`
   (keep the image references of the new `.env.example`), add a TLS certificate, move real policy changes into
   `policies/`.
4. `./scripts/install.sh`. The deployment uses the same volume names (`horus_*`), so the existing database,
   secrets and metrics are picked up; `scripts/restore.sh <backup>` restores onto a fresh host instead.

## Upgrade notes (bundled Wazuh 4.9.2 → 4.14.8)

Check out the new deployment files, then `./scripts/update.sh <version> <backend digest> <frontend digest>`. When the
running `wazuh-manager` image differs, `update.sh` stops Wazuh and copies all Wazuh volumes with
`scripts/wazuh-backup.sh` before the new images start; certificates and passwords are kept. Indexer data and manager
databases are migrated forward and cannot be downgraded - the way back is `scripts/wazuh-restore.sh` with that backup
and the previous deployment files. A Wazuh stack started by hand with `-f docker-compose.wazuh.yml` is adopted
(`COMPOSE_FILE` is added to `.env`); `install.sh --with-wazuh` backs up a running Wazuh of another version as well.

## Rollback notes

This release adds migrations (0029, 0030): an older image does not know the schema, so going back to a previous
release needs `scripts/rollback.sh --with-backup` (restores the backup `update.sh` took before the update; changes
made after the update - including domain monitoring data - are lost).
