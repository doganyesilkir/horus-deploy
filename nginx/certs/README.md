# TLS certificate / TLS sertifikası

**English** - Put the TLS certificate of Horus here. These files are never committed (see `.gitignore`):

| File | Content |
|---|---|
| `fullchain.pem` | Certificate followed by the intermediate certificates |
| `privkey.pem` | Private key - `chmod 0640`, readable by uid/gid 101 (the nginx container) |

Without a certificate, `./scripts/install.sh --self-signed` creates a temporary self-signed one here.

**Türkçe** - Horus'un TLS sertifikasını buraya koyun. Bu dosyalar hiçbir zaman commit edilmez (bkz. `.gitignore`):

| Dosya | İçerik |
|---|---|
| `fullchain.pem` | Sertifika ve ardından ara (intermediate) sertifikalar |
| `privkey.pem` | Özel anahtar - `chmod 0640`, uid/gid 101 (nginx container'ı) tarafından okunabilir |

Sertifika yoksa `./scripts/install.sh --self-signed` buraya geçici, kendinden imzalı bir sertifika oluşturur.
