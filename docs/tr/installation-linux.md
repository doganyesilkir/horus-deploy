# Horus'u Linux'a kurma (Ubuntu / Debian, x86_64 ve ARM64)

← [README'ye dön](../../README.tr.md) · [English](../en/installation-linux.md) | Türkçe

Production için önerilen platform budur. Paketli Wazuh 4.14.8 stack'i dahil tüm bileşenler x86_64 ve ARM64 üzerinde
aynı komutlarla desteklenir - Docker sunucunuza uyan imaj varyantını çeker.

- [1. Sunucuyu hazırlayın](#1-sunucuyu-hazırlayın)
- [2. Docker'ı kurun](#2-dockerı-kurun)
- [3. Ek araçlar (isteğe bağlı): cosign ve jq](#3-ek-araçlar-isteğe-bağlı-cosign-ve-jq)
- [4. Dağıtım dosyalarını alın](#4-dağıtım-dosyalarını-alın)
- [5. Yapılandırın](#5-yapılandırın)
- [6. TLS sertifikası](#6-tls-sertifikası)
- [7. Kurun](#7-kurun)
- [8. Doğrulayın ve giriş yapın](#8-doğrulayın-ve-giriş-yapın)
- [ARM64 notları](#arm64-notları)

## 1. Sunucuyu hazırlayın

| | Öneri |
|---|---|
| İşletim sistemi | Ubuntu 22.04 / 24.04 LTS veya Debian 12 |
| CPU / RAM | 4 vCPU / 8 GB (paketli Wazuh ile 6 vCPU / 16 GB) |
| Disk | 50 GB SSD (paketli Wazuh ile 100 GB) |
| Ağ | Horus için bir DNS adı; yöneteceğiniz sunuculara giden SSH; Docker Hub'a HTTPS |

Web portlarını sunucu firewall'unda açın (`ufw` ile örnek):

```bash
sudo ufw allow 443/tcp
sudo ufw allow 80/tcp        # yalnızca HTTPS'e yönlendirir
```

> [!TIP]
> `443/80` portlarını yalnızca Horus arayüzüne ihtiyaç duyan ağlara açın, örneğin
> `sudo ufw allow from 203.0.113.0/24 to any port 443 proto tcp`.

## 2. Docker'ı kurun

Docker Engine'i ve Compose eklentisini Docker'ın resmi deposundan kurun.

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

**Debian** - aynısı; iki URL'de `ubuntu` yerine `debian` kullanılır:

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

Kullanıcınızın Docker çalıştırabilmesine izin verin, ardından **oturumu kapatıp yeniden açın**:

```bash
sudo usermod -aG docker "$USER"
```

Kontrol:

```bash
docker version
docker compose version      # v2.24 veya üstü olmalı
```

## 3. Ek araçlar (isteğe bağlı): cosign ve jq

`cosign` sürüm imzalarını doğrular; `jq` `release-manifest.json` dosyasını okur. İkisi de önerilir.

```bash
sudo apt-get install -y jq
ARCH=$(dpkg --print-architecture)          # amd64 veya arm64
curl -fsSLo cosign "https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-${ARCH}"
sudo install -m 0755 cosign /usr/local/bin/cosign && rm cosign
cosign version
```

> [!IMPORTANT]
> `cosign` kurulduktan sonra `install.sh` ve `update.sh` imaj imzalarını doğrular ve **herhangi bir sorunda durur**.
> `HORUS_BACKEND_DIGEST`, `HORUS_FRONTEND_DIGEST` ve `HORUS_SIGNING_IDENTITY` değerlerinin ayarlı olduğundan emin olun.

## 4. Dağıtım dosyalarını alın

Çalıştırmak istediğiniz sürümün tag'ini klonlayın:

```bash
cd /opt
sudo git clone --branch v1.0.0 https://github.com/doganyesilkir/horus-deploy.git
sudo chown -R "$USER": horus-deploy
cd horus-deploy
```

## 5. Yapılandırın

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

En azından şunları ayarlayın:

```dotenv
HORUS_DOMAIN=horus.example.com
HORUS_ADMIN_PASSWORD=<güçlü ve benzersiz bir parola>
```

Bir sürüm checkout'unda `HORUS_IMAGE`, `HORUS_VERSION`, digest'ler ve `HORUS_SIGNING_IDENTITY` zaten doludur. Bunları
`release-manifest.json` ile karşılaştırın:

```bash
jq '{repository, version, backend: .backend.digest, frontend: .frontend.digest, identity: .signature.identity}' release-manifest.json
grep -E '^HORUS_(IMAGE|VERSION|BACKEND_DIGEST|FRONTEND_DIGEST|SIGNING_IDENTITY)=' .env
```

Diğer tüm ayarlar: [configuration.md](configuration.md).

## 6. TLS sertifikası

**Production** - CA tarafından imzalanmış bir sertifikayı (tam zincir) ve anahtarını kopyalayın:

```bash
cp /path/to/fullchain.pem nginx/certs/fullchain.pem
cp /path/to/privkey.pem   nginx/certs/privkey.pem
chmod 0644 nginx/certs/fullchain.pem
chmod 0640 nginx/certs/privkey.pem
sudo chgrp 101 nginx/certs/privkey.pem     # nginx container'ı uid/gid 101 ile çalışır
```

**Değerlendirme** - bu adımı atlayın ve aşağıda `--self-signed` kullanın.

## 7. Kurun

```bash
./scripts/install.sh                       # nginx/certs/ altında sertifika var
./scripts/install.sh --self-signed         # geçici kendinden imzalı sertifika
./scripts/install.sh --require-signature   # production: imza doğrulanmadan kurulumu reddet
./scripts/install.sh --with-wazuh          # paketli Wazuh'u da çalıştır (yukarıdaki seçeneklerle birleştirilebilir)
```

Kurulum scripti bir ön kontrol çalıştırır, her imajın Docker sunucusunun platformunu (`linux/amd64` veya
`linux/arm64`) sunduğunu kontrol eder, imzaları doğrular (`cosign` yüklüyse), imajları Docker Hub'dan çeker, stack'i
başlatır, her sağlık kontrolünü bekler ve `scripts/verify.sh`'i çalıştırır. `--with-wazuh` için önce
`vm.max_map_count` ayarını ve üç `WAZUH_*_PASSWORD` değerini girin (bkz.
[integrations.md](integrations.md#seçenek-b---paketli-tek-düğümlü-wazuh)).

## 8. Doğrulayın ve giriş yapın

```bash
docker compose ps
./scripts/verify.sh
```

`https://horus.example.com/` adresini açın, `admin` kullanıcısı ve `HORUS_ADMIN_PASSWORD` ile giriş yapın ve yeni bir
parola belirleyin. [Sonraki adımlar](../../README.tr.md#sonraki-adımlar) ile devam edin.

## ARM64 notları

- Horus imajları **çok mimarilidir**; Docker `linux/arm64` varyantını otomatik olarak çeker. Parametre veya
  emülasyon gerekmez.
- `cosign` ARM64 için de mevcuttur (`cosign-linux-arm64`; yukarıdaki `dpkg --print-architecture` komutu doğru dosyayı
  seçer).
- **Paketli Wazuh 4.14.8** stack'i (`docker-compose.wazuh.yml`) ve sertifika üreticisi de çok mimarilidir:
  `./scripts/install.sh --with-wazuh` ARM64'te native çalışır (4.14.8 öncesi Wazuh sürümleri yalnızca x86_64 idi).
- Horus'u sürekli çalışan bir servis olarak işletin: Docker servisi etkin olduğu sürece
  (`sudo systemctl enable docker`) her container yeniden başlatmadan sonra otomatik olarak yeniden başlar
  (`restart: unless-stopped`).
