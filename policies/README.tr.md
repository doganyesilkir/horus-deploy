# Politika geçersiz kılmaları (policy overrides)

[English](README.md) | Türkçe

Horus politika setinin tamamı backend imajının içinde gelir. Bu dizin `/app/policy-overrides` yoluna salt okunur
olarak bağlanır ve yalnızca değiştirmek istediğiniz dosyaları içermesi yeterlidir - paketle gelen dosyayla **aynı
göreli yolu** kullanın:

| Geçersiz kılma dosyası | Etkisi |
|---|---|
| `fim/fim.yaml`, `scoring/default.yaml`, `scoring/risk.yaml`, `firewall/firewall.yaml`, `retention/retention.yaml`, ... | paketle gelen belgenin üzerine derinlemesine birleştirilir: eşlemeler (map) birleşir, **listeler ve tekil değerler yer değiştirir**, `null` bir anahtarı kaldırır |
| `baselines/<ad>.yaml` | bir baseline ekler (veya aynı addaki paketli dosyanın yerini alır); paketli bir baseline'ı `extends:` ile genişletebilir |
| `correlation/`, `hunting/`, `runbooks/`, `compliance/` `*.yaml` | paketli kurallara eklenir; aynı dosya adı paketli dosyanın yerini alır |

`examples/` altındaki dosyalar hiçbir zaman yüklenmez. Birini hedef yoluna kopyalayıp düzenleyin - Horus bir politika
dosyası değiştiğinde onu yeniden okur, bu nedenle yeniden başlatma gerekmez (yeniden yüklemeyi zorlamak için:
`policies:write` yetkisiyle `POST /api/v1/policies/reload`). Geçersiz dosyalar loglanır ve yok sayılır; paketli
politika geçerli kalır.
