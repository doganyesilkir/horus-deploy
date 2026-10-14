# Installing Horus on macOS (Intel and Apple Silicon)

← [Back to README](../../README.md) · English | [Türkçe](../tr/installation-macos.md)

macOS is supported for **evaluation and development** through Docker Desktop. For production, use a Linux host
([installation-linux.md](installation-linux.md)).

- [1. Install Docker Desktop](#1-install-docker-desktop)
- [2. Optional tools](#2-optional-tools)
- [3. Get the deployment files](#3-get-the-deployment-files)
- [4. Configure](#4-configure)
- [5. Install](#5-install)
- [6. Verify and sign in](#6-verify-and-sign-in)
- [Apple Silicon notes](#apple-silicon-notes)
- [Limitations on macOS](#limitations-on-macos)

## 1. Install Docker Desktop

1. Download and install [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/) -
   choose **Apple silicon** or **Intel chip** to match your Mac.
2. Start Docker Desktop and wait until it reports that Docker is running.
3. Open **Settings → Resources** and assign at least **4 CPUs and 8 GB of memory**, then *Apply & restart*.
4. Check in Terminal:

```bash
docker version
docker compose version      # v2.24 or newer
```

## 2. Optional tools

With [Homebrew](https://brew.sh):

```bash
brew install cosign jq
```

> [!IMPORTANT]
> Once `cosign` is installed, the scripts verify the image signatures and stop on any problem. Keep the digests and
> `HORUS_SIGNING_IDENTITY` from the release in `.env`.

## 3. Get the deployment files

Clone into your home directory (Docker Desktop shares it with containers by default):

```bash
git clone --branch v1.0.0 https://github.com/doganyesilkir/horus-deploy.git ~/horus-deploy
cd ~/horus-deploy
```

## 4. Configure

```bash
cp .env.example .env
chmod 600 .env
open -e .env
```

For a local evaluation set:

```dotenv
HORUS_DOMAIN=localhost
HORUS_ADMIN_PASSWORD=<a strong, unique password>
```

Leave `HORUS_WORKER_CPUS` at or below the number of CPUs you gave Docker Desktop.

## 5. Install

```bash
./scripts/install.sh --self-signed
```

The script creates a self-signed certificate for `localhost` (with the `openssl` that ships with macOS), pulls the
images from Docker Hub, starts the stack and verifies it. Intel Macs pull the `linux/amd64` images, Apple Silicon Macs the
`linux/arm64` images.

> [!NOTE]
> If ports 80 or 443 are already used on your Mac, set `HORUS_HTTPS_PORT=8443` and `HORUS_HTTP_PORT=8080` in `.env`
> and open `https://localhost:8443/`.

## 6. Verify and sign in

```bash
docker compose ps
./scripts/verify.sh
```

Open `https://localhost/`, accept the self-signed certificate warning, sign in as `admin` and set a new password.

## Apple Silicon notes

- Horus publishes native **arm64** images. Docker Desktop pulls them automatically - Rosetta is not needed and no
  `--platform` flag is required.
- Third-party images used by Horus (PostgreSQL, Redis, nginx, Prometheus, Grafana, Loki) are multi-architecture as
  well.

## Limitations on macOS

| Component | Status |
|---|---|
| Horus web UI, API, automation over SSH | ✅ Works |
| Optional Falco on the Docker host (`--profile falco`) | ❌ Needs a Linux host kernel with eBPF |
| Bundled Wazuh (`docker-compose.wazuh.yml`) | ⚠️ Multi-arch images, but not tested under Docker Desktop - use a Linux host |
| External Wazuh (configured in Integrations) | ✅ Works |

Managed Linux servers must be reachable over SSH from the Docker Desktop VM - which normally means from your Mac's
network.
