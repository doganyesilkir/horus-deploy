# Installing Horus on Windows 10 / 11 (Docker Desktop + WSL2)

← [Back to README](../../README.md) · English | [Türkçe](../tr/installation-windows.md)

Horus runs on Windows for **evaluation and development** using Docker Desktop with the **WSL2** backend and
**Linux containers**. All commands below run **inside a WSL Linux distribution (Ubuntu)** - not in PowerShell or
CMD. For production, use a Linux host ([installation-linux.md](installation-linux.md)).

> [!IMPORTANT]
> **Why WSL and not PowerShell?** Horus images are Linux containers and the deployment scripts are POSIX shell
> scripts that rely on Linux file permissions (`chmod 600 .env`) and Unix line endings. Inside WSL both work as on a
> Linux server; on the Windows file system (`C:\`, `/mnt/c/`) they do not.

- [1. Install WSL2 and Ubuntu](#1-install-wsl2-and-ubuntu)
- [2. Install Docker Desktop](#2-install-docker-desktop)
- [3. Prepare the Ubuntu environment](#3-prepare-the-ubuntu-environment)
- [4. Get the deployment files](#4-get-the-deployment-files)
- [5. Configure](#5-configure)
- [6. Install](#6-install)
- [7. Verify and sign in](#7-verify-and-sign-in)
- [Windows on ARM](#windows-on-arm)
- [Limitations on Windows](#limitations-on-windows)

## 1. Install WSL2 and Ubuntu

Open **PowerShell as Administrator**:

```powershell
wsl --install -d Ubuntu
wsl --set-default-version 2
```

Restart Windows when asked, then open **Ubuntu** from the Start menu and create your Linux user. Check:

```powershell
wsl -l -v          # Ubuntu must show VERSION 2
```

## 2. Install Docker Desktop

1. Install [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/).
2. **Settings → General:** enable **Use the WSL 2 based engine**.
3. **Settings → Resources → WSL integration:** enable integration for **Ubuntu**.
4. **Settings → Resources:** give WSL/Docker at least **4 CPUs and 8 GB of memory** (with the WSL2 engine these
   limits are set in `%UserProfile%\.wslconfig`, for example `memory=8GB` and `processors=4`).
5. Make sure Docker runs **Linux containers** (the default). If the tray menu shows *Switch to Linux containers*,
   click it.

## 3. Prepare the Ubuntu environment

In the **Ubuntu** terminal:

```bash
sudo apt-get update
sudo apt-get install -y git openssl jq curl
docker version
docker compose version     # v2.24 or newer - provided by Docker Desktop
```

Optional - signature verification:

```bash
curl -fsSLo cosign "https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64"
sudo install -m 0755 cosign /usr/local/bin/cosign && rm cosign
```

## 4. Get the deployment files

Clone **inside the WSL file system** (your Linux home directory):

```bash
cd ~
git clone --branch v1.0.0 https://github.com/doganyesilkir/horus-deploy.git
cd horus-deploy
```

> [!CAUTION]
> Do not clone into `/mnt/c/...` and do not clone with Git for Windows. File permissions are ignored there and
> Windows line endings break the scripts with `/bin/sh^M: bad interpreter`.

## 5. Configure

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

For a local evaluation:

```dotenv
HORUS_DOMAIN=localhost
HORUS_ADMIN_PASSWORD=<a strong, unique password>
```

Keep `HORUS_WORKER_CPUS` at or below the number of CPUs available to WSL.

## 6. Install

```bash
./scripts/install.sh --self-signed
```

> [!NOTE]
> If ports 80 or 443 are already in use on Windows (for example by IIS), set `HORUS_HTTPS_PORT=8443` and
> `HORUS_HTTP_PORT=8080` in `.env` and use `https://localhost:8443/`.

## 7. Verify and sign in

```bash
docker compose ps
./scripts/verify.sh
```

Open `https://localhost/` in your Windows browser, accept the self-signed certificate warning, sign in as `admin`
and set a new password.

## Windows on ARM

Docker Desktop for Windows on ARM runs arm64 Linux containers through WSL2, and Horus publishes native arm64 images,
so the steps above apply unchanged (use `cosign-linux-arm64` for cosign). This combination is **not tested** by
the Horus release pipeline - use it for evaluation only.

## Limitations on Windows

| Component | Status |
|---|---|
| Horus web UI, API, automation over SSH | ✅ Works |
| Optional Falco on the Docker host (`--profile falco`) | ❌ Needs a Linux host kernel with eBPF |
| Bundled Wazuh (`docker-compose.wazuh.yml`) | ⚠️ Not tested - needs ~8 GB extra memory and `vm.max_map_count` in the WSL kernel |
| External Wazuh (configured in Integrations) | ✅ Works |
| Native Windows containers | ❌ Not supported |
