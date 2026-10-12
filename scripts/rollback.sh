#!/bin/sh
# Roll back to the images recorded by the last update (scripts/update.sh writes .horus-deployments).
#
#   ./scripts/rollback.sh                 # images only - allowed when the schema did not change
#   ./scripts/rollback.sh --with-backup   # also restore the pre-update backup (schema changed; data written
#                                         # after the update is lost)
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh

WITH_BACKUP=false
[ "${1:-}" = "--with-backup" ] && WITH_BACKUP=true
[ -f "$STATE_FILE" ] || die "$STATE_FILE missing - no recorded previous release"

last=$(awk '/ update from$/ {n=NR} END {print n}' "$STATE_FILE")
[ -n "$last" ] || die "no update recorded in $STATE_FILE"
get() { sed -n "$((last + 1)),$((last + 8))p" "$STATE_FILE" | sed -n "s/^  $1=//p" | head -n 1; }
old_version=$(get HORUS_VERSION); old_bd=$(get HORUS_BACKEND_DIGEST); old_fd=$(get HORUS_FRONTEND_DIGEST)
old_rev=$(get db_revision); backup=$(get backup)
[ -n "$old_version" ] || die "incomplete record in $STATE_FILE"
old_backend=$(image_ref backend "$old_version" "$old_bd")
old_frontend=$(image_ref frontend "$old_version" "$old_fd")

cur_rev=$(db_revision)
log "previous release: $old_backend (schema ${old_rev}); database now at ${cur_rev:-none}"
if [ "$WITH_BACKUP" = false ] && ! image_knows_revision "$old_backend" "$cur_rev"; then
  die "the schema was migrated to $cur_rev, which the previous release does not know. Re-run with --with-backup
       (restores $backup; changes made after the update are lost)."
fi

env_set HORUS_VERSION "$old_version"
env_set HORUS_BACKEND_DIGEST "$old_bd"
env_set HORUS_FRONTEND_DIGEST "$old_fd"
docker pull --quiet "$old_backend" >/dev/null
docker pull --quiet "$old_frontend" >/dev/null
if [ "$WITH_BACKUP" = true ]; then
  [ -s "$backup" ] || die "backup $backup not found"
  scripts/restore.sh "$backup"
fi
$DC up -d
wait_healthy 600 && scripts/verify.sh
printf '%s rollback to %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$old_backend" >> "$STATE_FILE"
log "rolled back to $old_backend"
