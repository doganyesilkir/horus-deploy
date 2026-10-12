#!/bin/sh
# Post-install / post-update verification: health, HTTPS, and container hardening of the running deployment.
# Exit code 1 on any failure. Prints no secret values.
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh

fail=0
bad() { printf '[verify] FAIL %s\n' "$*" >&2; fail=1; }
ok()  { printf '[verify] ok   %s\n' "$*"; }

# --- health --------------------------------------------------------------------------------------------------
unhealthy=$($DC ps --format '{{.Service}}|{{.Health}}|{{.State}}' | awk -F'|' '$2 == "unhealthy" || $3 != "running" {print $1}')
[ -z "$unhealthy" ] && ok "all services running / healthy" || bad "not healthy: $unhealthy"

# --- entrypoint --------------------------------------------------------------------------------------------------
mode=$(env_get HORUS_PROXY_MODE); mode=${mode:-https}
https_port=$(env_get HORUS_HTTPS_PORT); https_port=${https_port:-443}
http_port=$(env_get HORUS_HTTP_PORT); http_port=${http_port:-80}
if [ "$mode" = https ]; then
  hdr=$(curl -sk -D - -o /dev/null "https://127.0.0.1:$https_port/api/v1/health" || true)
  printf '%s' "$hdr" | head -n 1 | grep -q ' 200' && ok "HTTPS API health" || bad "HTTPS API health"
  printf '%s' "$hdr" | grep -qi '^strict-transport-security:' && ok "HSTS header" || bad "HSTS header missing"
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$http_port/login" || true)
  [ "$code" = 301 ] && ok "HTTP redirects to HTTPS" || bad "HTTP did not redirect (got $code)"
  code=$(curl -sk -o /dev/null -w '%{http_code}' "https://127.0.0.1:$https_port/login" || true)
  [ "$code" = 200 ] && ok "web UI" || bad "web UI returned $code"
else
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$http_port/api/v1/health" || true)
  [ "$code" = 200 ] && ok "HTTP API health (http-dev mode, no TLS)" || bad "HTTP API health ($code)"
fi
code=$(curl -sk -o /dev/null -w '%{http_code}' "https://127.0.0.1:$https_port/metrics" 2>/dev/null || \
       curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$http_port/metrics" || true)
[ "$code" = 404 ] || [ "$code" = 301 ] && ok "/metrics not exposed" || bad "/metrics reachable through the proxy ($code)"

# --- container hardening ------------------------------------------------------------------------------------------
for cid in $($DC ps -q); do
  name=$(docker inspect -f '{{.Name}}' "$cid" | sed 's|^/||')
  svc=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$cid")
  user=$(docker inspect -f '{{.Config.User}}' "$cid")
  case "$user" in ""|0|root|0:*|root:*) bad "$name runs as root" ;; esac
  [ "$(docker inspect -f '{{.HostConfig.Privileged}}' "$cid")" = false ] || bad "$name is privileged"
  [ "$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}}' "$cid")" = true ] || bad "$name has a writable root filesystem"
  case "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$cid")" in host) bad "$name uses the host network" ;; esac
  [ "$(docker inspect -f '{{.HostConfig.PidMode}}' "$cid")" != host ] || bad "$name shares the host PID namespace"
  case "$(docker inspect -f '{{.HostConfig.IpcMode}}' "$cid")" in host) bad "$name shares the host IPC namespace" ;; esac
  docker inspect -f '{{range .Mounts}}{{.Source}} {{end}}' "$cid" | grep -q 'docker.sock' && bad "$name mounts the Docker socket"
  docker inspect -f '{{json .HostConfig.SecurityOpt}}' "$cid" | grep -q 'no-new-privileges' || bad "$name lacks no-new-privileges"
  docker inspect -f '{{json .HostConfig.CapDrop}}' "$cid" | grep -q 'ALL' || bad "$name does not drop all capabilities"
  caps=$(docker inspect -f '{{join .HostConfig.CapAdd ","}}' "$cid")
  case "$svc:$caps" in
    *:|falco:*BPF*) : ;;
    *) bad "$name adds capabilities: $caps" ;;
  esac
  ports=$(docker inspect -f '{{range $p, $b := .NetworkSettings.Ports}}{{if $b}}{{$p}} {{end}}{{end}}' "$cid")
  if [ -n "$ports" ] && [ "$svc" != nginx ]; then bad "$name publishes ports: $ports"; fi
done
[ "$fail" -eq 0 ] && ok "container hardening (non-root, read-only, no extra capabilities, only nginx published)"
exit "$fail"
