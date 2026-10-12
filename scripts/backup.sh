#!/bin/sh
# Back up the Horus database and the secrets volume (the master key is
# required to decrypt stored SSH keys - keep backups encrypted and offline).
set -eu
DC=${HORUS_COMPOSE:-docker compose}      # see scripts/restore.sh
PROJECT=${HORUS_PROJECT:-horus}
TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT_DIR=${1:-backups}
mkdir -p "$OUT_DIR"
TMP=$(mktemp -d "$OUT_DIR/.tmp.XXXXXX")  # inside a bind-mountable path (Docker Desktop/Colima)
trap 'rm -rf "$TMP"' EXIT
echo "[backup] dumping PostgreSQL"
$DC exec -T postgres pg_dump -U horus -d horus --format=custom > "$TMP/horus.dump"
echo "[backup] copying secrets volume"
docker run --rm -v "${PROJECT}_secrets:/secrets:ro" -v "$(cd "$TMP" && pwd):/out" alpine:3.24.2 tar -C /secrets -czf /out/secrets.tar.gz .
# the deployment configuration (.env: database / JWT / integration secrets, image versions) is needed to rebuild the
# same platform - the archive therefore contains secrets: keep it encrypted and offline
ENV_FILE=${HORUS_ENV_FILE:-.env}
FILES="horus.dump secrets.tar.gz"
if [ -f "$ENV_FILE" ]; then
  cp "$ENV_FILE" "$TMP/env" && chmod 600 "$TMP/env" && FILES="$FILES env"
  echo "[backup] including $ENV_FILE"
else
  echo "[backup] WARNING: $ENV_FILE not found - the deployment configuration is NOT in this backup" >&2
fi
tar -C "$TMP" -czf "$OUT_DIR/horus-$TS.tar.gz" $FILES
chmod 600 "$OUT_DIR/horus-$TS.tar.gz"
echo "[backup] written $OUT_DIR/horus-$TS.tar.gz"
