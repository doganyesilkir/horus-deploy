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

# --- platform (CPU architecture) checks -----------------------------------------------------------------------
# What matters is the platform of the Docker DAEMON that runs the containers - it can be a remote context or
# DOCKER_HOST - never the uname of the machine running this script.
docker_platform() {
  p=$(docker version -f '{{.Server.Os}}/{{.Server.Arch}}' 2>/dev/null) \
    || die "cannot reach the Docker daemon (docker version failed; check the Docker context / DOCKER_HOST)"
  case "$p" in
    linux/amd64|linux/arm64) printf '%s\n' "$p" ;;
    */*) die "Docker host platform $p is not supported (Horus runs on linux/amd64 and linux/arm64)" ;;
    *) die "cannot determine the Docker host platform" ;;
  esac
}

# Registry lookup reference of an image: a digest-pinned name:tag@sha256:... becomes name@sha256:... (the tag is
# removed from the last path segment only - a registry host:port stays). `docker manifest inspect` resolves
# name:tag@digest by the TAG, so a pinned image whose tag does not exist (yet) - the release candidate checked before
# promote creates backend-<v> / frontend-<v> - failed with "no such manifest", and a moved tag was checked instead of
# the pinned digest. References without a digest are returned unchanged.
lookup_ref() {
  case "$1" in
    *@sha256:*)
      name=${1%@*}
      case "${name##*/}" in *:*) name=${name%:*} ;; esac
      printf '%s@%s\n' "$name" "${1##*@}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Runnable platforms (os/arch, one per line) of an image in its registry, looked up by digest when it is pinned.
# Attestation manifests (provenance / SBOM, platform unknown/unknown) are not runnable platforms and are skipped.
# Registry errors go to stderr, exit 1.
image_platforms() {
  ref=$(lookup_ref "$1")
  out=$(docker manifest inspect "$ref" 2>&1) || { printf '%s\n' "$out" | tail -n 1 >&2; return 1; }
  case "$out" in
    *'"manifests"'*) : ;;   # multi-arch index: one request lists every platform
    *) out=$(docker manifest inspect -v "$ref" 2>&1) || { printf '%s\n' "$out" | tail -n 1 >&2; return 1; } ;;
  esac
  printf '%s\n' "$out" | awk '
    /"platform": *\{/ { inp = 1; os = ""; arch = ""; next }
    inp && /"os": *"/           { v = $0; sub(/.*"os": *"/, "", v); sub(/".*/, "", v); os = v }
    inp && /"architecture": *"/ { v = $0; sub(/.*"architecture": *"/, "", v); sub(/".*/, "", v); arch = v }
    inp && /\}/ { inp = 0; if (os != "" && arch != "" && os != "unknown" && arch != "unknown") print os "/" arch }' \
    | sort -u
}

# images of the selected compose files (COMPOSE_FILE in .env adds docker-compose.wazuh.yml)
compose_images() { $DC config --images | sort -u; }

