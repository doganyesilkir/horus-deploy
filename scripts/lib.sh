#!/bin/sh
# Shared helpers of the Horus deployment scripts (sourced, not executed). Never prints secret values.
set -eu

DC=${HORUS_COMPOSE:-docker compose}
ENV_FILE=${HORUS_ENV_FILE:-.env}
# shellcheck disable=SC2034  # used by the scripts that source this file
STATE_FILE=${HORUS_STATE_FILE:-.horus-deployments}

log()  { printf '[horus] %s\n' "$*"; }
warn() { printf '[horus] WARNING: %s\n' "$*" >&2; }
die()  { printf '[horus] ERROR: %s\n' "$*" >&2; exit 1; }

# value of KEY in .env (last assignment wins, surrounding quotes removed) - never echoed by callers for secrets
env_get() {
  [ -f "$ENV_FILE" ] || return 0
  sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1 | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}

# replace or append KEY=VALUE in .env. The value is written verbatim - any character (|, $, \, &, regexp syntax such
# as the signing identity policy) is safe: it reaches awk through the environment, never through a sed/awk program.
env_set() {
  case "$2" in *"
"*) die "env_set $1: value must be a single line" ;; esac
  tmp=$(mktemp "$ENV_FILE.XXXXXX")
  ENV_SET_KEY=$1 ENV_SET_VALUE=$2 awk '
    BEGIN { k = ENVIRON["ENV_SET_KEY"]; v = ENVIRON["ENV_SET_VALUE"]; done = 0 }
    index($0, k "=") == 1 { if (!done) print k "=" v; done = 1; next }
    { print }
    END { if (!done) print k "=" v }' "$ENV_FILE" > "$tmp"
  cat "$tmp" > "$ENV_FILE" && rm -f "$tmp"
  [ "$(env_get "$1")" = "$2" ] || die "env_set $1: value was not stored verbatim"
}

require_tools() {
  command -v docker >/dev/null 2>&1 || die "docker is not installed"
  $DC version >/dev/null 2>&1 || die "docker compose v2 is required"
  v=$($DC version --short 2>/dev/null | sed 's/^v//')
  major=${v%%.*}; rest=${v#*.}; minor=${rest%%.*}
  if [ "${major:-0}" -lt 2 ] || { [ "$major" -eq 2 ] && [ "${minor:-0}" -lt 24 ]; }; then
    die "docker compose >= 2.24 required (found $v)"
  fi
}

# image references of a release: <HORUS_IMAGE>:backend-<version>[@digest] / :frontend-<version>[@digest]
image_ref() {   # $1 = backend|frontend, $2 = version, $3 = digest (optional)
  printf '%s:%s-%s%s' "$(env_get HORUS_IMAGE)" "$1" "$2" "${3:+@$3}"
}
backend_ref()  { image_ref backend  "$(env_get HORUS_VERSION)" "$(env_get HORUS_BACKEND_DIGEST)"; }
frontend_ref() { image_ref frontend "$(env_get HORUS_VERSION)" "$(env_get HORUS_FRONTEND_DIGEST)"; }

# The Cosign identity policy of Horus releases (canonical producer: release/signing_identity.py in the build
# pipeline; value published in release-manifest.json signature.identity). Only that exact shape is accepted: anchored
# on both ends, escaped literals, release.yml of one GitHub repository, version tags only. Fails closed.
# shellcheck disable=SC2034  # used by verify-signatures.sh, which sources this file
SIGNING_ISSUER=https://token.actions.githubusercontent.com
check_signing_identity() {
  id=$1
  [ -n "$id" ] || die "HORUS_SIGNING_IDENTITY is not set (release-manifest.json: signature.identity)"
  case "$id" in
    '^https://github\.com/'*'/\.github/workflows/release\.yml@refs/tags/v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc\.[1-9][0-9]*)?$') : ;;
    *) die "HORUS_SIGNING_IDENTITY is not a Horus release identity policy (copy signature.identity from release-manifest.json)" ;;
  esac
  repo=${id#'^https://github\.com/'}; repo=${repo%%'/\.github/workflows/'*}
  # owner/repo with every "." escaped (an unescaped dot would be a regexp wildcard)
  printf '%s' "$repo" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9-]{0,38}/([A-Za-z0-9_-]|\\\.){1,100}$' \
    || die "HORUS_SIGNING_IDENTITY names an invalid repository: $repo"
}

