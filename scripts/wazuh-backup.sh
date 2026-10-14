#!/bin/sh
# Bundled Wazuh only: consistent copy of every Wazuh data volume (indexer data, manager configuration, databases,
# queues, agent keys, filebeat state, dashboard configuration) into <dir>/wazuh-<UTC timestamp>/.
#
#   ./scripts/wazuh-backup.sh [dir]          (default: backups; scripts/update.sh runs it before a Wazuh upgrade)
#
# Order: measure the volumes and check the free space of <dir> (before anything is stopped) -> stop the Wazuh services
# (an indexer copied while running is not consistent) -> one gzip archive per volume into <dir>/.wazuh-<ts>.partial ->
# rename to <dir>/wazuh-<ts> only when every volume was copied. On any failure the partial directory is removed, the
# exit code is non-zero and the stopped containers are started again - unless the deployment files already belong to
# another Wazuh version (an upgrade in progress): then Wazuh stays stopped (see the message). After a successful backup
# the services stay stopped: scripts/update.sh starts the new release, otherwise run `docker compose up -d`.
#
# Unix sockets in the manager volumes (queue/sockets, queue/alerts/ar ...) are runtime endpoints, not data: tar skips
# them ("socket ignored"); only that message is filtered, every other tar / Docker / disk error fails the backup.
# The archives contain agent keys and the indexer data - store them like the .env file. wazuh/certs and
# wazuh/config/wazuh_indexer/internal_users.yml are files of this directory and are not changed by an upgrade.
# Works with remote Docker contexts: the data is streamed from the Docker host, nothing is bind-mounted.
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh

DIR=${1:-backups}
project=$($DC config | sed -n 's/^name: *//p' | head -n 1)
keys=$($DC config --volumes | grep -E '^(wazuh_|filebeat_)' || true)
[ -n "$keys" ] || die "no Wazuh volumes in the compose configuration - is COMPOSE_FILE=$WAZUH_COMPOSE set in $ENV_FILE?"

volume_of() {
  docker volume ls -q --filter "label=com.docker.compose.project=$project" \
    --filter "label=com.docker.compose.volume=$1" | head -n 1
}

# --- free space: checked while Wazuh still runs, so a full disk never leaves it stopped -----------------------------
umask 077
mkdir -p "$DIR"
total_kb=0
for key in $keys; do
  name=$(volume_of "$key")
  [ -n "$name" ] || continue
  kb=$(docker run --rm --network none -v "$name:/v:ro" alpine:3.24.2 du -sk /v | cut -f1) \
    || die "cannot measure volume $name"
  total_kb=$((total_kb + kb))
done
avail_kb=$(df -Pk "$DIR" | awk 'NR == 2 {print $4}')
# upper bound: the uncompressed volume size (gzip never makes these archives meaningfully larger) + 5 % + 512 MiB
need_kb=$((total_kb + total_kb / 20 + 524288))
log "Wazuh volumes: $((total_kb / 1024)) MiB uncompressed; free in $DIR: $((avail_kb / 1024)) MiB"
if [ "${HORUS_WAZUH_BACKUP_SPACE_CHECK:-1}" != 0 ] && [ "$avail_kb" -lt "$need_kb" ]; then
  die "insufficient disk space for the Wazuh backup in $DIR - required (upper bound): $((need_kb / 1024)) MiB, \
available: $((avail_kb / 1024)) MiB. Nothing was stopped. Free space or pass another directory; the archives are \
compressed and usually smaller (HORUS_WAZUH_BACKUP_SPACE_CHECK=0 skips this check at your own risk)."
fi

ts=$(date -u +%Y%m%dT%H%M%SZ)
out="$DIR/wazuh-$ts"
partial="$DIR/.wazuh-$ts.partial"
stopped=false
done_ok=false
cleanup() {
  [ "$done_ok" = true ] && return 0
  rm -rf "$partial"
  [ "$stopped" = true ] && [ -n "$running" ] || return 0
  if [ "$same_version" = true ]; then
    # exactly the containers this script stopped, without compose dependency handling
    warn "Wazuh backup failed - starting the stopped Wazuh containers again (unchanged)"
    # shellcheck disable=SC2086  # container ids
    docker start $running >/dev/null || warn "could not start the Wazuh containers - run: docker compose up -d"
  else
    # the deployment files already belong to another Wazuh version (upgrade): the old containers would mount the NEW
    # configuration files and fail - and starting the new version without a backup is what this script prevents
    warn "Wazuh backup failed - Wazuh stays STOPPED: these deployment files use $compose_manager, the stopped \
containers run $running_manager. Free space and repeat the update, or check out the previous deployment files and run \
docker compose up -d."
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$partial"
running=""
for svc in wazuh-indexer wazuh-manager wazuh-dashboard; do      # start order on failure: indexer first
  cid=$($DC ps -q --status running "$svc" | head -n 1)
  running="$running${cid:+ $cid}"
done
compose_manager=$($DC config --images | grep '^wazuh/wazuh-manager:' | head -n 1)
cid=$($DC ps -q wazuh-manager | head -n 1)
running_manager=$( [ -n "$cid" ] && docker inspect -f '{{.Config.Image}}' "$cid" || echo none)
same_version=false
[ "$running_manager" = "$compose_manager" ] && same_version=true
log "stopping the Wazuh services for a consistent copy"
stopped=true
$DC stop wazuh-dashboard wazuh-manager wazuh-indexer >/dev/null

{
  printf 'project=%s\ncreated=%s\n' "$project" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for svc in wazuh-manager wazuh-indexer wazuh-dashboard; do
    cid=$($DC ps -aq "$svc" | head -n 1)
    [ -z "$cid" ] || printf 'image %s=%s\n' "$svc" "$(docker inspect -f '{{.Config.Image}}' "$cid")"
  done
} > "$partial/MANIFEST"

for key in $keys; do
  name=$(volume_of "$key")
  if [ -z "$name" ]; then
    warn "volume $key does not exist yet - skipped"
    continue
  fi
  rc=0
  docker run --rm --network none -v "$name:/v:ro" alpine:3.24.2 tar -C /v -czf - . \
    > "$partial/$key.tar.gz" 2> "$partial/.stderr" || rc=$?
  sed '/: socket ignored$/d' "$partial/.stderr" >&2              # every message except skipped sockets
  rm -f "$partial/.stderr"
  [ "$rc" -eq 0 ] || die "copying volume $name failed (exit $rc) - no backup written"
  gzip -t < "$partial/$key.tar.gz" 2>/dev/null || die "archive of volume $name is incomplete - no backup written"
  printf 'volume %s=%s %s\n' "$key" "$name" "$(wc -c < "$partial/$key.tar.gz" | tr -d ' ')" >> "$partial/MANIFEST"
  log "  $key ($name)"
done
mv "$partial" "$out"
done_ok=true
log "Wazuh backup written to $out (Wazuh services are stopped)"
