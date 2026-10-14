#!/bin/sh
# Bundled Wazuh only: put back the Wazuh data volumes from a scripts/wazuh-backup.sh directory - the way back after a
# failed Wazuh upgrade (indexer data and manager databases cannot be downgraded in place).
#
#   ./scripts/wazuh-restore.sh backups/wazuh-<timestamp>
#
# Run it from the CURRENT checkout (older releases do not ship this script). The Wazuh services are stopped, each
# volume in the backup is emptied and refilled, and NOTHING is started. Then check out the deployment files of the
# release the backup was taken with (MANIFEST lists its images) and start that release - starting the current files
# instead would migrate the restored data forward again.
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh

SRC=${1:?usage: wazuh-restore.sh <backup directory>}
[ -f "$SRC/MANIFEST" ] || die "$SRC/MANIFEST missing - not a scripts/wazuh-backup.sh directory"
project=$($DC config | sed -n 's/^name: *//p' | head -n 1)
grep -qx "project=$project" "$SRC/MANIFEST" || die "the backup belongs to another compose project ($(sed -n 's/^project=//p' "$SRC/MANIFEST"))"
want=$(sed -n 's/^image wazuh-manager=//p' "$SRC/MANIFEST")

log "stopping the Wazuh services"
$DC stop wazuh-dashboard wazuh-manager wazuh-indexer >/dev/null
for f in "$SRC"/*.tar.gz; do
  key=$(basename "$f" .tar.gz)
  name=$(docker volume ls -q --filter "label=com.docker.compose.project=$project" \
    --filter "label=com.docker.compose.volume=$key" | head -n 1)
  name=${name:-${project}_$key}
  docker volume inspect "$name" >/dev/null 2>&1 \
    || docker volume create --label "com.docker.compose.project=$project" \
         --label "com.docker.compose.volume=$key" "$name" >/dev/null
  docker run --rm -i --network none -v "$name:/v" alpine:3.24.2 \
    sh -c 'find /v -mindepth 1 -delete && tar -C /v -xzf -' < "$f" || die "restoring $name failed"
  log "  $key -> $name"
done
log "Wazuh volumes restored from $SRC (Wazuh is stopped). The backup was taken with ${want:-an unrecorded image}:"
log "check out the deployment files of that release, then start it (docker compose up -d)"