check_version() {
  case "$1" in
    "") die "HORUS_VERSION is empty in $ENV_FILE" ;;
    latest|*[!0-9A-Za-z.-]*) die "HORUS_VERSION=$1 - use an exact release version (e.g. 1.0.0)" ;;
  esac
}

check_images() {
  img=$(env_get HORUS_IMAGE)
  case "$img" in
    ""|*"<"*|*">"*) die "HORUS_IMAGE is not set in $ENV_FILE (<dockerhub_username>/horus)" ;;
    *@*) die "HORUS_IMAGE must not contain a digest (use HORUS_BACKEND_DIGEST / HORUS_FRONTEND_DIGEST)" ;;
  esac
  case "${img##*/}" in   # a registry may have a port (host:5000/user/horus); the repository name has no tag
    *:*) die "HORUS_IMAGE must not contain a tag (tags are backend-<version> / frontend-<version>)" ;;
  esac
  check_version "$(env_get HORUS_VERSION)"
  for d in HORUS_BACKEND_DIGEST HORUS_FRONTEND_DIGEST; do
    v=$(env_get "$d")
    case "$v" in "") warn "$d empty - image not digest pinned (see release-manifest.json)" ;;
                 sha256:*) : ;; *) die "$d must look like sha256:<hex>" ;; esac
  done
}

preflight() {
  require_tools
  [ -f "$ENV_FILE" ] || die "$ENV_FILE missing - cp .env.example .env and fill it in"
  perms=$(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%Lp' "$ENV_FILE")
  case "$perms" in 600|400) : ;; *) warn "$ENV_FILE is mode $perms - run: chmod 600 $ENV_FILE" ;; esac
  check_images
  cpus=$(env_get HORUS_WORKER_CPUS); cpus=${cpus:-2.0}
  ncpu=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
  awk -v a="$cpus" -v b="$ncpu" 'BEGIN { exit !(a > b) }' && die "HORUS_WORKER_CPUS=$cpus exceeds the host's $ncpu CPUs"
  mode=$(env_get HORUS_PROXY_MODE); mode=${mode:-https}
  case "$mode" in
    https)
      [ -s nginx/certs/fullchain.pem ] && [ -s nginx/certs/privkey.pem ] \
        || die "HTTPS mode needs nginx/certs/fullchain.pem and privkey.pem (or: scripts/install.sh --self-signed)" ;;
    http-dev) warn "HORUS_PROXY_MODE=http-dev: NO TLS - development / isolated lab only" ;;
    *) die "HORUS_PROXY_MODE must be https or http-dev" ;;
  esac
  free_kb=$(df -Pk . | awk 'NR==2 {print $4}')
  [ "${free_kb:-0}" -gt 5242880 ] || warn "less than 5 GB free on $(pwd)"
  $DC config --quiet || die "docker compose configuration is invalid"
}

# image digests of the running deployment (for rollback records)
running_refs() {
  for svc in api frontend; do
    cid=$($DC ps -q "$svc" 2>/dev/null | head -n 1)
    [ -n "$cid" ] || continue
    img=$(docker inspect -f '{{.Image}}' "$cid")
    repo=$(docker image inspect -f '{{join .RepoDigests " "}}' "$img" 2>/dev/null | cut -d' ' -f1)
    printf '%s=%s\n' "$svc" "${repo:-$img}"
  done
}

wait_healthy() {
  timeout=${1:-300}; start=$(date +%s)
  log "waiting for services to become healthy (max ${timeout}s)"
  while :; do
    bad=$($DC ps --format '{{.Service}}|{{.Health}}|{{.State}}' \
      | awk -F'|' '$1 != "horus-init" && ($2 == "unhealthy" || $2 == "starting" || $3 != "running") {print $1}')
    [ -z "$bad" ] && return 0
    [ $(( $(date +%s) - start )) -lt "$timeout" ] || { warn "not healthy: $bad"; return 1; }
    sleep 5
  done
}

# Alembic revision stored in the database ("" when the database is empty / not reachable)
db_revision() {
  $DC exec -T postgres psql -X -A -t -U horus -d horus -c "SELECT version_num FROM alembic_version" 2>/dev/null \
    | tr -d '[:space:]' || true
}

# does IMAGE know the given Alembic revision?
image_knows_revision() {
  [ -n "$2" ] || return 0
  docker run --rm --network none --entrypoint sh "$1" -c 'ls /app/alembic/versions' \
    | sed -n 's/^\([0-9A-Za-z]*\)_.*\.py$/\1/p' | grep -qx "$2"
}
