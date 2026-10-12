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
- **Bundled Wazuh.** `docker-compose.wazuh.yml` replaces `docker-compose.full.yml`. Run `scripts/wazuh-init.sh`
  once: the indexer users get hashes of your `.env` passwords (the published Wazuh default hashes are gone).

## Migration changes

Schema head: `0028` (no new migration compared to the last source deployment at 0028). Installations on an older
schema are migrated forward automatically when the `api` container starts.

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

## Rollback notes

No schema change versus 0.9.x at revision 0028: rolling back the images is possible without restoring data
(`scripts/rollback.sh`). For releases that add migrations, the notes will say so and rollback needs
`scripts/rollback.sh --with-backup` (the pre-update backup; later changes are lost).
