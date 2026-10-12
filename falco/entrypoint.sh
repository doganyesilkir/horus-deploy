#!/bin/sh
# Horus local Falco: read the ingest token from the secrets volume (never from
# the environment of docker inspect) and start Falco with the modern eBPF engine.
set -eu
TOKEN=$(cat /run/horus-secrets/ingest_token)
export HORUS_FALCO_HTTP_URL="${HORUS_API_URL:-http://api:8000}/api/v1/runtime-security/ingest/falco?token=${TOKEN}"
exec /usr/bin/falco -o engine.kind=modern_ebpf "$@"
