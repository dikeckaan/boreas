# Boreas

[English](README.md) · [Türkçe](README.tr.md)

Boreas, Apple Silicon'lu Mac'ler için ücretsiz ve açık kaynaklı bir fan denetleyicisidir. Menü çubuğunda durur, tüm fanları ve sıcaklık sensörlerini gösterir; bir fanı sabit devirde tutmanıza ya da kendi çizdiğiniz bir sıcaklık eğrisiyle sürmenize izin verir. Telemetri, hesap ve ağ erişimi yoktur.

Boreas bağımsız bir projedir; Macs Fan Control ile bağlantısı yoktur ve ondan türetilmemiştir.

Ekran görüntüleri (yakında): ana pencere, menü çubuğu paneli, profil düzenleyici. `docs/screenshots/` altında yer alacak.

<!-- TODO: docs/screenshots/main-window.png, docs/screenshots/menu-bar.png, docs/screenshots/profile-editor.png -->

## Gereksinimler

- Apple Silicon (arm64) işlemcili bir Mac.
- macOS 15 ya da üstü.

## Kurulum

> **Ön sürüm:** henüz yayımlanmış, Apple onayından (notarization) geçmiş bir sürüm yok. İlk GitHub sürümü çıkana kadar kaynaktan derleyin (aşağıda). Sürüm DMG'sinin içindeki uygulama Apple onaylı ve staple'lı olacak; geliştiricinin Mac'inde Developer ID kimliği yoksa DMG'nin kendisi imzasız olur.

1. Sürümler sayfasından `Boreas-<sürüm>.dmg` dosyasını indirip açın.
2. **Boreas**'ı **Uygulamalar**'a sürükleyin ve uygulamayı oradan açın.
3. Fan devrini yazabilmek için Boreas'ın küçük bir yardımcı servise (root) ihtiyacı vardır. Karşılama ekranında **Yardımcı Servisi Kur**'a basın, ardından **Sistem Ayarları → Genel → Giriş Öğeleri ve Uzantılar** bölümünde **Arka Planda İzin Ver** altındaki **Boreas** düğmesini açın. Bu onay bir kez gerekir; küçük bir yönlendirme paneli düğmeyi gösterir.

Yardımcı servisi istediğiniz zaman Boreas → Ayarlar → **Kaldır** ile silebilirsiniz.

## Güvenlik

Boreas bir fanı asla elle modda takılı bırakmaz. Şu kurallar kapatılamaz. Donanım durumu (2026-11-08; ayrıntı [docs/manual-test-checklist.md](docs/manual-test-checklist.md)):

1. Uygulama kapanır, çöker ya da öldürülürse yardımcı servis birkaç saniye içinde tüm fanları Otomatik'e alır. *Donanımda doğrulandı: `kill -9` → 3 sn'de Otomatik, Çık → 1 sn'de Otomatik.*
2. Uykudan önce fanlar Otomatik'e alınır; uyanınca uygulama çalışıyorsa etkin profil yeniden uygulanır. *Birim testli; uyku/uyanma donanımda henüz doğrulanmadı.*
3. Yardımcı servis sonlanırken (SIGTERM, kaldırma, güncelleme) fanlar Otomatik'e alınır. *Birim testli; SIGTERM donanımda henüz doğrulanmadı.*
4. Bir sensör okunamazsa ya da değer saçmaysa (NaN, 0, 150 °C üstü), ona bağlı kurallar devre dışı kalır; geçerli kural kalmazsa fan Otomatik'e döner. *Birim testli.*
5. Kritik sıcaklık tavanı, sabit bir CPU ve GPU güvenlik sensörü kümesini izler. Bunların 5 saniyelik ortalaması 100 °C'yi aşarsa, profil ne derse desin fan maksimuma alınır; ortalama 90 °C'nin altına inince profile dönülür. Bu sensörleri tavandan gizleyemezsiniz. *Birim testli; gerçek yük altında henüz doğrulanmadı.*
6. Sabit devir, fanın gerçek en düşük ve en yüksek değerine sıkıştırılır. *Birim testli.*

Donanımda ayrıca doğrulandı: yardımcı servis boştayken kendiliğinden çıkar, yeniden açılan uygulama profili yeniden uygular ve `boreasctl set` yazma testi fanı Otomatik'e döndürür. Henüz doğrulanmadı: yetkisiz bir istemcinin yardımcı servisle konuşamadığı.

