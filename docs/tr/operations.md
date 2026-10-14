# Operasyon rehberi: scriptler, güncellemeler, yedekleme, geri yükleme ve geri alma

← [README'ye dön](../../README.tr.md) · [English](../en/operations.md) | Türkçe

Tüm scriptler `scripts/` altındaki POSIX kabuk scriptleridir. Bunları Docker sunucusunda depo kök dizininden
çalıştırın (Windows'ta WSL içinde). `.env` dosyasını okurlar, gizli değerleri asla yazdırmazlar ve ilk hatada dururlar.

- [install.sh](#installsh)
- [update.sh](#updatesh)
- [rollback.sh](#rollbacksh)
- [backup.sh](#backupsh)
- [restore.sh](#restoresh)
- [verify.sh](#verifysh)
- [verify-signatures.sh](#verify-signaturessh)
- [wazuh-init.sh](#wazuh-initsh)
- [wazuh-backup.sh ve wazuh-restore.sh](#wazuh-backupsh-ve-wazuh-restoresh)
- [Paketli Wazuh yükseltmesi](#paketli-wazuh-yükseltmesi)
- [Platform kontrolü](#platform-kontrolü)
- [init-secrets.sh](#init-secretssh)
- [Dağıtım geçmişi: .horus-deployments](#dağıtım-geçmişi-horus-deployments)
- [Günlük komutlar](#günlük-komutlar)
- [Önerilen rutin](#önerilen-rutin)

## install.sh

```bash
./scripts/install.sh [--self-signed] [--no-pull] [--require-signature] [--with-wazuh]
```

| Seçenek | Etkisi |
|---|---|
| `--self-signed` | `nginx/certs/` boşsa `HORUS_DOMAIN` için geçici, kendinden imzalı bir sertifika oluşturur |
| `--no-pull` | Yerelde zaten bulunan imajları kullanır (internetsiz/air-gapped sunucular: önce `docker load` ile yükleyin) |
| `--require-signature` | `cosign` iki imajı da doğrulamadıkça kurulumu reddeder |
| `--with-wazuh` | Paketli Wazuh'u ekler: `.env` içinde `COMPOSE_FILE=docker-compose.wazuh.yml`, Wazuh kontrolleri, bir kez `wazuh-init.sh` |

Adımlar: ön kontrol → [platform kontrolü](#platform-kontrolü) → (Wazuh: parolalar, `vm.max_map_count`, parola
hash'leri) → imza doğrulama (`cosign` yüklüyse) → `docker compose pull` → `docker compose up -d` → sağlık
kontrollerini bekleme (en fazla 10 dakika, Wazuh ile 20) → `verify.sh` → `.horus-deployments` dosyasına kayıt.

**Ön kontroller:** Docker ve Compose ≥ 2.24, `.env` mevcut (`chmod 600` değilse uyarır), tag/digest içermeyen
`HORUS_IMAGE`, kesin `HORUS_VERSION` (`latest` yok), digest biçimi, `HORUS_WORKER_CPUS` ≤ sunucu CPU sayısı, `https`
modunda TLS dosyaları, boş disk alanı (5 GB'ın altında uyarır), geçerli Compose yapılandırması. Yeni bir kurulum ayrıca
`HORUS_ADMIN_PASSWORD` gerektirir.

## update.sh

```bash
./scripts/update.sh <version> [<backend digest> <frontend digest>]
./scripts/update.sh 1.1.0 sha256:<backend> sha256:<frontend>
```

Adımlar:

1. Ön kontrol ve yeni sürümün her imajı için [platform kontrolü](#platform-kontrolü) (geçtiğiniz dağıtım dosyalarıyla),
   ardından `backend-<version>` / `frontend-<version>` imajlarını çekme (verildiyse digest'lerle).
2. `cosign` yüklüyse ve iki digest de verildiyse imza doğrulama - aksi halde bir uyarı.
3. **Şema kontrolü:** yeni backend imajı, veritabanının mevcut migration revizyonunu tanımalıdır; böylece kazara sürüm
   düşürme olamaz. Tanımıyorsa hiçbir şey değiştirilmez.
4. `backups/` altına **yedek** ve mevcut sürümün (sürüm, digest'ler, şema revizyonu, yedek dosyası)
   `.horus-deployments` dosyasına kaydı. Yeni dağıtım dosyaları paketli Wazuh sürümünü değiştiriyorsa
   `wazuh-backup.sh` ayrıca Wazuh'u durdurur ve volume'larını kopyalar (bkz.
   [Paketli Wazuh yükseltmesi](#paketli-wazuh-yükseltmesi)).
5. `HORUS_VERSION` ve digest'ler `.env`'e yazılır; stack yeniden başlatılır (`api` container'ı veritabanı
   migration'larını uygular).
6. Sağlık bekleme ve `verify.sh`. Başarısızlıkta script size `rollback.sh` çalıştırmanızı söyler.

Yeni değerleri yeni sürümden alın:

```bash
git fetch --tags && git checkout v1.1.0
jq -r '.version, .backend.digest, .frontend.digest' release-manifest.json
```

> [!NOTE]
> `update.sh`, `.env` içinde yalnızca `HORUS_VERSION` ve iki digest'i değiştirir. Bir sürüm yeni ayarlar eklediğinde
> `.env` dosyanızı yeni `.env.example` ile karşılaştırın. İmza kimliği değişirse `HORUS_SIGNING_IDENTITY` değerini de
> güncelleyin.

## rollback.sh

```bash
./scripts/rollback.sh                 # önceki sürüm, yalnızca imajlar
./scripts/rollback.sh --with-backup   # önceki sürüm + update.sh'in aldığı yedek
```

`.horus-deployments` içindeki son `update from` kaydını kullanır. `--with-backup` olmadan, veritabanı önceki sürümün
tanımadığı bir şemaya taşındıysa reddeder - migration'lar yalnızca ileri yönlüdür. `--with-backup` ile güncelleme
öncesi yedek geri yüklenir, **bu yüzden güncellemeden sonra yapılan her değişiklik kaybolur**.

## backup.sh

```bash
./scripts/backup.sh [<dizin>]     # varsayılan: backups/
```

`<dizin>/horus-<UTC zaman damgası>.tar.gz` (mod `600`) oluşturur; içeriği:

| Üye | İçerik |
|---|---|
| `horus.dump` | PostgreSQL dökümü (`pg_dump --format=custom`) |
| `secrets.tar.gz` | Ana anahtar dahil `horus_secrets` volume'u |
| `env` | `.env` dosyanız (varsa) |

> [!WARNING]
> Arşiv kurulumun tüm secret'larını içerir. Şifreleyin (örneğin `age` veya `gpg` ile) ve kopyalarını sunucu dışında
> saklayın. Geri yüklemeleri düzenli olarak test edin.

Docker sunucusunda örnek gece cron görevi:

```cron
15 2 * * *  cd /opt/horus-deploy && ./scripts/backup.sh /srv/horus-backups >> /var/log/horus-backup.log 2>&1
```

## restore.sh

```bash
./scripts/restore.sh backups/horus-<zaman damgası>.tar.gz
```

1. Arşivi kontrol eder (iki üye de mevcut mu, secret'lar veritabanı parolasını içeriyor mu) - eksikse hiçbir şey
   değiştirilmez.
2. `api`, `worker`, `worker-periodic`, `beat` servislerini durdurur; secrets volume'unu geri yükler; `postgres` ve
   `redis` container'larını yeniden oluşturur.
3. Veritabanı rol parolasını geri yüklenen secret ile eşitler.
4. Dökümü ayrı bir veritabanına **tek bir işlem (transaction) içinde** yükler ve ilk hatada durur.
5. **Daha yeni bir sürüme ait yedeği reddeder** (bilinmeyen şema revizyonu) - mevcut veritabanına dokunulmaz.
6. Veritabanlarını değiştirir ve öncekini `horus_pre_restore_<zaman damgası>` olarak saklar; servisleri yeniden
   başlatır (eski şemalar başlangıçta migrate edilir).

Arşivdeki `env` üyesi otomatik olarak **uygulanmaz** - onu kendi `.env` dosyanızla karşılaştırın.

**Yeni bir sunucuda geri yükleme:**

```bash
git clone --branch v1.0.0 https://github.com/doganyesilkir/horus-deploy.git && cd horus-deploy
tar -xzf /path/horus-<ts>.tar.gz env && mv env .env && chmod 600 .env
# yeni bir sunucuda install.sh HORUS_ADMIN_PASSWORD ister - boşsa geçici, güçlü bir değer girin
./scripts/install.sh --self-signed       # veya sertifikanız nginx/certs/ altındayken
./scripts/restore.sh /path/horus-<ts>.tar.gz
```

Geri yüklenen veriyi kontrol ettikten sonra güvenlik kopyasını silin:

```bash
docker compose exec -T postgres psql -U horus -d postgres -c 'DROP DATABASE horus_pre_restore_<timestamp>'
```

## verify.sh

```bash
./scripts/verify.sh
```

| Kontrol | Beklenen |
|---|---|
| Servisler | çalışıyor ve sağlıklı |
| HTTPS | `/api/v1/health`, HTTPS üzerinden HSTS başlığıyla 200 döndürür (`https` modu) |
| Yönlendirme | HTTP, HTTPS'e yönlendirir; web arayüzü yüklenir |
| `/metrics` | proxy üzerinden erişilemez |
| Sıkılaştırma | root olmayan kullanıcı, salt okunur kök dosya sistemi, tüm yetenekler kaldırılmış (Falco: yalnızca BPF, PERFMON, SYS_RESOURCE, SYS_PTRACE), `no-new-privileges`, privileged değil, sunucunun ağ/PID/IPC namespace'i yok, Docker soketi yok |
| Erişim | yalnızca nginx port yayımlar |

Çıkış kodu `0`, her şeyin geçtiği anlamına gelir.

## verify-signatures.sh

```bash
./scripts/verify-signatures.sh
```

`cosign`, iki digest ve `.env` içinde `HORUS_SIGNING_IDENTITY` gerektirir. Her imaj için şunu çalıştırır:

```bash
cosign verify \
  --certificate-identity-regexp "$HORUS_SIGNING_IDENTITY" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  <HORUS_IMAGE>:backend-<version>@<digest>
```

Önce kimlik doğrulanır: yalnızca Horus sürüm workflow'unun kesin biçimi kabul edilir.

## wazuh-init.sh

```bash
./scripts/wazuh-init.sh
```

Yalnızca paketli Wazuh içindir. `wazuh/config/wazuh_indexer/internal_users.yml` dosyasını `WAZUH_INDEXER_PASSWORD` ve
`WAZUH_DASHBOARD_PASSWORD` değerlerinin bcrypt hash'leriyle yazar (hash'ler, imajın Docker sunucusunun platformu için
mevcut olduğu kontrol edildikten sonra, ağ erişimi olmayan bir container'da Wazuh indexer imajı tarafından hesaplanır).
`install.sh --with-wazuh` dosya yoksa bunu çalıştırır; kendiniz yalnızca bu parolaları değiştirmek için çalıştırın.
Üretilen dosya git tarafından yok sayılır.

## wazuh-backup.sh ve wazuh-restore.sh

```bash
./scripts/wazuh-backup.sh [<dizin>]                   # varsayılan: backups -> backups/wazuh-<zaman damgası>/
./scripts/wazuh-restore.sh backups/wazuh-<zaman damgası>
```

`wazuh-backup.sh` Wazuh servislerini **durdurur** (çalışan bir indexer tutarlı şekilde kopyalanamaz) ve her Wazuh
volume'unu - indexer verisi, manager yapılandırması ve veritabanları, ajan anahtarları, kuyruklar, Filebeat durumu,
dashboard yapılandırması - volume başına bir arşive, imaj sürümlerini içeren bir `MANIFEST` dosyasıyla birlikte kopyalar.
Wazuh'u yeniden başlatmaz. Veri Docker sunucusundan akıtılır; bu nedenle uzak Docker context'leri de çalışır.
Arşivleri `.env` gibi saklayın: ajan anahtarlarını ve indekslenmiş tüm olayları içerirler.

- **Önce alan kontrolü.** Script, Wazuh henüz çalışırken volume'ları ölçer ve sıkıştırılmamış boyutu (+%5 ve 512 MiB;
  bir üst sınır - gzip arşivleri genellikle daha küçüktür) hedef dizindeki boş alanla karşılaştırır. Alan yetersizse
  hiçbir şey durdurulmadan `insufficient disk space for the Wazuh backup` mesajıyla durur. `wazuh_queue` volume'undaki
  zafiyet tespit içeriği tek başına birkaç GB'tır. `HORUS_WAZUH_BACKUP_SPACE_CHECK=0` bu kontrolü atlar (risk size aittir).
- **Ya tam ya hiç.** Arşivler `<dizin>/.wazuh-<zaman damgası>.partial` altına yazılır ve yalnızca tüm volume'lar
  kopyalanıp doğrulandığında `<dizin>/wazuh-<zaman damgası>` olarak yeniden adlandırılır. Herhangi bir hatada - dolu
  disk, okuma hatası - yarım dizin silinir, script sıfır olmayan bir kodla çıkar ve durdurulan Wazuh konteynerleri
  değiştirilmeden yeniden başlatılır - yükseltme sırasında, dağıtım dosyaları zaten yeni Wazuh sürümüne aitse hariç: bu
  durumda Wazuh durdurulmuş kalır (eski konteynerler yeni yapılandırma dosyalarını okurdu) ve mesaj nasıl devam
  edileceğini söyler. Manager volume'larındaki Unix soketleri çalışma zamanı uç noktalarıdır ve mesaj vermeden atlanır.

`wazuh-restore.sh` yalnızca aynı Compose projesine ait bir yedeği kabul eder. **Mevcut** checkout'tan çalıştırın (eski
sürümlerde bu script yoktur): Wazuh'u durdurur, her volume'u boşaltıp yeniden doldurur ve **hiçbir şeyi** başlatmaz.
Ardından yedeğin alındığı sürümün dağıtım dosyalarına geçin (`MANIFEST` imajlarını listeler) ve o sürümü başlatın -
daha yeni dosyalarla başlatmak geri yüklenen veriyi yeniden ileriye dönüştürür.

## Paketli Wazuh yükseltmesi

Bir Horus sürümü paketli Wazuh sürümünü değiştirebilir (ör. 4.9.2 → **4.14.8**). Indexer verisi ve manager
veritabanları ilk başlatmada ileriye doğru dönüştürülür ve **sürüm düşürülemez**; tek geri dönüş yolu öncesinde
alınmış bir kopyadır. x86_64 ve ARM64'te aynı komutlar:

```bash
git fetch --tags && git checkout v<yeni sürüm>      # Wazuh yapılandırması dahil yeni dağıtım dosyaları
jq -r '.version, .backend.digest, .frontend.digest' release-manifest.json
./scripts/update.sh <sürüm> sha256:<backend> sha256:<frontend>
```

`update.sh` çalışan `wazuh-manager` imajının yenisinden farklı olduğunu fark eder, önce her yeni imajın platformunu
kontrol eder ve hiçbir şey başlatılmadan önce `wazuh-backup.sh` çalıştırır. Ardından stack yeni Wazuh ile başlar:
`wazuh/certs/` altındaki sertifikalar ve parolalar olduğu gibi kalır (sıfırlama yok, varsayılan parola yok). Elle
`docker compose -f docker-compose.wazuh.yml` ile başlatılmış bir Wazuh benimsenir (`.env` dosyasına `COMPOSE_FILE`
eklenir) ve `install.sh --with-wazuh` de farklı sürümde çalışan bir Wazuh'u aynı şekilde yedekler.

**Wazuh 4.9.2 → 4.14.8 - dağıtım dosyalarında neler değişir**

- Indexer yapılandırması, güvenlik dosyaları ve sertifikalar `/usr/share/wazuh-indexer/config/` altına bağlanır
  (`opensearch.yml`, `opensearch-security/internal_users.yml`, `certs/`); `wazuh.indexer.yml` yeni yolları kullanır.
- `CERT_TOOL_VERSION=4.14` ile sertifika üreticisi `0.0.4` (yalnızca `wazuh/certs/` boşken kullanılır).
- Manager yapılandırması 4.14 kural setinin `malicious-ioc` listelerini yükler.
- Manager ve dashboard için sağlık kontrolleri; indexer / manager sağlıklı olduktan sonra başlarlar.
- `platform: linux/amd64` kaldırıldı - her imaj çok mimarilidir.

Bir Wazuh yükseltmesinden sonra **geri dönüş** (yedekten sonra yazılan veri kaybolur):

```bash
./scripts/wazuh-restore.sh backups/wazuh-<zaman damgası>   # mevcut checkout'tan; Wazuh durdurulmuş kalır
git checkout v<önceki sürüm>
./scripts/rollback.sh             # Horus imajları (yalnızca Wazuh etkileniyorsa docker compose up -d)
```

Taşınacak verisi olan tek yol, **mevcut 4.9.2 kurulumu olan x86_64 sunucudur**. ARM64'te 4.9.2 verisi yoktur: bu
imajlar orada hiç çalışmadı (`exec format error`), bu nedenle yükseltme bir ilk kurulumdur.

## Platform kontrolü

`install.sh`, `update.sh` ve `wazuh-init.sh` platformu scripti çalıştıran makineye değil, **Docker daemon'una** sorar
(`docker version` → `Server.Os/Arch`) - uzak Docker context'leri ve `DOCKER_HOST` çalışır. Ardından seçili Compose
dosyalarının her imajı kendi registry'sinde (`docker manifest inspect`, paralel olarak) aranır ve bu platformu
listelemelidir; attestation manifestleri (`unknown/unknown`) sayılmaz. Eksik platform, bilinmeyen tag veya registry
hatası (giriş, ağ, çekme limiti) scripti hiçbir şey çekilmeden veya değiştirilmeden **önce** durdurur ve etkilenen
imajları listeler. `--no-pull` ile yerelde bulunan imajlar yerelde kontrol edilir. Emülasyona geri düşme yoktur.

## init-secrets.sh

Elle çalıştırılmaz. Tek seferlik `horus-init` container'ı bunu her `docker compose up` çalıştırmasında çalıştırır: her
secret için ayarlıysa `.env`'deki değeri kullanır, yoksa mevcut değeri korur ya da yeni bir rastgele değer üretir.
Ayrıca Redis yapılandırmasını yazar.

## Dağıtım geçmişi: .horus-deployments

`install.sh`, `update.sh` ve `rollback.sh`, `.horus-deployments` dosyasına (git tarafından yok sayılır) ekleme yapar:
zaman damgaları, çalışan imaj digest'leri ve güncellemeler için önceki sürüm, digest'ler, şema revizyonu ve yedek
dosyası. `rollback.sh` bu dosyayı okur - saklayın.

## Günlük komutlar

```bash
docker compose ps                          # durum
docker compose logs -f --tail 100 api      # bir servisi izleme
docker compose restart nginx               # ör. sertifikayı değiştirdikten sonra
docker compose stop && docker compose start
docker compose down                        # container'ları durdur ve kaldır (volume'lar ve veri korunur)
```

> [!CAUTION]
> `docker compose down -v` veritabanı ve secret'lar (ana anahtar) dahil **tüm volume'ları siler**. Yalnızca bir
> kurulumu kalıcı olarak kaldırmak için - ve yedek aldıktan sonra - kullanın.

## Önerilen rutin

| Ne zaman | Ne |
|---|---|
| Her gün | `backup.sh` (cron), sunucu dışına kopyalama |
| Dağıtımdaki her değişiklikten sonra | `verify.sh` |
| Bir güncellemeden önce | `RELEASE_NOTES.md`'yi okuyun, imzaları doğrulayın, digest'lerle `update.sh` |
| Her ay | ayrı bir sunucuda geri yükleme testi |
