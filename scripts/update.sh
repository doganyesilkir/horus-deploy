#!/bin/sh
# Controlled update to a new Horus release:
#   preflight -> platform check -> pull + signature check -> schema check -> backup -> record current release
#   -> [bundled Wazuh version change: stop Wazuh + volume backup] -> start -> verify
#
# Check out the deployment files of the new release first (git checkout v<version>): they carry the image versions of
# the bundled Wazuh too. The same command works on linux/amd64 and linux/arm64 (multi-arch images, no emulation).
#
#   ./scripts/update.sh <version> [<backend digest> <frontend digest>]
#   e.g. ./scripts/update.sh 1.1.0 sha256:... sha256:...     (digests from the release's release-manifest.json)
#
# Database migrations run forward on start. They are NOT reversible automatically: a rollback to an older release
# after a schema change needs the backup this script writes first (scripts/rollback.sh tells you when).
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh

NEW_VERSION=${1:?usage: update.sh <version> [<backend digest> <frontend digest>]}
NEW_BD=${2:-}; NEW_FD=${3:-}
check_version "$NEW_VERSION"
wazuh_adopt
preflight
new_backend=$(image_ref backend "$NEW_VERSION" "$NEW_BD")
new_frontend=$(image_ref frontend "$NEW_VERSION" "$NEW_FD")
# every image of the NEW release (Horus + third-party + bundled Wazuh) must exist for the Docker host's platform
# shellcheck disable=SC2046  # one image reference per word
check_platforms $(HORUS_VERSION="$NEW_VERSION" HORUS_BACKEND_DIGEST="$NEW_BD" HORUS_FRONTEND_DIGEST="$NEW_FD" compose_images)
if wazuh_enabled; then wazuh_preflight; fi

log "pulling $new_backend and $new_frontend"
docker pull --quiet "$new_backend" >/dev/null
docker pull --quiet "$new_frontend" >/dev/null
if command -v cosign >/dev/null 2>&1 && [ -n "$NEW_BD" ] && [ -n "$NEW_FD" ]; then
  HORUS_VERSION="$NEW_VERSION" HORUS_BACKEND_DIGEST="$NEW_BD" HORUS_FRONTEND_DIGEST="$NEW_FD" \
    scripts/verify-signatures.sh || die "signature verification failed - nothing changed"
else
  warn "image signatures NOT verified (needs cosign and the two digests)"
fi

rev=$(db_revision)
log "database schema revision: ${rev:-none}"
image_knows_revision "$new_backend" "$rev" \
  || die "the new backend image does not know schema revision $rev (downgrade?) - nothing changed"

log "backup before update"
scripts/backup.sh backups

{
  printf '%s update from\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  HORUS_VERSION=%s\n  HORUS_BACKEND_DIGEST=%s\n  HORUS_FRONTEND_DIGEST=%s\n  db_revision=%s\n  backup=%s\n' \
    "$(env_get HORUS_VERSION)" "$(env_get HORUS_BACKEND_DIGEST)" "$(env_get HORUS_FRONTEND_DIGEST)" "${rev:-none}" \
    "$(ls -t backups/horus-*.tar.gz | head -n 1)"
  running_refs | sed 's/^/  running /'
} >> "$STATE_FILE"

# a Wazuh version change: stop Wazuh and copy its volumes (the only way back, scripts/wazuh-restore.sh)
if wazuh_enabled; then wazuh_backup_before_upgrade; fi

env_set HORUS_VERSION "$NEW_VERSION"
env_set HORUS_BACKEND_DIGEST "$NEW_BD"
env_set HORUS_FRONTEND_DIGEST "$NEW_FD"
log "starting the new release (migrations run in the api container)"
$DC up -d
if wazuh_enabled; then timeout=1200; else timeout=600; fi
if ! wait_healthy "$timeout" || ! scripts/verify.sh; then
  warn "the new release is not healthy. The previous release and backup are recorded in $STATE_FILE"
  die "roll back with: scripts/rollback.sh"
fi
log "update complete: $(backend_ref)"
