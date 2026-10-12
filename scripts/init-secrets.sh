#!/bin/sh
# -----------------------------------------------------------------------------
# Horus secret bootstrap (runs in the one-shot `horus-init` container).
#
# For every secret:
#   1. if the corresponding environment variable is set  -> use it
#   2. else if the secret file already exists              -> keep it
#   3. else                                               -> generate random
#
# Secrets live only in the `horus_secrets` Docker volume.
# -----------------------------------------------------------------------------
set -eu
umask 0022
DIR=/secrets
mkdir -p "$DIR"

rand() {
  # $1 = number of random bytes; URL-safe base64 without padding
  head -c "$1" /dev/urandom | base64 | tr -d '\n=' | tr '+/' '-_'
}

ensure() {
  name="$1"; value="$2"; bytes="$3"
  file="$DIR/$name"
  if [ -n "$value" ]; then
    printf '%s' "$value" > "$file.tmp" && mv "$file.tmp" "$file"
    echo "[init] $name: taken from environment"
  elif [ -s "$file" ]; then
    echo "[init] $name: keeping existing value"
  else
    rand "$bytes" > "$file.tmp" && mv "$file.tmp" "$file"
    echo "[init] $name: generated"
  fi
  # Files are world-readable *inside* the volume because the consuming
  # containers run under different non-root UIDs. The volume itself is only
  # mounted (read-only) into Horus containers.
  chmod 0444 "$file"
}

ensure master_key             "${HORUS_MASTER_KEY:-}"     48
ensure jwt_secret             "${HORUS_JWT_SECRET:-}"     48
ensure postgres_password      "${POSTGRES_PASSWORD:-}"       32
ensure redis_password         "${REDIS_PASSWORD:-}"          32
ensure grafana_admin_password "${GRAFANA_ADMIN_PASSWORD:-}"  24
ensure ingest_token           "${HORUS_INGEST_TOKEN:-}"   32

# Redis configuration (password must not appear on the command line)
cat > "$DIR/redis.conf.tmp" <<EOF
bind 0.0.0.0
protected-mode yes
port 6379
dir /data
appendonly yes
appendfsync everysec
maxmemory 400mb
maxmemory-policy noeviction
rename-command FLUSHALL ""
rename-command FLUSHDB ""
rename-command CONFIG ""
rename-command DEBUG ""
requirepass $(cat "$DIR/redis_password")
EOF
mv "$DIR/redis.conf.tmp" "$DIR/redis.conf"
chmod 0444 "$DIR/redis.conf"
echo "[init] secrets ready"