# Stop before anything is pulled or changed unless EVERY image offers the Docker host's platform. Emulation (QEMU /
# Rosetta) is never used as a fallback. With PLATFORM_LOCAL=true (--no-pull) an image already present locally is
# checked locally; everything else is checked in its registry. CHECK_PLATFORM=linux/<arch> checks another platform
# than the host's (CI: release/check_image_platforms.sh).
check_platforms() {
  if [ -n "${CHECK_PLATFORM:-}" ]; then want=$CHECK_PLATFORM; else want=$(docker_platform); fi
  log "platform $want: checking $# images"
  work=$(mktemp -d "${TMPDIR:-/tmp}/horus-platforms.XXXXXX")
  i=0
  for ref in "$@"; do   # registry lookups in parallel; results are evaluated in order below
    i=$((i + 1))
    printf '%s\n' "$ref" > "$work/$i.ref"
    if [ "${PLATFORM_LOCAL:-false}" = true ] \
       && docker image inspect -f '{{.Os}}/{{.Architecture}}' "$ref" > "$work/$i.out" 2>/dev/null; then
      : > "$work/$i.ok"
    else
      ( image_platforms "$ref" > "$work/$i.out" 2> "$work/$i.err" && : > "$work/$i.ok" ) &
    fi
  done
  wait
  problems=""
  n=0
  while [ "$n" -lt "$i" ]; do
    n=$((n + 1)); ref=$(cat "$work/$n.ref"); got=$(cat "$work/$n.out" 2>/dev/null || true)
    if [ ! -e "$work/$n.ok" ]; then
      problems="$problems
  $ref: registry check failed ($(head -n 1 "$work/$n.err" 2>/dev/null)) - docker login / network / tag?"
    elif [ -z "$got" ]; then
      problems="$problems
  $ref: no platform information in the registry"
    elif ! printf '%s\n' "$got" | grep -qx "$want"; then
      # shellcheck disable=SC2086  # list the available platforms on one line
      problems="$problems
  $ref: no $want image (available: $(printf '%s ' $got))"
    fi
  done
  rm -rf "$work"
  [ -z "$problems" ] || die "image platform check failed for $want - nothing was changed:$problems"
  log "all images provide $want"
}

# --- bundled Wazuh ----------------------------------------------------------------------------------------------
WAZUH_COMPOSE=docker-compose.wazuh.yml
wazuh_enabled() { case "$(env_get COMPOSE_FILE)" in *"$WAZUH_COMPOSE"*) return 0 ;; esac; return 1; }

# running bundled-Wazuh containers of this project (also when COMPOSE_FILE was never set)
wazuh_running() {
  project=$($DC config 2>/dev/null | sed -n 's/^name: *//p' | head -n 1)
  docker ps -q --filter "label=com.docker.compose.project=${project:-horus}" \
    --filter "label=com.docker.compose.service=wazuh-manager" | grep -q .
}

# A bundled Wazuh started by hand (docker compose -f docker-compose.wazuh.yml ...) belongs to this deployment: record
# COMPOSE_FILE so that the scripts keep Horus attached to it instead of recreating Horus without the Wazuh network.
wazuh_adopt() {
  if ! wazuh_enabled && wazuh_running; then
    env_set COMPOSE_FILE "$WAZUH_COMPOSE"
    log "bundled Wazuh is running: COMPOSE_FILE=$WAZUH_COMPOSE added to $ENV_FILE"
  fi
}

# Back up the Wazuh volumes when the selected deployment files would start another Wazuh version than the running one
# (indexer data and manager databases are migrated forward and cannot be downgraded). Stops Wazuh; the caller starts.
wazuh_backup_before_upgrade() {
  cid=$($DC ps -q wazuh-manager 2>/dev/null | head -n 1)
  [ -n "$cid" ] || return 0
  old=$(docker inspect -f '{{.Config.Image}}' "$cid")
  new=$(compose_images | grep '^wazuh/wazuh-manager:' | head -n 1 || true)
  [ "$old" != "$new" ] || return 0
  log "bundled Wazuh changes: $old -> $new - backing up the Wazuh volumes first"
  scripts/wazuh-backup.sh backups || die "Wazuh backup failed - nothing was upgraded. The messages above say whether \
Wazuh is still running (space check) or stopped, and how to continue"
}

wazuh_preflight() {
  for v in WAZUH_INDEXER_PASSWORD WAZUH_API_PASSWORD WAZUH_DASHBOARD_PASSWORD; do
    [ -n "$(env_get "$v")" ] || die "$v must be set in $ENV_FILE (no default Wazuh password is ever used)"
  done
  # vm.max_map_count is not namespaced: a container sees the value of the Docker host (also for remote contexts)
  mmc=$(docker run --rm --network none alpine:3.24.2 cat /proc/sys/vm/max_map_count 2>/dev/null || echo 0)
  [ "${mmc:-0}" -ge 262144 ] || die "vm.max_map_count is ${mmc:-unknown} on the Docker host; the Wazuh indexer needs \
262144: sudo sysctl -w vm.max_map_count=262144 (persist it in /etc/sysctl.conf)"
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
