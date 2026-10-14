# Integrations

← [Back to README](../../README.md) · English | [Türkçe](../tr/integrations.md)

Integrations are configured in the web UI under **Integrations**. Every integration has a **Test connection**
button; secrets (passwords, tokens, webhook URLs) are stored encrypted with the installation's master key and are
never shown again.

| Integration | Category | What Horus does |
|---|---|---|
| **Wazuh** | Vulnerabilities, alerts | Imports agents, vulnerabilities and alerts; file integrity events |
| **Falco** | Runtime security | Receives runtime events from managed servers (installed through Horus) |
| **Slack**, **Microsoft Teams** | Notifications | Incoming-webhook notifications |
| **Webhook** | Notifications | JSON webhook with optional HMAC-SHA256 signature (`X-Horus-Signature`) |
| **E-mail (SMTP)** | Notifications | Mail via your SMTP server (STARTTLS supported) |
| **MISP** | Threat intelligence | Daily import of IDS indicators (IP, domain, hash, URL) |
| **AbuseIPDB** | Threat intelligence | On-demand reputation lookups for public IPs (cached) |
| **GLPI** | CMDB / ITSM | Computer sync to assets, tickets for incidents and changes |
| **FortiGate** | Network firewall | Status and policies (read-only), approved block-list address group |
| **HashiCorp Vault** | Secrets | Secret backend for new credentials - configured in `.env` ([configuration.md](configuration.md#secret-backend-vault)) |

- [Wazuh](#wazuh)
- [Falco](#falco)
- [Notifications](#notifications)
- [Threat intelligence, CMDB and network firewall](#threat-intelligence-cmdb-and-network-firewall)

## Wazuh

Horus works **without** Wazuh. With Wazuh, vulnerabilities and alerts of your servers appear in Horus.

### Option A - an existing Wazuh server (recommended)

Configure it in **Integrations → Wazuh** (fields: API URL and user, indexer URL and user, TLS verification, CA bundle;
secrets: API password, indexer password), or preconfigure it in `.env`:

```dotenv
HORUS_WAZUH_ENABLED=true
HORUS_WAZUH_API_URL=https://wazuh.example.com:55000
HORUS_WAZUH_API_USER=wazuh-wui
HORUS_WAZUH_API_PASSWORD=<password>
HORUS_WAZUH_INDEXER_URL=https://wazuh.example.com:9200
HORUS_WAZUH_INDEXER_USER=admin
HORUS_WAZUH_INDEXER_PASSWORD=<password>
HORUS_WAZUH_VERIFY_TLS=true
```

Then `docker compose up -d` and use **Test connection** in the UI.

### Option B - bundled single-node Wazuh

Wazuh **4.14.8** (manager, indexer, dashboard) and certificate generator **0.0.4**, as multi-arch images: the same
command on Linux **x86_64 and ARM64**, Docker pulls the variant of your host. About 8 GB of extra memory. Not tested
under Docker Desktop on macOS or Windows.

```bash
# 1. kernel setting for the Wazuh indexer
sudo sysctl -w vm.max_map_count=262144
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-wazuh.conf

# 2. passwords in .env (required - no published default is ever used)
#    WAZUH_INDEXER_PASSWORD=...  WAZUH_API_PASSWORD=...  WAZUH_DASHBOARD_PASSWORD=...

# 3. install (also adds Wazuh to an existing Horus installation)
./scripts/install.sh --with-wazuh
```

`install.sh --with-wazuh`:

1. writes `COMPOSE_FILE=docker-compose.wazuh.yml` to `.env` - from then on plain `docker compose ...` commands and every
   script include the Wazuh services;
2. checks that **every** image (Horus, third-party, Wazuh) offers the Docker host's platform, that `vm.max_map_count`
   is at least 262144 on the Docker host and that the three passwords are set - and stops otherwise;
3. writes the indexer password hashes once (`scripts/wazuh-init.sh`);
4. starts everything: the certificate generator creates the TLS certificates in `wazuh/certs/` on the first start
   (it downloads the Wazuh certificate tool from `packages.wazuh.com`, so outbound HTTPS is needed), then the indexer,
   the manager and the dashboard start in that order once the previous one is healthy;
5. runs `verify.sh`, which also checks an authenticated indexer query, the manager API login and the dashboard.

The integration is enabled automatically. Wazuh agents on your servers connect to ports **1514/1515** of the Docker
host; the Wazuh dashboard listens on **127.0.0.1:8443** (`WAZUH_DASHBOARD_BIND`, `WAZUH_DASHBOARD_PORT`).
Upgrading from an earlier bundled Wazuh: [operations.md](operations.md#bundled-wazuh-upgrade).

#### Changing the bundled Wazuh passwords

For the indexer users `admin` (`WAZUH_INDEXER_PASSWORD`) and `kibanaserver` (`WAZUH_DASHBOARD_PASSWORD`):

```bash
${EDITOR:-nano} .env                 # new WAZUH_INDEXER_PASSWORD and/or WAZUH_DASHBOARD_PASSWORD
./scripts/wazuh-init.sh              # new hashes into internal_users.yml
docker compose exec wazuh-indexer bash -c 'export JAVA_HOME=/usr/share/wazuh-indexer/jdk && \
  bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
  -f /usr/share/wazuh-indexer/config/opensearch-security/internal_users.yml -t internalusers -icl -nhnv -h localhost \
  -cacert /usr/share/wazuh-indexer/config/certs/root-ca.pem \
  -cert /usr/share/wazuh-indexer/config/certs/admin.pem -key /usr/share/wazuh-indexer/config/certs/admin-key.pem'
docker compose up -d                 # manager, dashboard and Horus pick up the new values
./scripts/verify.sh
```

The Wazuh API user (`wazuh-wui`, `WAZUH_API_PASSWORD`) is not covered by these steps: change it through the Wazuh API
and update the dashboard's API connection (`wazuh.yml` in the `wazuh_dashboard_config` volume) as described in the
Wazuh documentation.

## Falco

- **Managed servers:** set `HORUS_FALCO_INGEST_URL` in `.env` to the URL the servers use to reach Horus (for example
  `https://horus.example.com`), then open **Assets → server → Runtime Security → Install Falco**. The job follows the
  normal approval rules; each server sends its events with its own asset-bound token. Events appear under
  **Runtime Security**.
- **The Docker host itself** (optional, Linux hosts with eBPF only):

  ```bash
  docker compose --profile falco up -d falco
  ```

  The container uses only the BPF, PERFMON, SYS_RESOURCE and SYS_PTRACE capabilities - no privileged mode and no
  Docker socket.

## Notifications

| Integration | Required |
|---|---|
| Slack | Incoming webhook URL |
| Microsoft Teams | Webhook URL |
| Webhook | URL; optional signing secret (requests carry `X-Horus-Signature`) |
| E-mail | SMTP host, port, from address, recipients, username, STARTTLS; password |

Routing of events to channels: **Notifications & Webhooks**.

## Threat intelligence, CMDB and network firewall

| Integration | Required |
|---|---|
| MISP | URL, API key; optional TLS verification, days, tags, limit |
| AbuseIPDB | API key; optional maximum report age |
| GLPI | URL, app token, user token; optional ticket on incident |
| FortiGate | URL, API token, VDOM, block-list address group |

> [!TIP]
> Horus only needs outbound HTTPS to these services. Integrations that are not configured are shown as
> *Not configured* and do nothing.
