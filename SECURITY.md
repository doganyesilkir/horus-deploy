# Security

English | [Türkçe](SECURITY.tr.md)

## Reporting a vulnerability

Report suspected vulnerabilities privately to your Horus support contact. Do not open public issues for security
problems.

## What this deployment guarantees

- **Signed images.** Release images are signed with Cosign (keyless, GitHub Actions OIDC) and recorded in the public
  Sigstore transparency log. `scripts/install.sh` and `scripts/update.sh` verify signatures when `cosign` is
  installed; deploy by digest (`@sha256:`), never by `:latest`.
- **SBOM.** Every release publishes CycloneDX SBOMs of both images.
- **Vulnerability gate.** Releases are blocked by any CRITICAL finding and by HIGH findings without a documented
  exception (Trivy).
- **No secrets in images.** Secrets are generated at first start into the `horus_secrets` volume or provided through
  `.env`; images and their layer history are scanned for keys and tokens before release.
- **Least privilege at runtime.** Non-root users, read-only root filesystems, all Linux capabilities dropped
  (optional Falco: BPF, PERFMON, SYS_RESOURCE, SYS_PTRACE only), `no-new-privileges`, no Docker socket, no host
  network / PID / IPC namespaces. Only nginx publishes ports. `scripts/verify.sh` checks all of this on the running
  deployment.
- **TLS by default.** HTTPS with HSTS; HTTP only redirects. `HORUS_PROXY_MODE=http-dev` is for development only.

## Your responsibilities

- Keep `.env`, `nginx/certs/privkey.pem` and backups (they contain the master key) readable only by administrators;
  store backups encrypted and offline.
- Replace self-signed certificates with CA-issued ones.
- Restrict access to ports 443/80 (and 1514/1515 with the bundled Wazuh) to the networks that need them.
- Apply Horus updates and keep the Docker host patched.
