# Yapılandırma referansı

← [README'ye dön](../../README.tr.md) · [English](../en/configuration.md) | Türkçe

Horus, depo kök dizinindeki `.env` dosyası (`.env.example`'dan kopyalanır) ile yapılandırılır. Dosya hem Docker
Compose hem de scriptler tarafından okunur. `chmod 600` olarak tutun - aksi halde ön kontrol uyarı verir.

- [Sürüm manifest'i](#sürüm-manifesti)
- [Docker imajları](#docker-imajları)
- [Erişim ve TLS](#erişim-ve-tls)
- [Yönetici hesabı (ilk kurulum)](#yönetici-hesabı-ilk-kurulum)
- [Secret'lar](#secretlar)
- [Otomasyon güvenliği](#otomasyon-güvenliği)
- [Arayüz ve parola politikası](#arayüz-ve-parola-politikası)
- [Çalışma zamanı güvenliği (Falco)](#çalışma-zamanı-güvenliği-falco)
- [Wazuh](#wazuh)
- [Secret backend (Vault)](#secret-backend-vault)
- [Cosign imaj imzaları](#cosign-imaj-imzaları)
- [Politika geçersiz kılmaları](#politika-geçersiz-kılmaları)

## Sürüm manifest'i

Her sürüm checkout'u, sürümün yetkili tanımı olan `release-manifest.json` dosyasını içerir:

| Alan | Anlamı |
|---|---|
| `version` | Sürüm numarası, ör. `1.0.0` |
| `repository` | İki imajın da bulunduğu Docker Hub deposu |
| `backend.tag`, `backend.digest` | `backend-<version>` ve çok mimarili `sha256` digest'i |
| `frontend.tag`, `frontend.digest` | `frontend-<version>` ve digest'i |
| `backend.platforms`, `frontend.platforms` | `linux/amd64`, `linux/arm64` |
| `signature.identity`, `signature.oidc_issuer` | Sürüm workflow'unun Cosign keyless imza kimliği |
| `sbom.files` | İmajların CycloneDX SBOM'ları |
| `agent` | İsteğe bağlı ajan binary'lerinin dosya adları, mimarileri ve SHA-256 sağlama toplamları |

```bash
jq . release-manifest.json
```

Sürümün `.env.example` dosyası bu manifest'ten üretilir; bu nedenle yeni bir `cp .env.example .env` doğru imajı,
sürümü, digest'leri ve kimliği zaten içerir.

## Docker imajları

| Değişken | Varsayılan | Açıklama |
|---|---|---|
| `HORUS_IMAGE` | `<dockerhub_username>/horus` | Tag veya digest içermeyen depo adı |
| `HORUS_VERSION` | sürüm numarası | Kesin sürüm; imajlar `backend-<version>` / `frontend-<version>`. `latest` reddedilir |
| `HORUS_BACKEND_DIGEST` | sürümün digest'i | `sha256:...` - backend imajını sabitler (api, worker'lar, zamanlayıcı) |
| `HORUS_FRONTEND_DIGEST` | sürümün digest'i | `sha256:...` - web arayüzü imajını sabitler |

Digest verildiğinde Compose `<image>:<tag>@<digest>` kullanır: tag sürümü belgeler, digest içeriği garanti eder.
Digest olmadan scriptler uyarır ve imza doğrulaması yapılamaz.

## Erişim ve TLS

| Değişken | Varsayılan | Açıklama |
|---|---|---|
| `HORUS_DOMAIN` | - | Kullanıcıların açtığı DNS adı; `--self-signed` sertifikasının CN/SAN değeri |
| `HORUS_PROXY_MODE` | `https` | `https`: 443'te HSTS ile TLS, 80 yönlendirir. `http-dev`: 80'de düz HTTP - yalnızca geliştirme |
| `HORUS_BIND_ADDRESS` | `0.0.0.0` | nginx'in bağlandığı sunucu adresi (ör. tek bir arayüz) |
| `HORUS_HTTPS_PORT` / `HORUS_HTTP_PORT` | `443` / `80` | Yayımlanan sunucu portları |
| `HORUS_COOKIE_SECURE` | `auto` | İstek HTTPS üzerinden geldiyse oturum cookie'leri `Secure` olur |
| `HORUS_FORWARDED_ALLOW_IPS` | boş | `X-Forwarded-For` için güvenilen proxy'ler (boş: yalnızca Docker iç ağları) |

Sertifikalar: `nginx/certs/fullchain.pem` ve `nginx/certs/privkey.pem` (bkz. [nginx/certs/README.md](../../nginx/certs/README.md)).
Değiştirdikten sonra `docker compose restart nginx` çalıştırın.

## Yönetici hesabı (ilk kurulum)

| Değişken | Varsayılan | Açıklama |
|---|---|---|
| `HORUS_ADMIN_USERNAME` | `admin` | Yalnızca veritabanında hiç kullanıcı yoksa oluşturulur |
| `HORUS_ADMIN_EMAIL` | `admin@horus.local` | Bu hesabın e-posta adresi |
| `HORUS_ADMIN_PASSWORD` | - | Yeni kurulumda zorunlu; zayıf veya örnek değerler reddedilir. İlk girişte değiştirilmelidir |

İlk girişten sonra bu değer artık kullanılmaz ve `.env`'den kaldırılabilir.

## Secret'lar

Bunları `horus-init` container'ının `horus_secrets` Docker volume'una bir kez (rastgele, kuruluma özel) üretmesi için
**boş bırakın** veya kendi değerlerinizi verin (`openssl rand -hex 32`):

| Değişken | Kullanım amacı |
|---|---|
| `HORUS_MASTER_KEY` | Saklanan SSH anahtarlarının ve entegrasyon secret'larının şifrelenmesi - **yedekleyin** |
| `HORUS_JWT_SECRET` | Oturum token'larının imzalanması |
| `POSTGRES_PASSWORD`, `REDIS_PASSWORD` | İç veritabanı ve kuyruk |
| `GRAFANA_ADMIN_PASSWORD` | Grafana `admin` hesabı (`/grafana/`) |
| `HORUS_INGEST_TOKEN` | Platformun kendi olay alımı (ör. yerel Falco container'ı) |

Üretilmiş bir değeri okumak için (örneğin Grafana parolası):

```bash
docker run --rm -v horus_secrets:/s:ro alpine:3.24.2 cat /s/grafana_admin_password; echo
```

## Otomasyon güvenliği

| Değişken | Varsayılan | Açıklama |
|---|---|---|
| `HORUS_OPERATION_MODE` | `APPROVAL` | `OBSERVE` (değişiklik yok), `APPROVAL` (değişiklikler onay gerektirir), `AUTONOMOUS` - başlangıç değeri, Ayarlar'dan değiştirilebilir |
| `HORUS_ALLOW_SELF_APPROVAL` | `true` | `false` dört göz prensibini zorunlu kılar |
| `HORUS_PRODUCTION_REQUIRED_APPROVALS` | `2` | Production varlıklarındaki yüksek riskli işler için gereken onay sayısı |
| `HORUS_JOB_TIMEOUT_SECONDS` | `1800` | Otomasyon işi başına kesin süre sınırı |
| `HORUS_WORKER_CONCURRENCY` | `4` | Worker başına paralel iş sayısı |
| `HORUS_WORKER_CPUS` | `2.0` | Worker container'ının CPU sınırı - sunucunun CPU sayısını aşmamalıdır |
| `HORUS_IP_WHITELIST` | `127.0.0.1/32` | Otomasyonun asla engellememesi gereken IP/CIDR'ler - yönetim ağlarınızı ekleyin |
| `HORUS_SCHEDULE_TIMEZONE` | `UTC` | Yeni görev zamanlamalarının saat dilimi |
| `HORUS_SERVICE_STATUS_INTERVAL_SECONDS` | `60` | Servis durumlarının arka planda yenilenme aralığı |
| `HORUS_MONITOR_CONCURRENCY` | `8` | Domain izleme: aynı anda çalışan kontrol sayısı ([domain-monitoring.md](domain-monitoring.md)) |
| `HORUS_MONITOR_RETENTION_DAYS` | `90` | Domain izleme: ham kontrol sonuçlarının saklandığı gün |
| `HORUS_FIREWALL_ROLLBACK_TIMEOUT` | `120` | Onaylanmamış bir firewall değişikliğinin sunucuda geri alınmasından önceki saniye |

## Arayüz ve parola politikası

| Değişken | Varsayılan |
|---|---|
| `HORUS_DEFAULT_LANGUAGE` | `tr` (`tr` veya `en`) |
| `HORUS_PASSWORD_MIN_LENGTH` | `12` |
| `HORUS_PASSWORD_REQUIRE_UPPER` / `_LOWER` / `_DIGIT` / `_SPECIAL` | `true` |
| `HORUS_PASSWORD_CHANGE_MAX_ATTEMPTS` | `5` |

## Çalışma zamanı güvenliği (Falco)

| Değişken | Açıklama |
|---|---|
| `HORUS_FALCO_INGEST_URL` | Yönetilen sunucularınızın Falco olaylarını Horus'a göndermek için kullandığı URL, ör. `https://horus.example.com` |
| `HORUS_FALCO_HOSTNAME` | Docker sunucusundaki isteğe bağlı Falco container'ının bildirdiği sunucu adı |

## Wazuh

Standart `docker-compose.yml` ile harici Wazuh:

| Değişken | Açıklama |
|---|---|
| `HORUS_WAZUH_ENABLED` | Entegrasyonu etkinleştirmek için `true` |
| `HORUS_WAZUH_API_URL`, `HORUS_WAZUH_API_USER`, `HORUS_WAZUH_API_PASSWORD` | Wazuh manager API'si (port 55000) |
| `HORUS_WAZUH_INDEXER_URL`, `HORUS_WAZUH_INDEXER_USER`, `HORUS_WAZUH_INDEXER_PASSWORD` | Wazuh indexer (port 9200) |
| `HORUS_WAZUH_VERIFY_TLS`, `HORUS_WAZUH_CA_BUNDLE` | TLS doğrulaması (`true` olarak bırakın; CA paketini Wazuh CA'nıza yönlendirin) |

Paketli Wazuh (`docker-compose.wazuh.yml`) - zorunludur, hiçbir zaman varsayılan değer kullanılmaz:

| Değişken | Açıklama |
|---|---|
| `WAZUH_INDEXER_PASSWORD`, `WAZUH_API_PASSWORD`, `WAZUH_DASHBOARD_PASSWORD` | Büyük harf, küçük harf, rakam ve sembol içeren 8-64 karakter |
| `WAZUH_DASHBOARD_BIND`, `WAZUH_DASHBOARD_PORT` | Wazuh dashboard'u, varsayılan olarak `127.0.0.1:8443` |
| `WAZUH_INDEXER_JAVA_OPTS` | Indexer heap'i, boş = `-Xms1g -Xmx1g` |
| `COMPOSE_FILE` | `install.sh --with-wazuh` tarafından yazılır (`docker-compose.wazuh.yml`); her Compose komutunun Wazuh'u kapsamasını sağlar |

Bkz. [integrations.md](integrations.md#wazuh).

## Secret backend (Vault)

| Değişken | Açıklama |
|---|---|
| `HORUS_SECRET_BACKEND` | `database` (varsayılan: PostgreSQL'de şifreli) veya `vault` (yeni kimlik bilgileri için HashiCorp Vault KV v2) |
| `HORUS_VAULT_ADDR`, `HORUS_VAULT_MOUNT`, `HORUS_VAULT_PREFIX`, `HORUS_VAULT_NAMESPACE`, `HORUS_VAULT_VERIFY_TLS` | Vault bağlantısı |
| `HORUS_VAULT_TOKEN_FILE` | Bağlanan token dosyasının **container'lar içindeki** yolu - token'ın kendisini asla `.env`'e koymayın |

Token dosyasını bağlamak için `docker-compose.yml`'nin yanına bir `docker-compose.override.yml` ekleyin (Compose bunu
otomatik okur); bu dosya token'ı `api`, `worker` ve `worker-periodic` servislerine salt okunur olarak bağlamalıdır.

## Cosign imaj imzaları

| Değişken | Açıklama |
|---|---|
| `HORUS_SIGNING_IDENTITY` | `release-manifest.json`'daki `signature.identity`, birebir kopyalanır. Scriptler yalnızca Horus sürüm kimliğinin kesin biçimini kabul eder; eksik veya gevşetilmiş değerleri reddeder |

## Politika geçersiz kılmaları

Paketle gelen politikalar imajın içindedir. [`policies/`](../../policies/README.tr.md) altındaki dosyalar salt okunur
olarak bağlanır ve bunları geçersiz kılar (aynı göreli yollar; tekil belgeler derinlemesine birleştirilir).
`policies/examples/` hiçbir zaman yüklenmez. Değişen dosyalar otomatik olarak algılanır (Horus bir politika dosyası
değiştiğinde onu yeniden okur) - yeniden başlatma gerekmez. Yeniden yüklemeyi zorlamak için `policies:write`
yetkisine sahip bir hesapla `POST /api/v1/policies/reload` çağırın.
