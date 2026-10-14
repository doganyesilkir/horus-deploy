#!/bin/sh
# First installation of Horus from the published images (no source repository needed).
#
#   cp .env.example .env && chmod 600 .env && $EDITOR .env
#   docker login                      # private image repository
#   ./scripts/install.sh [--self-signed] [--with-wazuh]
#
# The same command works on linux/amd64 and linux/arm64: every image is multi-arch and Docker pulls the variant of
# the Docker host. Before anything is pulled, every image is checked for the host's platform (no emulation).
#
# --self-signed  create a temporary self-signed certificate for HORUS_DOMAIN when nginx/certs is empty
# --no-pull      use images already present locally (air-gapped hosts: docker load < horus-images.tar)
# --require-signature  refuse to install unless cosign verifies both images (cosign, digests and
#                      HORUS_SIGNING_IDENTITY must all be present - recommended for production)
# --with-wazuh   also run the bundled single-node Wazuh (docker-compose.wazuh.yml): stores COMPOSE_FILE in .env so
#                every later docker compose / script call includes it, writes the indexer password hashes once
#                (scripts/wazuh-init.sh). Can also be run on an existing installation to add Wazuh.
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh

SELF_SIGNED=false
PULL=true
REQUIRE_SIGNATURE=false
WITH_WAZUH=false
for a in "$@"; do
  case "$a" in
    --self-signed) SELF_SIGNED=true ;; --no-pull) PULL=false ;; --require-signature) REQUIRE_SIGNATURE=true ;;
    --with-wazuh) WITH_WAZUH=true ;;
    *) die "unknown option $a" ;;
  esac
done

if [ "$SELF_SIGNED" = true ] && [ ! -s nginx/certs/fullchain.pem ]; then
  domain=$(env_get HORUS_DOMAIN); domain=${domain:-localhost}
  command -v openssl >/dev/null 2>&1 || die "openssl is required for --self-signed"
  log "creating a self-signed certificate for $domain (replace it with a CA-issued one)"
  umask 077
  openssl req -x509 -newkey rsa:3072 -sha256 -days 397 -nodes -subj "/CN=$domain" \
    -addext "subjectAltName=DNS:$domain" -keyout nginx/certs/privkey.pem -out nginx/certs/fullchain.pem 2>/dev/null
  chmod 0644 nginx/certs/fullchain.pem && chmod 0640 nginx/certs/privkey.pem
  # nginx-unprivileged runs as uid 101; the key stays unreadable for others
  chgrp 101 nginx/certs/privkey.pem 2>/dev/null || chmod 0644 nginx/certs/privkey.pem
fi

if [ "$WITH_WAZUH" = true ]; then
  [ -f "$ENV_FILE" ] || die "$ENV_FILE missing - cp .env.example .env and fill it in"
  env_set COMPOSE_FILE "$WAZUH_COMPOSE"
  log "bundled Wazuh enabled (COMPOSE_FILE=$WAZUH_COMPOSE in $ENV_FILE)"
else
  wazuh_adopt
fi
preflight
# shellcheck disable=SC2034  # read by check_platforms (scripts/lib.sh)
[ "$PULL" = true ] || PLATFORM_LOCAL=true
# shellcheck disable=SC2046  # one image reference per word
check_platforms $(compose_images)
if wazuh_enabled; then
  wazuh_preflight
  [ -s wazuh/config/wazuh_indexer/internal_users.yml ] || scripts/wazuh-init.sh
fi

if [ -z "$(env_get HORUS_ADMIN_PASSWORD)" ] && ! docker volume inspect "${HORUS_PROJECT:-horus}_postgres_data" >/dev/null 2>&1; then
  die "HORUS_ADMIN_PASSWORD is required for a new installation"
fi
if command -v cosign >/dev/null 2>&1; then
  scripts/verify-signatures.sh || die "image signature verification failed - not installing"
elif [ "$REQUIRE_SIGNATURE" = true ]; then
  die "--require-signature: cosign is not installed - not installing"
else
  warn "cosign not installed - image signatures NOT verified (see README: Verify images)"
fi

if [ "$PULL" = true ]; then
  log "pulling images"
  $DC pull --quiet
else
  for ref in "$(backend_ref)" "$(frontend_ref)"; do
    docker image inspect "$ref" >/dev/null 2>&1 || die "--no-pull: image $ref is not present locally"
  done
  log "using local images (--no-pull); third-party images are pulled when missing"
fi
if wazuh_enabled; then wazuh_backup_before_upgrade; fi   # running Wazuh of another version: back up first
log "starting Horus"
$DC up -d
if wazuh_enabled; then timeout=1200; else timeout=600; fi
wait_healthy "$timeout" || die "Horus did not become healthy - check: docker compose ps / docker compose logs api"
scripts/verify.sh
{ printf '%s install\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; running_refs | sed 's/^/  /'; } >> "$STATE_FILE"
log "installed. Open https://$(env_get HORUS_DOMAIN)/ and change the administrator password at first login."
