#!/bin/sh
# Bundled Wazuh only: write wazuh/config/wazuh_indexer/internal_users.yml with bcrypt hashes of the passwords in
# .env (WAZUH_INDEXER_PASSWORD -> admin, WAZUH_DASHBOARD_PASSWORD -> kibanaserver). Run once before the first
# `docker compose -f docker-compose.wazuh.yml up -d`; re-run (and follow README: Wazuh password rotation) to change.
# The hashes are computed by the Wazuh indexer image's own tool in a throw-away container without network.
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh

for v in WAZUH_INDEXER_PASSWORD WAZUH_API_PASSWORD WAZUH_DASHBOARD_PASSWORD; do
  [ -n "$(env_get "$v")" ] || die "$v must be set in $ENV_FILE (no default Wazuh password is ever used)"
done
image=$(sed -n 's/^ *image: \(wazuh\/wazuh-indexer:[^ ]*\)$/\1/p' docker-compose.wazuh.yml | head -n 1)
[ -n "$image" ] || die "wazuh-indexer image not found in docker-compose.wazuh.yml"

hash_of() {
  # the password travels as an environment variable of a network-less container, never as a host argument
  WAZUH_PW="$1" docker run --rm -i --network none -e WAZUH_PW --entrypoint bash "$image" -c \
    'JAVA_HOME=/usr/share/wazuh-indexer/jdk bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh -p "$WAZUH_PW"' \
    2>/dev/null | grep '^\$2' | tail -n 1
}
admin=$(hash_of "$(env_get WAZUH_INDEXER_PASSWORD)")
kibana=$(hash_of "$(env_get WAZUH_DASHBOARD_PASSWORD)")
[ -n "$admin" ] && [ -n "$kibana" ] || die "could not compute password hashes"
out=wazuh/config/wazuh_indexer/internal_users.yml
umask 022
sed -e "s|__ADMIN_HASH__|$admin|" -e "s|__KIBANASERVER_HASH__|$kibana|" "$out.template" > "$out.tmp"
mv "$out.tmp" "$out"
log "written $out (bcrypt hashes only)"
