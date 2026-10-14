#!/bin/sh
# Bundled Wazuh only: write wazuh/config/wazuh_indexer/internal_users.yml with bcrypt hashes of the passwords in
# .env (WAZUH_INDEXER_PASSWORD -> admin, WAZUH_DASHBOARD_PASSWORD -> kibanaserver). scripts/install.sh --with-wazuh
# runs it once when the file is missing; to change passwords re-run it and apply the hashes to the running indexer
# (docs/en/integrations.md: Changing the bundled Wazuh passwords).
# The hashes are computed by the Wazuh indexer image's own tool in a throw-away container without network - after
# checking that the image exists for the Docker host's platform (no emulation).
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh

for v in WAZUH_INDEXER_PASSWORD WAZUH_API_PASSWORD WAZUH_DASHBOARD_PASSWORD; do
  [ -n "$(env_get "$v")" ] || die "$v must be set in $ENV_FILE (no default Wazuh password is ever used)"
done
image=$(sed -n 's/^ *image: \(wazuh\/wazuh-indexer:[^ ]*\)$/\1/p' "$WAZUH_COMPOSE" | head -n 1)
[ -n "$image" ] || die "wazuh-indexer image not found in $WAZUH_COMPOSE"
if docker image inspect "$image" >/dev/null 2>&1; then
  have=$(docker image inspect -f '{{.Os}}/{{.Architecture}}' "$image")
  [ "$have" = "$(docker_platform)" ] || die "local $image is $have, the Docker host is $(docker_platform) - remove it and retry"
else
  check_platforms "$image"
  docker pull --quiet "$image" >/dev/null
fi

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
if [ -f "$out" ]; then
  # rewrite in place: the running indexer bind-mounts this file and would keep seeing a replaced (mv) inode
  cat "$out.tmp" > "$out" && rm -f "$out.tmp"
else
  mv "$out.tmp" "$out"
fi
log "written $out (bcrypt hashes only)"
