# Entegrasyonlar

← [README'ye dön](../../README.tr.md) · [English](../en/integrations.md) | Türkçe

Entegrasyonlar web arayüzünde **Entegrasyonlar (Integrations)** altında yapılandırılır. Her entegrasyonun bir
**Bağlantıyı test et (Test connection)** düğmesi vardır; secret'lar (parolalar, token'lar, webhook URL'leri)
kurulumun ana anahtarıyla şifreli saklanır ve bir daha gösterilmez.

| Entegrasyon | Kategori | Horus ne yapar |
|---|---|---|
| **Wazuh** | Zafiyetler, alarmlar | Ajanları, zafiyetleri ve alarmları aktarır; dosya bütünlüğü olayları |
| **Falco** | Çalışma zamanı güvenliği | Yönetilen sunuculardan (Horus ile kurulan) çalışma zamanı olaylarını alır |
| **Slack**, **Microsoft Teams** | Bildirimler | Incoming webhook bildirimleri |
| **Webhook** | Bildirimler | İsteğe bağlı HMAC-SHA256 imzalı (`X-Horus-Signature`) JSON webhook |
| **E-posta (SMTP)** | Bildirimler | SMTP sunucunuz üzerinden e-posta (STARTTLS desteklenir) |
| **MISP** | Tehdit istihbaratı | IDS göstergelerinin (IP, alan adı, hash, URL) günlük aktarımı |
| **AbuseIPDB** | Tehdit istihbaratı | Public IP'ler için isteğe bağlı itibar sorguları (önbelleğe alınır) |
| **GLPI** | CMDB / ITSM | Bilgisayarların varlıklarla senkronizasyonu, olaylar ve değişiklikler için kayıt (ticket) |
| **FortiGate** | Ağ firewall'u | Durum ve politikalar (salt okunur), onaylı engelleme listesi adres grubu |
| **HashiCorp Vault** | Secret'lar | Yeni kimlik bilgileri için secret backend - `.env` içinde yapılandırılır ([configuration.md](configuration.md#secret-backend-vault)) |

- [Wazuh](#wazuh)
- [Falco](#falco)
- [Bildirimler](#bildirimler)
- [Tehdit istihbaratı, CMDB ve ağ firewall'u](#tehdit-istihbaratı-cmdb-ve-ağ-firewallu)

## Wazuh

Horus Wazuh **olmadan** da çalışır. Wazuh ile sunucularınızın zafiyetleri ve alarmları Horus'ta görünür.

### Seçenek A - mevcut bir Wazuh sunucusu (önerilen)

**Entegrasyonlar → Wazuh** altında yapılandırın (alanlar: API URL'si ve kullanıcısı, indexer URL'si ve kullanıcısı,
TLS doğrulaması, CA paketi; secret'lar: API parolası, indexer parolası) veya `.env` içinde önceden yapılandırın:

```dotenv
HORUS_WAZUH_ENABLED=true
HORUS_WAZUH_API_URL=https://wazuh.example.com:55000
HORUS_WAZUH_API_USER=wazuh-wui
HORUS_WAZUH_API_PASSWORD=<parola>
HORUS_WAZUH_INDEXER_URL=https://wazuh.example.com:9200
HORUS_WAZUH_INDEXER_USER=admin
HORUS_WAZUH_INDEXER_PASSWORD=<parola>
HORUS_WAZUH_VERIFY_TLS=true
```

Ardından `docker compose up -d` çalıştırın ve arayüzde **Bağlantıyı test et** düğmesini kullanın.

### Seçenek B - paketli tek düğümlü Wazuh

> [!WARNING]
> Yalnızca x86_64 Linux sunucular, yaklaşık 8 GB ek bellek. ARM64'te veya macOS'te Docker Desktop altında desteklenmez.

```bash
# 1. Wazuh indexer için kernel ayarı
sudo sysctl -w vm.max_map_count=262144
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-wazuh.conf

# 2. .env içinde parolalar (zorunlu - yayımlanmış hiçbir varsayılan kullanılmaz)
#    WAZUH_INDEXER_PASSWORD=...  WAZUH_API_PASSWORD=...  WAZUH_DASHBOARD_PASSWORD=...

# 3. bu parolalardan indexer kullanıcı hash'leri
./scripts/wazuh-init.sh

# 4. Horus'u Wazuh ile birlikte başlatın
docker compose -f docker-compose.wazuh.yml up -d
docker compose -f docker-compose.wazuh.yml ps
```

`docker-compose.wazuh.yml` normal Horus stack'ini içerir ve entegrasyonu otomatik olarak etkinleştirir.
Sunucularınızdaki Wazuh ajanları Docker sunucusunun **1514/1515** portlarına bağlanır; Wazuh dashboard'u
**127.0.0.1:8443** üzerinde dinler (`WAZUH_DASHBOARD_BIND`, `WAZUH_DASHBOARD_PORT`).

> [!NOTE]
> Paketli Wazuh'u çalıştırırken elle yazdığınız Compose komutlarında `docker compose -f docker-compose.wazuh.yml ...`
> kullanın.

## Falco

- **Yönetilen sunucular:** `.env` içinde `HORUS_FALCO_INGEST_URL` değerini sunucuların Horus'a erişmek için kullandığı
  URL olarak ayarlayın (örneğin `https://horus.example.com`), ardından **Sunucular (Assets) → sunucu → Runtime
  Security → Install Falco** yolunu izleyin. İş normal onay kurallarına tabidir; her sunucu olaylarını kendi varlığa
  bağlı (asset-bound) token'ıyla gönderir. Olaylar **Çalışma Zamanı Güvenliği (Runtime Security)** altında görünür.
- **Docker sunucusunun kendisi** (isteğe bağlı, yalnızca eBPF destekli Linux sunucular):

  ```bash
  docker compose --profile falco up -d falco
  ```

  Container yalnızca BPF, PERFMON, SYS_RESOURCE ve SYS_PTRACE yeteneklerini kullanır - privileged mod ve Docker soketi
  yoktur.

## Bildirimler

| Entegrasyon | Gerekenler |
|---|---|
| Slack | Incoming webhook URL'si |
| Microsoft Teams | Webhook URL'si |
| Webhook | URL; isteğe bağlı imzalama secret'ı (istekler `X-Horus-Signature` taşır) |
| E-posta | SMTP sunucusu, port, gönderen adresi, alıcılar, kullanıcı adı, STARTTLS; parola |

Olayların kanallara yönlendirilmesi: **Bildirimler ve Webhook'lar (Notifications & Webhooks)**.

## Tehdit istihbaratı, CMDB ve ağ firewall'u

| Entegrasyon | Gerekenler |
|---|---|
| MISP | URL, API anahtarı; isteğe bağlı TLS doğrulaması, gün sayısı, etiketler, sınır |
| AbuseIPDB | API anahtarı; isteğe bağlı azami rapor yaşı |
| GLPI | URL, uygulama token'ı (app token), kullanıcı token'ı (user token); isteğe bağlı olayda kayıt açma |
| FortiGate | URL, API token'ı, VDOM, engelleme listesi adres grubu |

> [!TIP]
> Horus'un bu servislere yalnızca giden HTTPS erişimine ihtiyacı vardır. Yapılandırılmamış entegrasyonlar
> *Yapılandırılmadı (Not configured)* olarak gösterilir ve hiçbir şey yapmaz.
