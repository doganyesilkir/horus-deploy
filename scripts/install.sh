#!/bin/sh
# First installation of Horus from the published images (no source repository needed).
#
#   cp .env.example .env && chmod 600 .env && $EDITOR .env
#   docker login                      # private image repository
#   ./scripts/install.sh [--self-signed]
#
# --self-signed  create a temporary self-signed certificate for HORUS_DOMAIN when nginx/certs is empty
# --no-pull      use images already present locally (air-gapped hosts: docker load < horus-images.tar)
# --require-signature  refuse to install unless cosign verifies both images (cosign, digests and
#                      HORUS_SIGNING_IDENTITY must all be present - recommended for production)
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh

SELF_SIGNED=false
PULL=true
REQUIRE_SIGNATURE=false
for a in "$@"; do
  case "$a" in
    --self-signed) SELF_SIGNED=true ;; --no-pull) PULL=false ;; --require-signature) REQUIRE_SIGNATURE=true ;;
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

preflight
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
log "starting Horus"
$DC up -d
wait_healthy 600 || die "Horus did not become healthy - check: docker compose ps / docker compose logs api"
scripts/verify.sh
{ printf '%s install\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; running_refs | sed 's/^/  /'; } >> "$STATE_FILE"
log "installed. Open https://$(env_get HORUS_DOMAIN)/ and change the administrator password at first login."
