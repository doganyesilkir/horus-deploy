# Horus'u macOS'e kurma (Intel ve Apple Silicon)

← [README'ye dön](../../README.tr.md) · [English](../en/installation-macos.md) | Türkçe

macOS, Docker Desktop aracılığıyla **değerlendirme ve geliştirme** için desteklenir. Production için bir Linux
sunucu kullanın ([installation-linux.md](installation-linux.md)).

- [1. Docker Desktop'ı kurun](#1-docker-desktopı-kurun)
- [2. Ek araçlar (isteğe bağlı)](#2-ek-araçlar-isteğe-bağlı)
- [3. Dağıtım dosyalarını alın](#3-dağıtım-dosyalarını-alın)
- [4. Yapılandırın](#4-yapılandırın)
- [5. Kurun](#5-kurun)
- [6. Doğrulayın ve giriş yapın](#6-doğrulayın-ve-giriş-yapın)
- [Apple Silicon notları](#apple-silicon-notları)
- [macOS'teki sınırlamalar](#macosteki-sınırlamalar)

## 1. Docker Desktop'ı kurun

1. [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/) indirip kurun - Mac'inize
   uygun olarak **Apple silicon** veya **Intel chip** seçin.
2. Docker Desktop'ı başlatın ve Docker'ın çalıştığını bildirene kadar bekleyin.
3. **Settings → Resources** bölümünü açın, en az **4 CPU ve 8 GB bellek** atayın ve *Apply & restart* ile uygulayın.
4. Terminal'de kontrol edin:

```bash
docker version
docker compose version      # v2.24 veya üstü
```

## 2. Ek araçlar (isteğe bağlı)

[Homebrew](https://brew.sh) ile:

```bash
brew install cosign jq
```

> [!IMPORTANT]
> `cosign` kurulduktan sonra scriptler imaj imzalarını doğrular ve herhangi bir sorunda durur. Sürümün digest'lerini
> ve `HORUS_SIGNING_IDENTITY` değerini `.env` içinde tutun.

## 3. Dağıtım dosyalarını alın

Ev dizininize klonlayın (Docker Desktop bu dizini varsayılan olarak container'larla paylaşır):

```bash
git clone --branch v1.0.0 https://github.com/doganyesilkir/horus-deploy.git ~/horus-deploy
cd ~/horus-deploy
```

## 4. Yapılandırın

```bash
cp .env.example .env
chmod 600 .env
open -e .env
```

Yerel bir değerlendirme için şunları ayarlayın:

```dotenv
HORUS_DOMAIN=localhost
HORUS_ADMIN_PASSWORD=<güçlü ve benzersiz bir parola>
```

`HORUS_WORKER_CPUS` değerini Docker Desktop'a verdiğiniz CPU sayısı veya altında tutun.

## 5. Kurun

```bash
./scripts/install.sh --self-signed
```

Script `localhost` için kendinden imzalı bir sertifika oluşturur (macOS ile gelen `openssl` ile), imajları Docker
Hub'dan çeker, stack'i başlatır ve doğrular. Intel Mac'te `linux/amd64`, Apple Silicon'da `linux/arm64` imajları
çekilir.

> [!NOTE]
> Mac'inizde 80 veya 443 portları zaten kullanılıyorsa `.env` içinde `HORUS_HTTPS_PORT=8443` ve `HORUS_HTTP_PORT=8080`
> ayarlayın ve `https://localhost:8443/` adresini açın.

## 6. Doğrulayın ve giriş yapın

```bash
docker compose ps
./scripts/verify.sh
```

`https://localhost/` adresini açın, kendinden imzalı sertifika uyarısını kabul edin, `admin` olarak giriş yapın ve
yeni bir parola belirleyin.

## Apple Silicon notları

- Horus native **arm64** imajlar yayımlar. Docker Desktop bunları otomatik olarak çeker - Rosetta gerekmez ve
  `--platform` parametresi kullanmanız gerekmez.
- Horus'un kullandığı üçüncü taraf imajlar (PostgreSQL, Redis, nginx, Prometheus, Grafana, Loki) da çok mimarilidir.

## macOS'teki sınırlamalar

| Bileşen | Durum |
|---|---|
| Horus web arayüzü, API, SSH üzerinden otomasyon | ✅ Çalışır |
| Docker sunucusunda isteğe bağlı Falco (`--profile falco`) | ❌ eBPF destekli bir Linux sunucu kernel'i gerektirir |
| Paketli Wazuh (`docker-compose.wazuh.yml`) | ⚠️ Çok mimarili imajlar, ancak Docker Desktop altında test edilmedi - bir Linux sunucu kullanın |
| Harici Wazuh (Entegrasyonlar'da yapılandırılır) | ✅ Çalışır |

Yönetilen Linux sunucularına Docker Desktop sanal makinesinden SSH ile erişilebilmelidir - bu genellikle Mac'inizin
ağından erişilebilmeleri anlamına gelir.