## Test edilen donanım

**Mac mini (M6), macOS 27.2** üzerinde test edildi.

**Topluluk testleri bekleniyor:** diğer çipler (M1–M5, Pro/Max/Ultra) ve MacBook'lar farklı SMC anahtarları ve sensörler sunar. Boreas Mac'inizde çalışıyorsa ya da çalışmıyorsa, `boreasctl fans` ve `boreasctl sensors --raw` çıktısıyla bir issue açın.

## Kaynaktan derleme

Gereksinimler: Xcode 27 (Swift 6), [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) ve bir Apple Developer ekibi (yardımcı servis `SMAppService` ile kaydedilir; bunun için imzalı derleme gerekir).

```sh
git clone https://github.com/dikeckaan/boreas.git
cd boreas
cp Config/Signing.xcconfig.example Config/Signing.xcconfig   # sonra düzenleyin
xcodegen generate
open Boreas.xcodeproj
```

`Config/Signing.xcconfig` git'e girmez ve Team ID'nizi içerir:

```
DEVELOPMENT_TEAM = XXXXXXXXXX
```

Birim testleri için `cd Packages/BoreasCore && swift test` çalıştırın. Sürüm DMG'si için `scripts/release.sh <sürüm> --skip-notarize` (deneme çalıştırması); bayrak olmadan `boreas-notary` notarytool anahtar zinciri profiliyle Apple onayı (notarization) alınır (betiğin başındaki açıklamaya bakın). Fork'lar `scripts/ExportOptions.plist` içindeki Team ID'yi değiştirmelidir.

## boreasctl

`boreasctl`, aynı paketten derlenen, hata ayıklama ve donanım denemeleri için bir komut satırı aracıdır:

```sh
swift build --package-path Packages/BoreasCore                          # Packages/BoreasCore/.build/debug/boreasctl dosyasını derler
swift run --package-path Packages/BoreasCore boreasctl fans          # fan tablosu
swift run --package-path Packages/BoreasCore boreasctl sensors       # sıcaklık sensörleri
swift run --package-path Packages/BoreasCore boreasctl sensors --raw # katalogsuz: ham ad ve kimlik
swift run --package-path Packages/BoreasCore boreasctl keys TC       # önekli SMC anahtarları
sudo Packages/BoreasCore/.build/debug/boreasctl set 0 3500 --hold 20   # fan 0'ı 20 sn sür, sonra Otomatik'e dön
sudo Packages/BoreasCore/.build/debug/boreasctl auto                   # tüm fanları Otomatik'e al
```

Yazmak için root gerekir. `set`, süre dolunca ya da süreç kesilince fanı her zaman Otomatik'e geri verir.

## Sensör kataloğuna katkı

Sensör adları, grupları ve güvenlik kümesi `Packages/BoreasCore/Sources/BoreasCore/Resources/sensor-catalog.json` dosyasından gelir. Bir girdi şöyle görünür:

```json
{
  "match": "hid:PMU tdie{n}",
  "nameEN": "CPU die {n}",
  "nameTR": "CPU kalıp {n}",
  "group": "cpu",
  "featured": false,
  "safety": false,
  "suspect": false,
  "hotspot": true
}
```

- `match`, `smc:<ANAHTAR>` ya da `hid:<ürün adı>` biçimindedir; `{n}` bir sayıyı yakalar ve adlarda yeniden kullanılabilir.
- `group` `cpu`, `gpu` ya da katalogdaki başka bir gruptur; `featured` sensörü varsayılan olarak gösterir.
- `safety`, sensörü kritik sıcaklık tavanına ekler. Buraya yalnızca doğrulanmış CPU/GPU kalıp sensörleri girer; lütfen yük altındaki okumaları ekleyin.
- `suspect` anlamı doğrulanmamış anahtarları, `hotspot` grup ortalamalarının atladığı çekirdek başına sıcak noktaları işaretler.

Mac'inizin sensörlerini eklemek için: `boreasctl sensors --raw` çalıştırın, okumaları yükle (boşta ve CPU/GPU stres) karşılaştırın, girdileri ekleyin, `swift test` çalıştırın ve model ile macOS sürümünü belirterek pull request açın.

## Lisans

[MIT](LICENSE). Telif (c) 2026 Abdurrahman Kaan Dikeç.
