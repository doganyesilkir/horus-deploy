#!/bin/sh
# Restore a backup created by scripts/backup.sh - also on a NEW host (fresh volumes).
#
#   scripts/restore.sh backups/horus-<ts>.tar.gz
#
# 1. the archive is checked (both members present, the dump is readable) before anything is stopped
# 2. the secrets volume is restored; PostgreSQL's role password is set to the restored secret (a new host's
#    data directory was initialised with a different, generated one)
# 3. the dump is restored into a separate database in ONE transaction, stopping at the first error
#    (no half-restored database, no tables of newer migrations left behind)
# 4. the schema version must be known to this Horus image (a backup from a newer release is refused)
# 5. only then the restored database replaces the current one; the previous one is kept as
#    horus_pre_restore_<ts> (drop it once the restore has been checked)
#
# HORUS_COMPOSE (default "docker compose") and HORUS_PROJECT (default "horus", the volume prefix) allow
# running against another compose project (disposable test deployments).
set -eu
FILE=${1:?usage: restore.sh backups/horus-<ts>.tar.gz}
DC=${HORUS_COMPOSE:-docker compose}
PROJECT=${HORUS_PROJECT:-horus}
TS=$(date -u +%Y%m%dt%H%M%Sz)          # lower case: the database name is an unquoted identifier
mkdir -p backups
TMP=$(mktemp -d "backups/.restore.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

psql_admin() { $DC exec -T postgres psql -v ON_ERROR_STOP=1 -X -q -U horus -d postgres "$@"; }

echo "[restore] checking the archive"
tar -C "$TMP" -xzf "$FILE"
for m in horus.dump secrets.tar.gz; do
  [ -s "$TMP/$m" ] || { echo "[restore] ERROR: $m missing in $FILE - nothing changed" >&2; exit 1; }
done
tar -tzf "$TMP/secrets.tar.gz" | grep -q 'postgres_password' || {
  echo "[restore] ERROR: secrets archive has no postgres_password - nothing changed" >&2; exit 1; }
if [ -s "$TMP/env" ]; then
  echo "[restore] note: the archive also contains the deployment configuration ('env'); it is NOT applied" \
       "automatically - compare it with your .env (tar -xzf $FILE env)"
fi

echo "[restore] stopping application containers"
$DC stop api worker worker-periodic beat

echo "[restore] restoring secrets volume ${PROJECT}_secrets"
docker run --rm -v "${PROJECT}_secrets:/secrets" -v "$(cd "$TMP" && pwd):/in:ro" alpine:3.24.2 \
  sh -c "find /secrets -mindepth 1 -delete && tar -C /secrets -xzf /in/secrets.tar.gz"
$DC up -d --force-recreate postgres redis

echo "[restore] waiting for PostgreSQL"
i=0
until $DC exec -T postgres pg_isready -U horus -d postgres >/dev/null 2>&1; do
  i=$((i + 1)); [ "$i" -lt 60 ] || { echo "[restore] ERROR: PostgreSQL not ready" >&2; exit 1; }
  sleep 2
done

echo "[restore] aligning the database role password with the restored secret"
# local socket connection (trust inside the container); the password never appears on a command line
$DC exec -T postgres sh -c 'printf "%s\n" "ALTER ROLE horus PASSWORD :'"'"'pw'"'"';" | \
  psql -v ON_ERROR_STOP=1 -X -q -U horus -d postgres -v pw="$(cat /run/horus-secrets/postgres_password)"'

echo "[restore] restoring the dump into horus_restore (single transaction, stop on error)"
psql_admin -c "DROP DATABASE IF EXISTS horus_restore" -c "CREATE DATABASE horus_restore OWNER horus"
if ! $DC exec -T postgres pg_restore -U horus -d horus_restore --no-owner --single-transaction --exit-on-error \
    < "$TMP/horus.dump"; then
  psql_admin -c "DROP DATABASE IF EXISTS horus_restore"
  echo "[restore] ERROR: pg_restore failed - the current database was NOT changed" >&2
  $DC up -d api worker worker-periodic beat
  exit 1
fi

echo "[restore] checking the schema version against this image"
VERSION=$($DC exec -T postgres psql -X -A -t -U horus -d horus_restore -c "SELECT version_num FROM alembic_version" | tr -d '[:space:]')
KNOWN=$($DC run --rm --no-deps -T --entrypoint sh api -c "ls /app/alembic/versions" | sed -n 's/^\([0-9A-Za-z]*\)_.*\.py$/\1/p')
if [ -z "$VERSION" ] || ! printf '%s\n' "$KNOWN" | grep -qx "$VERSION"; then
  psql_admin -c "DROP DATABASE IF EXISTS horus_restore"
  echo "[restore] ERROR: backup schema version '${VERSION:-none}' is unknown to this Horus image (newer release?)." >&2
  echo "[restore]        The current database was NOT changed." >&2
  $DC up -d api worker worker-periodic beat
  exit 1
fi

echo "[restore] switching databases (previous one kept as horus_pre_restore_$TS)"
psql_admin -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname IN ('horus', 'horus_restore') AND pid <> pg_backend_pid()" \
  -c "ALTER DATABASE horus RENAME TO horus_pre_restore_$TS" \
  -c "ALTER DATABASE horus_restore RENAME TO horus"

echo "[restore] starting application containers (older schemas are migrated on start)"
$DC up -d api worker worker-periodic beat
echo "[restore] done. After checking the restored data: DROP DATABASE horus_pre_restore_$TS"
