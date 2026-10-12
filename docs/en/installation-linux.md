# Installing Horus on Linux (Ubuntu / Debian, x86_64 and ARM64)

← [Back to README](../../README.md) · English | [Türkçe](../tr/installation-linux.md)

This is the recommended platform for production. Every component is supported on x86_64, including the bundled
Wazuh stack. On ARM64 everything except the bundled Wazuh is supported.

- [1. Prepare the host](#1-prepare-the-host)
- [2. Install Docker](#2-install-docker)
- [3. Optional tools: cosign and jq](#3-optional-tools-cosign-and-jq)
- [4. Get the deployment files](#4-get-the-deployment-files)
- [5. Configure](#5-configure)
- [6. TLS certificate](#6-tls-certificate)
- [7. Install](#7-install)
- [8. Verify and sign in](#8-verify-and-sign-in)
- [ARM64 notes](#arm64-notes)

## 1. Prepare the host

| | Recommendation |
|---|---|
| OS | Ubuntu 22.04 / 24.04 LTS or Debian 12 |
| CPU / RAM | 4 vCPU / 8 GB (6 vCPU / 16 GB with the bundled Wazuh) |
| Disk | 50 GB SSD (100 GB with the bundled Wazuh) |
| Network | A DNS name for Horus; outbound SSH to the servers you will manage; HTTPS to Docker Hub |

Open the web ports in the host firewall (example with `ufw`):

```bash
sudo ufw allow 443/tcp
sudo ufw allow 80/tcp        # only redirects to HTTPS
```

> [!TIP]
> Restrict `443/80` to the networks that need the Horus UI, for example `sudo ufw allow from 203.0.113.0/24 to any port 443 proto tcp`.

## 2. Install Docker

Install Docker Engine and the Compose plugin from Docker's official repository.

**Ubuntu**

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git openssl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

**Debian** - identical, with `debian` instead of `ubuntu` in the two URLs:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git openssl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Allow your user to run Docker, then **log out and back in**:

```bash
sudo usermod -aG docker "$USER"
```

Check:

```bash
docker version
docker compose version      # must be v2.24 or newer
```

## 3. Optional tools: cosign and jq

`cosign` verifies the release signatures; `jq` reads `release-manifest.json`. Both are recommended.

```bash
sudo apt-get install -y jq
ARCH=$(dpkg --print-architecture)          # amd64 or arm64
curl -fsSLo cosign "https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-${ARCH}"
sudo install -m 0755 cosign /usr/local/bin/cosign && rm cosign
cosign version
```

> [!IMPORTANT]
> Once `cosign` is installed, `install.sh` and `update.sh` verify the image signatures and **stop on any
> problem**. Make sure `HORUS_BACKEND_DIGEST`, `HORUS_FRONTEND_DIGEST` and `HORUS_SIGNING_IDENTITY` are set.

## 4. Get the deployment files

Clone the tag of the release you want to run:

```bash
cd /opt
sudo git clone --branch v1.0.0 https://github.com/doganyesilkir/horus-deploy.git
sudo chown -R "$USER": horus-deploy
cd horus-deploy
```

## 5. Configure

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

Set at least:

```dotenv
HORUS_DOMAIN=horus.example.com
HORUS_ADMIN_PASSWORD=<a strong, unique password>
```

In a release checkout `HORUS_IMAGE`, `HORUS_VERSION`, the digests and `HORUS_SIGNING_IDENTITY` are already filled
in. Check them against `release-manifest.json`:

```bash
jq '{repository, version, backend: .backend.digest, frontend: .frontend.digest, identity: .signature.identity}' release-manifest.json
grep -E '^HORUS_(IMAGE|VERSION|BACKEND_DIGEST|FRONTEND_DIGEST|SIGNING_IDENTITY)=' .env
```

All other settings: [configuration.md](configuration.md).

## 6. TLS certificate

**Production** - copy a CA-issued certificate (full chain) and its key:

```bash
cp /path/to/fullchain.pem nginx/certs/fullchain.pem
cp /path/to/privkey.pem   nginx/certs/privkey.pem
chmod 0644 nginx/certs/fullchain.pem
chmod 0640 nginx/certs/privkey.pem
sudo chgrp 101 nginx/certs/privkey.pem     # the nginx container runs as uid/gid 101
```

**Evaluation** - skip this step and use `--self-signed` below.

## 7. Install

```bash
./scripts/install.sh                       # with a certificate in nginx/certs/
./scripts/install.sh --self-signed         # temporary self-signed certificate
./scripts/install.sh --require-signature   # production: refuse to install without a verified signature
```

The installer runs a preflight, verifies signatures (when `cosign` is installed), pulls the images from Docker Hub,
starts the stack, waits for every health check and runs `scripts/verify.sh`.

## 8. Verify and sign in

```bash
docker compose ps
./scripts/verify.sh
```

Open `https://horus.example.com/`, sign in as `admin` with `HORUS_ADMIN_PASSWORD` and set a new password. Continue
with the [next steps](../../README.md#next-steps).

## ARM64 notes

- Horus images are **multi-architecture**; Docker pulls the `linux/arm64` variant automatically. No flags or
  emulation are needed.
- `cosign` is available for ARM64 (`cosign-linux-arm64`, selected by the `dpkg --print-architecture` command above).
- The **bundled Wazuh** stack (`docker-compose.wazuh.yml`) uses x86_64-only images. Connect Horus to an external
  Wazuh server instead (see [integrations.md](integrations.md)).
- Run Horus as a long-running service: Docker restarts every container automatically (`restart: unless-stopped`)
  after a reboot as long as the Docker service is enabled (`sudo systemctl enable docker`).
