# Güvenlik

[English](SECURITY.md) | Türkçe

## Güvenlik açığı bildirme

Şüphelendiğiniz güvenlik açıklarını Horus destek kişinize gizli olarak bildirin. Güvenlik sorunları için public issue
açmayın.

## Bu dağıtımın garanti ettikleri

- **İmzalı imajlar.** Sürüm imajları Cosign ile imzalanır (keyless, GitHub Actions OIDC) ve public Sigstore şeffaflık
  kaydına (transparency log) işlenir. `scripts/install.sh` ve `scripts/update.sh`, `cosign` yüklüyse imzaları
  doğrular; dağıtımı `:latest` ile değil, her zaman digest ile (`@sha256:`) yapın.
- **SBOM.** Her sürüm iki imajın da CycloneDX SBOM'larını yayımlar.
- **Zafiyet kapısı.** Herhangi bir CRITICAL bulgu ve belgelenmiş bir istisnası olmayan HIGH bulgular sürümü engeller
  (Trivy).
- **İmajlarda secret yok.** Secret'lar ilk başlatmada `horus_secrets` volume'una üretilir veya `.env` üzerinden
  verilir; imajlar ve katman geçmişleri sürümden önce anahtar ve token'lara karşı taranır.
- **Çalışma zamanında en az yetki.** Root olmayan kullanıcılar, salt okunur kök dosya sistemleri, tüm Linux yetenekleri
  (capabilities) kaldırılmış (isteğe bağlı Falco: yalnızca BPF, PERFMON, SYS_RESOURCE, SYS_PTRACE), `no-new-privileges`,
  Docker soketi yok, sunucunun ağ / PID / IPC namespace'leri yok. Yalnızca nginx port yayımlar. `scripts/verify.sh`
  bunların tamamını çalışan dağıtımda kontrol eder.
- **Varsayılan olarak TLS.** HSTS ile HTTPS; HTTP yalnızca yönlendirir. `HORUS_PROXY_MODE=http-dev` yalnızca
  geliştirme içindir.

## Sizin sorumluluklarınız

- `.env`, `nginx/certs/privkey.pem` ve yedekleri (ana anahtarı içerirler) yalnızca yöneticiler tarafından okunabilir
  tutun; yedekleri şifreli ve çevrim dışı saklayın.
- Kendinden imzalı sertifikaları CA tarafından imzalanmış sertifikalarla değiştirin.
- 443/80 portlarına (paketli Wazuh ile 1514/1515'e de) erişimi yalnızca ihtiyaç duyan ağlarla sınırlayın.
- Horus güncellemelerini uygulayın ve Docker sunucusunu yamalı tutun.
