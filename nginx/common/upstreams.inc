# Container IPs change when a service is recreated: names are re-resolved through Docker's embedded DNS instead of
# being cached at nginx start (no 502 after "docker compose up -d api"). "resolve" needs a shared zone; a service
# that is down at nginx start (e.g. grafana) does not prevent nginx from starting.
resolver 127.0.0.11 valid=10s ipv6=off;
resolver_timeout 5s;

upstream horus_api      { zone horus_api 64k;      server api:8000 resolve;      keepalive 16; }
upstream horus_frontend { zone horus_frontend 64k; server frontend:3000 resolve; keepalive 16; }
upstream horus_grafana  { zone horus_grafana 64k;  server grafana:3000 resolve; }

# container healthcheck only (loopback inside the nginx container)
server {
    listen 127.0.0.1:8081;
    location = /nginx-health { access_log off; default_type text/plain; return 200 "ok\n"; }
}
