# Horus'u Windows 10 / 11'e kurma (Docker Desktop + WSL2)

← [README'ye dön](../../README.tr.md) · [English](../en/installation-windows.md) | Türkçe

Horus, Windows'ta **WSL2** altyapılı Docker Desktop ve **Linux container'ları** ile **değerlendirme ve geliştirme**
için çalışır. Aşağıdaki tüm komutlar PowerShell veya CMD'de değil, **bir WSL Linux dağıtımı (Ubuntu) içinde**
çalıştırılır. Production için bir Linux sunucu kullanın ([installation-linux.md](installation-linux.md)).

> [!IMPORTANT]
> **Neden PowerShell değil de WSL?** Horus imajları Linux container'larıdır ve dağıtım scriptleri Linux dosya
> izinlerine (`chmod 600 .env`) ve Unix satır sonlarına dayanan POSIX kabuk scriptleridir. WSL içinde ikisi de bir
> Linux sunucudaki gibi çalışır; Windows dosya sisteminde (`C:\`, `/mnt/c/`) çalışmaz.

- [1. WSL2 ve Ubuntu'yu kurun](#1-wsl2-ve-ubuntuyu-kurun)
- [2. Docker Desktop'ı kurun](#2-docker-desktopı-kurun)
- [3. Ubuntu ortamını hazırlayın](#3-ubuntu-ortamını-hazırlayın)
- [4. Dağıtım dosyalarını alın](#4-dağıtım-dosyalarını-alın)
- [5. Yapılandırın](#5-yapılandırın)
- [6. Kurun](#6-kurun)
- [7. Doğrulayın ve giriş yapın](#7-doğrulayın-ve-giriş-yapın)
- [ARM tabanlı Windows](#arm-tabanlı-windows)
- [Windows'taki sınırlamalar](#windowstaki-sınırlamalar)

## 1. WSL2 ve Ubuntu'yu kurun

**PowerShell'i Yönetici olarak** açın:

```powershell
wsl --install -d Ubuntu
wsl --set-default-version 2
```

İstendiğinde Windows'u yeniden başlatın, ardından Başlat menüsünden **Ubuntu**'yu açın ve Linux kullanıcınızı
oluşturun. Kontrol:

```powershell
wsl -l -v          # Ubuntu VERSION 2 göstermelidir
```

## 2. Docker Desktop'ı kurun

1. [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/) kurun.
2. **Settings → General:** **Use the WSL 2 based engine** seçeneğini etkinleştirin.
3. **Settings → Resources → WSL integration:** **Ubuntu** için entegrasyonu etkinleştirin.
4. **Settings → Resources:** WSL/Docker'a en az **4 CPU ve 8 GB bellek** verin (WSL2 altyapısında bu sınırlar
   `%UserProfile%\.wslconfig` dosyasında ayarlanır, örneğin `memory=8GB` ve `processors=4`).
5. Docker'ın **Linux container'ları** çalıştırdığından emin olun (varsayılan). Tepsi menüsünde
   *Switch to Linux containers* görünüyorsa tıklayın.

## 3. Ubuntu ortamını hazırlayın

**Ubuntu** terminalinde:

```bash
sudo apt-get update
sudo apt-get install -y git openssl jq curl
docker version
docker compose version     # v2.24 veya üstü - Docker Desktop tarafından sağlanır
```

İsteğe bağlı - imza doğrulama:

```bash
curl -fsSLo cosign "https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64"
sudo install -m 0755 cosign /usr/local/bin/cosign && rm cosign
```

## 4. Dağıtım dosyalarını alın

**WSL dosya sistemi içine** (Linux ev dizininize) klonlayın:

```bash
cd ~
git clone --branch v1.0.0 https://github.com/doganyesilkir/horus-deploy.git
cd horus-deploy
```

> [!CAUTION]
> `/mnt/c/...` altına klonlamayın ve Git for Windows ile klonlamayın. Orada dosya izinleri yok sayılır ve Windows
> satır sonları scriptleri `/bin/sh^M: bad interpreter` hatasıyla bozar.

## 5. Yapılandırın

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

Yerel bir değerlendirme için:

```dotenv
HORUS_DOMAIN=localhost
HORUS_ADMIN_PASSWORD=<güçlü ve benzersiz bir parola>
```

`HORUS_WORKER_CPUS` değerini WSL'e ayrılan CPU sayısı veya altında tutun.

## 6. Kurun

```bash
./scripts/install.sh --self-signed
```

> [!NOTE]
> Windows'ta 80 veya 443 portları zaten kullanılıyorsa (örneğin IIS tarafından), `.env` içinde `HORUS_HTTPS_PORT=8443`
> ve `HORUS_HTTP_PORT=8080` ayarlayın ve `https://localhost:8443/` adresini kullanın.

## 7. Doğrulayın ve giriş yapın

```bash
docker compose ps
./scripts/verify.sh
```

Windows tarayıcınızda `https://localhost/` adresini açın, kendinden imzalı sertifika uyarısını kabul edin, `admin`
olarak giriş yapın ve yeni bir parola belirleyin.

## ARM tabanlı Windows

Windows on ARM için Docker Desktop, arm64 Linux container'larını WSL2 üzerinden çalıştırır ve Horus native arm64 imajlar
yayımlar; bu nedenle yukarıdaki adımlar değişmeden geçerlidir (cosign için `cosign-linux-arm64` kullanın). Bu
kombinasyon Horus sürüm hattında **test edilmez** - yalnızca değerlendirme için kullanın.

## Windows'taki sınırlamalar

| Bileşen | Durum |
|---|---|
| Horus web arayüzü, API, SSH üzerinden otomasyon | ✅ Çalışır |
| Docker sunucusunda isteğe bağlı Falco (`--profile falco`) | ❌ eBPF destekli bir Linux sunucu kernel'i gerektirir |
| Paketli Wazuh (`docker-compose.wazuh.yml`) | ⚠️ Önerilmez - yaklaşık 8 GB ek bellek ve WSL kernel'inde `vm.max_map_count` gerektirir |
| Harici Wazuh (Entegrasyonlar'da yapılandırılır) | ✅ Çalışır |
| Native Windows container'ları | ❌ Desteklenmez |
