# Sorun giderme

← [README'ye dön](../../README.tr.md) · [English](../en/troubleshooting.md) | Türkçe

Şu üç komutla başlayın - soruların çoğunu yanıtlarlar:

```bash
docker compose ps                         # hangi servis çalışmıyor / sağlıksız?
docker compose logs --tail 200 <servis>   # neden?
./scripts/verify.sh                       # tam olarak ne başarısız?
```

- [Kurulum](#kurulum)
- [Docker imajları ve imzalar](#docker-imajları-ve-imzalar)
- [Windows ve macOS](#windows-ve-macos)
- [Çalışma zamanı](#çalışma-zamanı)
- [Wazuh](#wazuh)
- [Güncelleme veya geri yükleme sonrası](#güncelleme-veya-geri-yükleme-sonrası)
- [Destek için bilgi toplama](#destek-için-bilgi-toplama)

## Kurulum

| Belirti | Neden ve çözüm |
|---|---|
| `Cannot connect to the Docker daemon` | Docker çalışmıyor. Linux: `sudo systemctl enable --now docker`; kullanıcınızı `docker` grubuna ekleyin ve yeniden giriş yapın. macOS/Windows: Docker Desktop'ı başlatın |
| `docker compose >= 2.24 required` | Compose eklentisini veya Docker Desktop'ı güncelleyin |
| `.env missing - cp .env.example .env` | `.env` dosyasını şablondan oluşturun |
| `.env is mode 644 - run: chmod 600 .env` | Yalnızca uyarı - düzeltin: `chmod 600 .env` |
| `HORUS_IMAGE is not set` / `HORUS_VERSION ...` | İmaj ayarlarını girin (bir sürüm checkout'unda önceden doludur) |
| `HORUS_ADMIN_PASSWORD is required for a new installation` | Güçlü bir ilk yönetici parolası belirleyin |
| `HTTPS mode needs nginx/certs/fullchain.pem and privkey.pem` | Sertifikanızı kopyalayın veya `./scripts/install.sh --self-signed` çalıştırın |
| `HORUS_WORKER_CPUS=... exceeds the host's ... CPUs` | `.env` içinde `HORUS_WORKER_CPUS` değerini düşürün |
| `less than 5 GB free` | Disk alanı açın; imajlar ve veri büyümek için yer ister |
| `./scripts/...` çalıştırırken `Permission denied` | `chmod +x scripts/*.sh` |
| 80/443 portu zaten kullanımda | Diğer servisi durdurun veya `HORUS_HTTPS_PORT` / `HORUS_HTTP_PORT` ayarlayın |

## Docker imajları ve imzalar

| Belirti | Neden ve çözüm |
|---|---|
| `pull access denied` / `repository does not exist` | Yanlış `HORUS_IMAGE` veya depo private - `docker login` çalıştırın |
| `manifest unknown` | O tag için imaj yok - `HORUS_VERSION` değerini `release-manifest.json` ile karşılaştırın |
| `toomanyrequests` | Docker Hub anonim çekme limiti - bekleyin veya limiti yükseltmek için `docker login` yapın |
| `HORUS_SIGNING_IDENTITY is not set` | `cosign` yüklü olduğundan imzalar doğrulanır - `release-manifest.json`'dan `signature.identity` değerini kopyalayın |
| `... is not a Horus release identity policy` | Kimlik değiştirilmiş veya kırpılmış - yeniden, birebir kopyalayın |
| `... is not digest pinned` | `HORUS_BACKEND_DIGEST` / `HORUS_FRONTEND_DIGEST` değerlerini manifest'ten girin |
| `signature verification FAILED` | İmaj, Horus sürüm workflow'unun geçerli bir imzasını taşımıyor. **Kurulum yapmayın.** Digest'leri yeniden kontrol edin; manifest ile eşleşiyorlarsa Horus sağlayıcınızla iletişime geçin |

## Windows ve macOS

| Belirti | Neden ve çözüm |
|---|---|
| `/bin/sh^M: bad interpreter` | Windows satır sonlarıyla klonlanmış - WSL terminalinden `~` içine yeniden klonlayın |
| `chmod` etkisiz, `.env` uyarısı devam ediyor | Depo `/mnt/c` üzerinde - WSL dosya sistemine taşıyın |
| WSL'de `docker: command not found` | Docker Desktop ayarlarında dağıtımınız için *WSL integration*'ı etkinleştirin |
| `no matching manifest for windows/amd64` | Docker Desktop Windows containers modunda - *Switch to Linux containers* |
| WSL2 kurulu değil | Yönetici olarak PowerShell: `wsl --install -d Ubuntu` |
| Container'lar sonlandırılıyor / çok yavaş | Docker Desktop'ın belleği yetersiz - en az 8 GB atayın |

## Çalışma zamanı

| Belirti | Neden ve çözüm |
|---|---|
| Tarayıcı sertifika uyarısı | `--self-signed` ile beklenen durum; CA sertifikası kurun ve `docker compose restart nginx` çalıştırın |
| Kurulumdan hemen sonra `api` sağlıksız | `docker compose logs api` çıktısını kontrol edin: zayıf `HORUS_ADMIN_PASSWORD` (reddedilir), veritabanı hazır değil, geçersiz bir `HORUS_IP_WHITELIST` girdisi |
| `worker` sürekli yeniden başlıyor | Bellek sınırı veya CPU ayarı; `docker compose logs worker` çıktısını kontrol edin |
| `502 Bad Gateway` | Bir backend servisi yeniden başlıyor - `docker compose ps` sağlıklı gösterene kadar bekleyin, sonra sayfayı yenileyin |
| Giriş çalışıyor ama değişiklikler hiç uygulanmıyor | Çalışma modu `OBSERVE` veya işler **Onaylar (Approvals)** altında bekliyor |
| Sunuculara Horus'tan erişilemiyor | Docker sunucusunun onlara giden SSH erişimi olmalı; firewall'ları ve varlıktaki SSH kullanıcısını/anahtarını kontrol edin |

## Wazuh

| Belirti | Neden ve çözüm |
|---|---|
| `set WAZUH_..._PASSWORD in .env` | Paketli Wazuh üç parolanın da girilmesini ister - varsayılan değer yoktur |
| `image platform check failed for linux/<arch>` | Bir imaj sunucunuzun platformunu sunmuyor veya registry okunamadı (satır hangisi olduğunu söyler). Giriş yapın (`docker login`), ağı kontrol edin veya bu sürümün dağıtım dosyalarını kullanın |
| `exec format error` (ör. `wazuh-certs`) | Yanlış mimariye ait bir imaj: 4.14.8 öncesi Wazuh ve 0.0.4 öncesi sertifika üreticisi yalnızca amd64 idi. Bu sürümün dağıtım dosyalarına geçin ve `./scripts/install.sh --with-wazuh` çalıştırın |
| `certificate ... was not created` (`wazuh-certs` 1 ile çıkar) | Üretici `wazuh/certs/` dizinine yazamadı veya aracını `packages.wazuh.com` adresinden indiremedi (dışarıya HTTPS). Sorunu giderin, `wazuh/certs/` dizinini boşaltın ve yeniden başlatın |
| `insufficient disk space for the Wazuh backup` | Wazuh volume'ları (zafiyet içeriği: birkaç GB) yedek dizinine sığmıyor. Yer açın veya önce `./scripts/wazuh-backup.sh /yeterli/alanli/dizin` çalıştırın; Wazuh durdurulmadı |
| `vm.max_map_count is ... on the Docker host` / `wazuh-indexer` çıkıyor | `sudo sysctl -w vm.max_map_count=262144` veya bellek yetersiz (`WAZUH_INDEXER_JAVA_OPTS`) |
| Indexer kimlik doğrulaması başarısız | `./scripts/wazuh-init.sh` çalıştırılmamış veya parolalar sonradan değişmiş - başlatmadan önce yeniden çalıştırın |
| `bundled Wazuh is running: COMPOSE_FILE=... added` | Bilgi: Wazuh elle `-f docker-compose.wazuh.yml` ile başlatılmıştı; scriptler artık Horus'u ona bağlı tutar |
| Docker Desktop altında paketli Wazuh (macOS / Windows) | Test edilmedi - bir Linux sunucu (x86_64 veya ARM64) ya da harici bir Wazuh kullanın |
| Bağlantı testi başarısız (harici Wazuh) | URL/port, kimlik bilgileri ve TLS: doğrulamayı açık tutun ve özel bir CA için `HORUS_WAZUH_CA_BUNDLE` ayarlayın |

## Güncelleme veya geri yükleme sonrası

| Belirti | Neden ve çözüm |
|---|---|
| `update.sh`: yeni imaj şema revizyonunu tanımıyor | Daha eski bir sürüme geçmeye çalıştınız - bunun yerine `rollback.sh` kullanın |
| `update.sh` sonrası yeni sürüm sağlıksız | `./scripts/rollback.sh` (yalnızca imajlar) veya şema değiştiyse `./scripts/rollback.sh --with-backup` |
| `restore.sh`: yedeğin şema sürümü bilinmiyor | Yedek daha yeni bir sürüme ait - önce o sürümü kurun |
| `restore.sh`: `pg_restore failed` | Mevcut veritabanı değiştirilmedi; arşivi ve boş disk alanını kontrol edin |
| Geri yüklenen veri yanlış görünüyor | Önceki veritabanı `horus_pre_restore_<zaman damgası>` olarak saklanır |

## Destek için bilgi toplama

```bash
docker compose version
docker compose ps
./scripts/verify.sh
docker compose logs --tail 300 api worker nginx > horus-logs.txt
```

> [!WARNING]
> `.env` dosyasını, yedek arşivlerini, `nginx/certs/privkey.pem` dosyasını veya `horus_secrets` volume'unun içeriğini
> asla paylaşmayın. Göndermeden önce logları ifşa etmek istemediğiniz sunucu adları veya adresler açısından kontrol
> edin.
