# Boreas

[English](README.md) · [Türkçe](README.tr.md)

Boreas, Apple Silicon'lu Mac'ler için ücretsiz ve açık kaynaklı bir fan denetleyicisidir. Menü çubuğunda durur, tüm fanları ve sıcaklık sensörlerini gösterir; bir fanı sabit devirde tutmanıza ya da kendi çizdiğiniz bir sıcaklık eğrisiyle sürmenize izin verir. Telemetri, hesap ve ağ erişimi yoktur.

Boreas bağımsız bir projedir; Macs Fan Control ile bağlantısı yoktur ve ondan türetilmemiştir.

<!-- Ekran görüntüleri: aşağıdaki yer tutucuları gerçek görüntülerle değiştirin (PNG, yaklaşık 1600 px genişlik). -->
| Ana pencere | Menü çubuğu paneli | Profil düzenleyici |
|---|---|---|
| ![Ana pencere](docs/screenshots/main-window.png) <!-- TODO: docs/screenshots/main-window.png --> | ![Menü çubuğu paneli](docs/screenshots/menu-bar.png) <!-- TODO: docs/screenshots/menu-bar.png --> | ![Profil düzenleyici](docs/screenshots/profile-editor.png) <!-- TODO: docs/screenshots/profile-editor.png --> |

## Gereksinimler

- Apple Silicon (arm64) işlemcili bir Mac.
- macOS 15 ya da üstü.

## Kurulum

1. Sürümler sayfasından `Boreas-<sürüm>.dmg` dosyasını indirip açın.
2. **Boreas**'ı **Uygulamalar**'a sürükleyin ve uygulamayı oradan açın.
3. Fan devrini yazabilmek için Boreas'ın küçük bir yardımcı servise (root) ihtiyacı vardır. Karşılama ekranında **Yardımcı Servisi Kur**'a basın, ardından **Sistem Ayarları → Genel → Oturum Açma Öğeleri ve Uzantılar** bölümünde **Arka Planda İzin Ver** altındaki **Boreas** düğmesini açın. Bu onay bir kez gerekir; küçük bir yönlendirme paneli düğmeyi gösterir.

Yardımcı servisi istediğiniz zaman Boreas → Ayarlar → **Kaldır** ile silebilirsiniz.

## Güvenlik

Boreas bir fanı asla elle modda takılı bırakmaz. Şu kurallar kapatılamaz:

1. Uygulama kapanır, çöker ya da öldürülürse yardımcı servis birkaç saniye içinde tüm fanları Otomatik'e alır.
2. Uykudan önce fanlar Otomatik'e alınır; uyanınca uygulama çalışıyorsa etkin profil yeniden uygulanır.
3. Yardımcı servis sonlanırken (SIGTERM, kaldırma, güncelleme) fanlar Otomatik'e alınır.
4. Bir sensör okunamazsa ya da değer saçmaysa (NaN, 0, 150 °C üstü), ona bağlı kurallar devre dışı kalır; geçerli kural kalmazsa fan Otomatik'e döner.
5. Kritik sıcaklık tavanı, sabit bir CPU ve GPU güvenlik sensörü kümesini izler. Bunların 5 saniyelik ortalaması 100 °C'yi aşarsa, profil ne derse desin fan maksimuma alınır; ortalama 90 °C'nin altına inince profile dönülür. Bu sensörleri tavandan gizleyemezsiniz.
6. Sabit devir, fanın gerçek en düşük ve en yüksek değerine sıkıştırılır.

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

Birim testleri için `cd Packages/BoreasCore && swift test` çalıştırın. Sürüm DMG'si için `scripts/release.sh <sürüm> --skip-notarize` (deneme çalıştırması); bayrak olmadan `boreas-notary` notarytool anahtar zinciri profiliyle noter onayı yapılır (betiğin başındaki açıklamaya bakın). Fork'lar `scripts/ExportOptions.plist` içindeki Team ID'yi değiştirmelidir.

## boreasctl

`boreasctl`, aynı paketten derlenen, hata ayıklama ve donanım denemeleri için bir komut satırı aracıdır:

```sh
swift run --package-path Packages/BoreasCore boreasctl fans          # fan tablosu
swift run --package-path Packages/BoreasCore boreasctl sensors       # sıcaklık sensörleri
swift run --package-path Packages/BoreasCore boreasctl sensors --raw # katalogsuz: ham ad ve kimlik
swift run --package-path Packages/BoreasCore boreasctl keys TC       # önekli SMC anahtarları
sudo .build/debug/boreasctl set 0 3500 --hold 20   # fan 0'ı 20 sn sür, sonra Otomatik'e dön
sudo .build/debug/boreasctl auto                   # tüm fanları Otomatik'e al
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
