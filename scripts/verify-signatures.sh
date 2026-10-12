#!/bin/sh
# Verify the Cosign (keyless, GitHub OIDC) signatures of the configured images before they are started.
#   HORUS_SIGNING_IDENTITY  certificate identity regexp of the release workflow (from release-manifest.json)
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh

command -v cosign >/dev/null 2>&1 || die "cosign is not installed (https://docs.sigstore.dev/cosign/system_config/installation/)"
identity=${HORUS_SIGNING_IDENTITY:-$(env_get HORUS_SIGNING_IDENTITY)}
check_signing_identity "$identity"
img=${HORUS_IMAGE:-$(env_get HORUS_IMAGE)}
ver=${HORUS_VERSION:-$(env_get HORUS_VERSION)}
bd=${HORUS_BACKEND_DIGEST:-$(env_get HORUS_BACKEND_DIGEST)}
fd=${HORUS_FRONTEND_DIGEST:-$(env_get HORUS_FRONTEND_DIGEST)}
for ref in "$img:backend-$ver${bd:+@$bd}" "$img:frontend-$ver${fd:+@$fd}"; do
  case "$ref" in *@sha256:*) : ;; *) die "$ref is not digest pinned (set HORUS_BACKEND_DIGEST / HORUS_FRONTEND_DIGEST)" ;; esac
  cosign verify --certificate-identity-regexp "$identity" \
    --certificate-oidc-issuer "$SIGNING_ISSUER" "$ref" >/dev/null \
    && log "signature ok: $ref" || die "signature verification FAILED: $ref"
done
