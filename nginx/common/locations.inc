# --- security headers ------------------------------------------------------------
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
add_header Cross-Origin-Opener-Policy "same-origin" always;

location = /nginx-health {
    access_log off;
    default_type text/plain;
    return 200 "ok\n";
}

# internal endpoints are never exposed through the proxy
location = /metrics { return 404; }
location = /ready   { return 404; }

# --- API ---------------------------------------------------------------------------
location = /api/v1/auth/login {
    limit_req zone=auth burst=5 nodelay;
    proxy_pass http://horus_api;
    include /etc/nginx/common/proxy_params.inc;
}

# Runtime security event ingestion from managed hosts (Falco http_output), authenticated by an asset-bound token.
# Error-log lines contain the full request line, so this location logs critical errors only.
location = /api/v1/runtime-security/ingest/falco {
    error_log /dev/stderr crit;
    limit_req_log_level warn;
    limit_req zone=ingest burst=400 nodelay;
    client_max_body_size 1m;
    proxy_pass http://horus_api;
    include /etc/nginx/common/proxy_params.inc;
}

location /api/ {
    limit_req zone=api burst=60 nodelay;
    proxy_pass http://horus_api;
    include /etc/nginx/common/proxy_params.inc;
    proxy_read_timeout 120s;
}

# --- Grafana (sub path, own login) ----------------------------------------------------
location /grafana/ {
    proxy_pass http://horus_grafana;
    proxy_set_header Host $http_host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
}

# --- Frontend (Next.js) -----------------------------------------------------------------
location / {
    proxy_pass http://horus_frontend;
    include /etc/nginx/common/proxy_params.inc;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'self'; frame-ancestors 'self'; base-uri 'self'; form-action 'self'" always;
    # add_header here replaces the server-level set, so repeat the remaining ones
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Strict-Transport-Security $horus_hsts always;
}
