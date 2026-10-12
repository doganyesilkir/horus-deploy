# Troubleshooting

← [Back to README](../../README.md) · English | [Türkçe](../tr/troubleshooting.md)

Start with these three commands - they answer most questions:

```bash
docker compose ps                         # which service is not running / healthy?
docker compose logs --tail 200 <service>  # why?
./scripts/verify.sh                       # what exactly fails?
```

- [Installation](#installation)
- [Images and signatures](#images-and-signatures)
- [Windows and macOS](#windows-and-macos)
- [Runtime](#runtime)
- [Wazuh](#wazuh)
- [After an update or restore](#after-an-update-or-restore)
- [Collecting information for support](#collecting-information-for-support)

## Installation

| Symptom | Cause and fix |
|---|---|
| `Cannot connect to the Docker daemon` | Docker is not running. Linux: `sudo systemctl enable --now docker`; add your user to the `docker` group and log in again. macOS/Windows: start Docker Desktop |
| `docker compose >= 2.24 required` | Update the Compose plugin or Docker Desktop |
| `.env missing - cp .env.example .env` | Create `.env` from the template |
| `.env is mode 644 - run: chmod 600 .env` | Warning only - fix it: `chmod 600 .env` |
| `HORUS_IMAGE is not set` / `HORUS_VERSION ...` | Fill in the image settings (a release checkout has them pre-filled) |
| `HORUS_ADMIN_PASSWORD is required for a new installation` | Set a strong first administrator password |
| `HTTPS mode needs nginx/certs/fullchain.pem and privkey.pem` | Copy your certificate, or run `./scripts/install.sh --self-signed` |
| `HORUS_WORKER_CPUS=... exceeds the host's ... CPUs` | Lower `HORUS_WORKER_CPUS` in `.env` |
| `less than 5 GB free` | Free disk space; images and data need room to grow |
| `Permission denied` running `./scripts/...` | `chmod +x scripts/*.sh` |
| Port 80/443 already in use | Stop the other service or set `HORUS_HTTPS_PORT` / `HORUS_HTTP_PORT` |

## Images and signatures

| Symptom | Cause and fix |
|---|---|
| `pull access denied` / `repository does not exist` | Wrong `HORUS_IMAGE`, or the repository is private - run `docker login` |
| `manifest unknown` | No image for that tag - check `HORUS_VERSION` against `release-manifest.json` |
| `toomanyrequests` | Docker Hub anonymous pull limit - wait, or `docker login` to raise the limit |
| `HORUS_SIGNING_IDENTITY is not set` | `cosign` is installed, so signatures are verified - copy `signature.identity` from `release-manifest.json` |
| `... is not a Horus release identity policy` | The identity was changed or truncated - copy it again, verbatim |
| `... is not digest pinned` | Set `HORUS_BACKEND_DIGEST` / `HORUS_FRONTEND_DIGEST` from the manifest |
| `signature verification FAILED` | The image does not carry a valid signature of the Horus release workflow. **Do not install.** Re-check the digests; if they match the manifest, contact your Horus provider |

## Windows and macOS

| Symptom | Cause and fix |
|---|---|
| `/bin/sh^M: bad interpreter` | Cloned with Windows line endings - clone again from the WSL terminal into `~` |
| `chmod` has no effect, `.env` warning persists | The repository is on `/mnt/c` - move it into the WSL file system |
| `docker: command not found` in WSL | Enable *WSL integration* for your distribution in Docker Desktop settings |
| `no matching manifest for windows/amd64` | Docker Desktop is in Windows containers mode - *Switch to Linux containers* |
| WSL2 not installed | PowerShell as Administrator: `wsl --install -d Ubuntu` |
| Containers killed / very slow | Docker Desktop has too little memory - assign at least 8 GB |

## Runtime

| Symptom | Cause and fix |
|---|---|
| Browser certificate warning | Expected with `--self-signed`; install a CA certificate and `docker compose restart nginx` |
| `api` unhealthy right after install | Check `docker compose logs api`: weak `HORUS_ADMIN_PASSWORD` (refused), database not ready, invalid `HORUS_IP_WHITELIST` entry |
| `worker` keeps restarting | Memory limit or CPU setting; check `docker compose logs worker` |
| `502 Bad Gateway` | A backend service is restarting - wait for `docker compose ps` to show healthy, then reload |
| Login works but changes are never executed | Operation mode `OBSERVE`, or jobs waiting in **Approvals** |
| Servers unreachable from Horus | The Docker host needs outbound SSH to them; check firewalls and the SSH user/key in the asset |

## Wazuh

| Symptom | Cause and fix |
|---|---|
| `set WAZUH_..._PASSWORD in .env` | The bundled Wazuh needs all three passwords - no defaults exist |
| `wazuh-indexer` exits | `vm.max_map_count` too low (`sudo sysctl -w vm.max_map_count=262144`) or not enough memory |
| Indexer authentication fails | `./scripts/wazuh-init.sh` was not run, or the passwords changed afterwards - run it again before starting |
| Bundled Wazuh on ARM64 / macOS | Not supported (x86_64-only images) - use an external Wazuh |
| Test connection fails (external Wazuh) | URL/port, credentials, and TLS: keep verification on and set `HORUS_WAZUH_CA_BUNDLE` for a private CA |

## After an update or restore

| Symptom | Cause and fix |
|---|---|
| `update.sh`: new image does not know schema revision | You tried to go to an older release - use `rollback.sh` instead |
| New release unhealthy after `update.sh` | `./scripts/rollback.sh` (images only) or `./scripts/rollback.sh --with-backup` if the schema changed |
| `restore.sh`: backup schema version unknown | The backup comes from a newer release - install that release first |
| `restore.sh`: `pg_restore failed` | The current database was not changed; check the archive and free disk space |
| Restored data looks wrong | The previous database is kept as `horus_pre_restore_<timestamp>` |

## Collecting information for support

```bash
docker compose version
docker compose ps
./scripts/verify.sh
docker compose logs --tail 300 api worker nginx > horus-logs.txt
```

> [!WARNING]
> Never share `.env`, backup archives, `nginx/certs/privkey.pem` or the contents of the `horus_secrets` volume. Check
> logs for host names or addresses you do not want to disclose before sending them.
