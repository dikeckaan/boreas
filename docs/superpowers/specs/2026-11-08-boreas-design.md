# Boreas: Tasarım Dokümanı

Tarih: 2026-11-08 · Durum: onay bekliyor

Boreas, Apple Silicon Mac'ler için tamamen ücretsiz ve açık kaynak bir fan kontrol ve sıcaklık izleme uygulamasıdır. Macs Fan Control'ün yaptığı işi yapar; ücretli sürümde kilitli olan özel fan profilleri burada herkese açıktır.

## 1. Neden

Kullanıcı Macs Fan Control'de tüm sensörlerin (CPU, GPU, SSD, ağ, batarya, kısacası sıcaklık sensörü olan her yer) sıcaklığına baktı ve fanı otomatik moddan elle belli bir devre aldı. Asıl istediği, sıcaklığa göre fanı kendiliğinden ayarlayan **kendi fan profilini** kurmaktı. Bu özellik ücretli olduğu için yapamadı.

Hedef, kullanıcının kendi tarifiyle "basit görünen ama dolu dolu" bir uygulama. Genel sıcaklık artışında sistem kendini soğutsun, kullanıcı belli sıcaklıklarda Mac'in varsayılan davranışını değiştirebilsin.

## 2. Hedefler

1. Sıcaklık sensörü olan her noktanın sıcaklığını anlaşılır adlarla göstermek.
2. Her fanı tek tıkla **Otomatik** (Apple'ın kontrolü), **Sabit devir** ya da **Profil** moduna almak.
3. Sensör sıcaklığına bağlı, eğriyle tanımlanan, adlandırılmış **fan profilleri** (bkz. §5).
4. Menü çubuğundan hızlı bakış ve profil geçişi.
5. Fan devri ve seçili sensörler için sıcaklık geçmişi grafiği.
6. GitHub'da MIT lisanslı, Developer ID ile imzalanmış ve noterden geçmiş (notarized) sürümler.

## 3. Hedef olmayanlar (v1)

- Intel Mac desteği. macOS 27 yalnızca Apple Silicon'da çalışıyor; Intel SMC farkları kapsam dışı.
- Uygulamaya ya da güç kaynağına göre otomatik profil değiştirme (ileride eklenebilir).
- Sıcaklık geçmişini diske kaydetmek ve dışa aktarmak (geçmiş yalnızca bellekte tutulur).
- Otomatik güncelleme (Sparkle vb.). Kullanıcı yeni sürümü GitHub Releases'tan indirir.
- Disk SMART, pil sağlığı ya da CPU yükü gibi sıcaklık ve fan dışı izleme.
- GitHub Actions üzerinden imzalama. İlk sürüm akışı yerel makinede çalışır, CI ileride gelir.

## 4. Kesinlikle olmaması gerekenler

- **Mac'i aşırı ısınmaya bırakmak.** Boreas hiçbir koşulda fanı, Apple'ın kendi kontrolünün bırakacağından daha tehlikeli bir durumda bırakmamalı (bkz. §7).
- **Uygulama kapandıktan, çöktükten ya da Mac uykuya geçtikten sonra fanı elle modda bırakmak.**
- Ücretli, kilitli ya da "Pro" bir özellik. Hesap, telemetri ya da reklam. Uygulama ağa hiç çıkmaz.
- Macs Fan Control'ün kodunu, görsellerini, adını ya da metinlerini kopyalamak. Boreas kendi adı, logosu ve tasarımıyla bağımsız bir uygulamadır; SMC erişimi kamuya açık bilgiye dayanır.
- Kalabalık, "kontrol paneli" görünümlü bir arayüz. İlk bakışta sade, istendikçe derinleşen bir yapı olmalı.

## 5. Kullanıcının gördüğü uygulama

Onaylanan taslaklar: `docs/design/mockup-main-window-and-menubar.html` ve `docs/design/mockup-profile-editor.html`. Bunlar HTML parçalarıdır; tarayıcıda açılabilir, stilleri dosyanın içinde.

### 5.1 Menü çubuğu (birincil kullanım)

- Menü çubuğu simgesi: tek renkli, üç kanatlı pervane (logodan türetilir, şablon görsel olarak açık ve koyu temaya uyar).
- Simgenin yanındaki yazı kullanıcı tarafından seçilir: hiçbiri, sıcaklık, fan devri ya da ikisi. Gösterilecek sıcaklık için varsayılan "en sıcak CPU", kullanıcı herhangi bir sensörü seçebilir.
- Tıklayınca açılan panel:
  - Profil seçici: Otomatik, Sessiz, Performans ve kullanıcı profilleri.
  - Her fanın anlık devri.
  - "En sıcak 3" sensör.
  - "Pencereyi aç…" bağlantısı ve Çıkış.

### 5.2 Ana pencere

- **Üst çubuk:** Profil seçici (segmentli kontrol) ve "＋ yeni profil".
- **Grafik şeridi (katlanabilir):** CPU, GPU ve fan devri çizgileri ile yıldızlı sensörler. Zaman aralığı 1 dk, 10 dk ya da 1 sa.
- **Sol sütun, Fanlar:** Ad, min–max devir, anlık devir ve mod seçici (Otomatik, Sabit devir, Profil). Sabit devirde bir kaydırıcı ya da sayı alanı kullanılır, değer min ile max arasına sıkıştırılır.
- **Sağ sütun, Sensörler:**
  - Gruplar: CPU, GPU, Bellek, Depolama, Ağ, Batarya, Güç, Diğer.
  - Varsayılan olarak öne çıkan sensörler görünür, kalanlar "+N sensör daha" altında açılır.
  - Kullanıcı bir sensörü yıldızlayabilir (listenin başına ve grafiğe eklenir), yeniden adlandırabilir ya da gizleyebilir.
  - Renk kodları: serin yeşil, ılık sarı, sıcak turuncu. Eşikler sensör grubuna göre belirlenir, kesin değerler builder'a kalmıştır.
- **Fan yoksa** (ör. MacBook Air) fan sütunu yerine "Bu Mac'te fan yok" bilgisi gösterilir, uygulama sıcaklık izleyici olarak çalışmaya devam eder.

### 5.3 Profil düzenleyici

- **Mac genelinde tek bir etkin profil vardır.** Menü çubuğundaki ve üst çubuktaki seçici bunu gösterir. Her fanın modu ayrıca seçilir: Otomatik, Sabit devir ya da Profil (etkin profili izler). Profil seçmek, Profil modundaki fanları etkiler. Profil seçicide "Otomatik"i seçmek tüm fanları Otomatik'e alır. Seçicide başka bir profil seçilince, Otomatik moddaki fanlar Profil moduna geçer, Sabit devirdeki fanlar olduğu gibi kalır ve satırında "Sabit" rozeti görünür. *(Benim kararım.)*
- Bir profilin içeriği: ad ve bir ya da birden fazla **kural**. Profil, Profil modundaki tüm fanlara uygulanır. Fanlara göre ayrı eğri v1'de yok; taslaktaki "Uygulanacak fanlar" alanı kaldırıldı. *(Benim kararım.)*
- Her kural tek bir **sensör kaynağını** bir **eğriye** bağlar. Sensör kaynağı tek bir sensör ya da "CPU (en sıcak çekirdek)" gibi bir grup olabilir; grup, üyelerinin en yükseğidir.
- Eğri, 2–8 noktalı (sıcaklık °C → devir) parçalı doğrusal bir fonksiyondur. Noktalar grafikte sürüklenerek düzenlenir. İlk noktanın solunda eğri sabit min devirde, son noktanın sağında sabit son devirde kalır.
- Birden fazla kural varsa fan, **en yüksek devri isteyen kurala** uyar. Tek kural "yalnızca CPU'ya bak", çok kural "hangisi ısınırsa" anlamına gelir.
- Grafikte o anki sıcaklık dikey kesikli çizgiyle gösterilir. Diğer kuralların eğrileri soluk renkte görünür.
- Davranış seçenekleri:
  - **Yumuşak geçiş:** Hedef devir ani sıçramaz, saniyede belirli bir oranla değişir.
  - **Geç tepki (histerezis):** Sıcaklık düşerken eğri X°C (varsayılan 3°C) geriden takip eder, eşik sınırında fan sürekli hızlanıp yavaşlamaz.
  - **"Eğrinin altında Apple'a bırak":** Hesaplanan devir fanın minimumuna eşit ya da altındaysa fan Otomatik moda geri verilir. *(Benim kararım: Konuşmada "Apple'ın otomatik devrinin altına inme" olarak geçti. Fan elle moddayken Apple'ın o anki hedef devri okunamıyor, bu yüzden aynı amaca bu yolla ulaşılıyor: düşük sıcaklıkta karar Apple'da, yüksek sıcaklıkta Boreas'ta.)*
- **Yerleşik profiller:**
  - **Otomatik:** Tüm fanlar Apple'da. Silinemez.
  - **Sessiz:** CPU'ya bakar, 55°C'ye kadar min devir, 95°C'de max devir.
  - **Performans:** CPU ve GPU'ya bakar, 40°C'den itibaren erken ve dik bir yükseliş.

  Sessiz ve Performans düzenlenebilir ve kopyalanabilir. Kesin eğri değerleri builder'a kalmıştır.

### 5.4 Ayarlar

- Girişte başlat (varsayılan açık).
- Menü çubuğu gösterimi.
- Sıcaklık birimi (°C/°F).
- Örnekleme aralığı (varsayılan 1 sn).
- Yardımcı servisin durumu: kurulu ya da kurulu değil, onay bekliyor; yeniden kurma ve kaldırma düğmeleri.

### 5.5 Dil ve görünüm

- Türkçe ve İngilizce arayüz, sistem diline göre seçilir (String Catalog).
- Açık ve koyu tema desteklenir, macOS'un standart malzemeleri ve SF Symbols kullanılır.

### 5.6 Logo

Onaylanan yön "Kutup Işığı": gece göğünde kuzey ışıkları (aurora *borealis*, Boreas'ın adıyla bağlantılı) ve önünde buzlu camdan üç kanatlı bir pervane. Kaynak taslak `docs/design/logo-concept-aurora.svg`.

Builder'ın işleri:

- Taslağı son hâline getirmek (detay, kontrast, küçük boyutlarda okunabilirlik).
- macOS'un istediği tüm simge boyutlarını üretmek.
- Menü çubuğu için tek renkli şablon simgesini çıkarmak.

## 6. Mimari

İki parça, tek Xcode projesi.

```
Boreas.app (kullanıcı oturumu, SwiftUI, menü çubuğu + pencere)
   │  NSXPCConnection (mach service)
   ▼
BoreasHelper (root LaunchDaemon, SMAppService.daemon ile kayıtlı)
   ├── SMC okuma/yazma (AppleSMC IOKit)
   ├── Kontrol döngüsü (profil → hedef devir)
   └── Güvenlik bekçisi (§7)
```

### 6.1 Yardımcı servis (BoreasHelper)

- Uygulama paketinin içinde gelir ve `SMAppService.daemon(plistName:)` ile kaydedilir. Kullanıcı ilk kurulumda Sistem Ayarları → Giriş Öğeleri ve Uzantılar'dan bir kez onay verir. Uygulama bu adımı bir karşılama ekranıyla anlatır ve onay ekranını açar.
- Fan yazma için root yetkisi gerekir; okuma için gerekmez. Sensör okuma da yardımcı servis üzerinden yapılabilir. Hangisinin yapılacağı builder'a kalmıştır, ama fanı yöneten kontrol döngüsü **yardımcı serviste çalışır**. Böylece kontrol, arayüzün takılmasından etkilenmez.
- XPC bağlantısında yalnızca aynı Team ID ile imzalanmış Boreas uygulaması kabul edilir (`setCodeSigningRequirement`). Başka hiçbir süreç fanları yönetemez.
- XPC arayüzü (kabaca):
  - `snapshot()`: tüm sensör ve fan değerleri.
  - `setFanMode(fan:, mode: auto | fixed(rpm) | profile)`.
  - `applyProfile(profile)`.
  - `resetAllToAuto()`.
  - `helperVersion()`.

  Kesin imzalar builder'a kalmıştır.
- Uygulama yeni bir sürümle geldiğinde eski servis sürümü algılanıp yeniden kaydedilir.

### 6.2 SMC (bu makinede doğrulandı)

Kullanıcının makinesi Mac mini, Mac18,5, Apple M6, macOS 27.2. Salt okunur bir deneme programıyla şunlar okundu (`docs/design/` altına konmadı, aşağıdaki bilgiler yeterli):

| Anahtar | Tip | Değer | Anlam |
|---|---|---|---|
| `FNum` | ui8 | 1 | fan sayısı |
| `F0Ac` | flt | 1920 | anlık devir |
| `F0Mn` | flt | 1000 | min devir |
| `F0Mx` | flt | 4900 | max devir |
| `F0Tg` | flt | 1935 | hedef devir |
| `F0md` | ui8 | 0 | fan modu (0 = otomatik; elle mod için 1 yazılması beklenir) |
| `F0Md`, `Ftst` | yok | — | bu çipte bulunmuyor |
| `#KEY` | ui32 | 2066 | toplam anahtar sayısı |

- `T` ile başlayan ve 5–130 aralığında `flt` değer dönen **125 sıcaklık anahtarı** var. Bazıları (`TPD*`) boşta 95–110 arası değer gösteriyor. Bunların gerçek °C sıcaklık olup olmadığı belirsiz; builder bunları doğrulamalı ve şüpheli olanları varsayılan listeden çıkarmalı.
- **Yazma yolu henüz denenmedi. Planın ilk adımı bir geç/kal kapısıdır:**
  - Arayüz, profiller ve sürüm işlerinden önce, en küçük imzalı yardımcı servis yazılır.
  - Bu servisle `F0md = 1`, ardından `F0Tg = rpm` yazımı kullanıcı makinenin başındayken denenir. Kullanıcı servis onayını verir ve fan sesini dinler. Denemenin hemen ardından `F0md = 0` geri yüklenir.
  - Yazma çalışmazsa (kilit anahtarı gerekiyorsa, sistem değeri geri alıyorsa vb.) iş durur ve bulgularla kullanıcıya dönülür. Sınırsız araştırma yapılmaz, sessizce yalnızca izleme yapan bir uygulamaya da geçilmez. *(Benim kararım.)*
- **Diğer Apple Silicon çiplerinde** anahtar adları değişebilir (`F0Md` / `F0md`, bazılarında `Ftst` kilidi). Builder anahtar varlığına göre çalışan bir algılama katmanı yazmalı ve mod anahtarını sabit kodlamamalı. **Yalnızca bu Mac'te test edilebilecek.** Diğer çipler için README'de "topluluk testleri bekleniyor" notu yer almalı.
- **Yapı hizalaması tuzağı:** `SMCParamStruct` C'de 80 bayttır. Swift'te iç içe struct'lar stride değil size kadar yer kapladığı için `keyInfo` sonrasına 3 bayt ve `data8` sonrasına 1 bayt açık dolgu eklenmeli. Deneme programı dolgu olmadan sessizce başarısız oldu.

### 6.3 Sensör adlandırma

- İki kaynak birleştirilir:
  1. SMC `T*` anahtarları.
  2. IOHIDEventSystemClient üzerinden okunan Apple Silicon sıcaklık sensörleri. Bu özel bir API; sensörlerin "PMU tdie…", "NAND CH0 temp" gibi okunabilir adları var.
- Bilinen anahtar ve ad kalıpları bir eşleme tablosuyla anlaşılır adlara ve gruplara çevrilir (ör. "CPU P-çekirdek 3", "SSD", "Wi-Fi"). Tablo çip ailesine göre genişletilebilir bir veri dosyası olmalı ki topluluk katkısı kolay olsun.
- Eşleşmeyen sensörler "Diğer" grubunda ham adıyla gösterilir. Kullanıcı her sensörü yeniden adlandırabilir.
- Aynı fiziksel noktayı iki kaynak da veriyorsa yinelenen kayıt gösterilmez. Hangi kaynağın tercih edileceği builder'a kalmıştır.

### 6.4 Veri ve kalıcılık

- Profiller, sensör tercihleri (yıldız, ad, gizli) ve ayarlar uygulama tarafında JSON ya da UserDefaults ile saklanır.
- Etkin profil yardımcı servise gönderilir. Servis, yeniden başladığında bağlı bir uygulama yoksa fanları Otomatik'e alır (§7).
- Geçmiş grafiği bellekte en fazla 1 saatlik halka tamponda tutulur.

## 7. Güvenlik kuralları (pazarlığa kapalı)

1. **Uygulama bağlantısı koparsa** (çıkış, çökme, öldürme) yardımcı servis birkaç saniye içinde tüm fanları Otomatik'e alır. Arka planda profili sürdürmek ancak uygulama çalışırken geçerlidir.
2. **Uyku ve uyanma:** Uyku öncesinde fanlar Otomatik'e alınır. Uyanınca, uygulama bağlıysa etkin profil yeniden uygulanır.
3. **Yardımcı servis sonlanırken** (SIGTERM, kaldırma, güncelleme) fanlar Otomatik'e alınır.
4. **Sensör okunamazsa** ya da değer saçmaysa (NaN, 0, 150°C üstü), o sensöre bağlı kural devre dışı kalır. Fanı yöneten hiçbir kural geçerli değilse fan Otomatik'e döner.
5. **Kritik sıcaklık tavanı:** Yardımcı servis, kendi sabit **güvenlik sensörü kümesini** izler. Bu küme, doğrulanmış CPU ve GPU kalıp (die) sensörlerinden oluşur. Kullanıcı bu sensörleri gizleyemez ve profil ayarları onları etkilemez; şüpheli `TPD*` gibi anahtarlar kümeye girmez. Girdi, kümenin en yüksek değerinin **5 saniyelik hareketli ortalamasıdır**, böylece anlık sıçramalar tetiklemez. Bu ortalama 100°C'yi aşarsa, profil ne derse desin fan max devre alınır. Ortalama 90°C'nin altına inince profile geri dönülür. *(Benim kararım: Sensör kümesi ve ortalama süresi yazma testi sırasında gerçek yük altında doğrulanmalı.)*
6. **Sabit devir, fanın gerçek min–max aralığına sıkıştırılır.**
7. Sabit devirde de 5. kural geçerlidir.

Bu kuralların her biri birim testle (sahte SMC ile) ve elle test listesiyle doğrulanmalı.

## 8. Derleme, imza ve dağıtım

- **Proje yapısı:** Xcode 27.2 ile derlenir. Proje dosyası XcodeGen `project.yml` ile üretilir (makinede `/opt/homebrew/bin/xcodegen` kurulu); `.xcodeproj` depoya girmez. *(Benim kararım: tekrarlanabilir ve birleştirme çakışması çıkarmayan bir proje dosyası için.)*
- **Xcode yolu:** Makinede `xcode-select` komut satırı araçlarını gösteriyor. Betikler `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` ile çalışmalı ve sistem ayarı değiştirilmemeli.
- **Hedefler:** `Boreas` (uygulama), `BoreasHelper` (daemon), `BoreasCore` (paylaşılan model, eğri mantığı, SMC katmanı; test edilebilir framework ya da Swift paketi), `BoreasTests`.
- **Dil ve sürüm:** Swift 6, SwiftUI. En düşük macOS sürümü builder'ın kararıdır; macOS 15 ya da üstü önerilir, Apple Silicon zorunludur.
- **İmza:**
  - Kullanıcının Apple geliştirici hesabı Xcode'da açık. Kullanıcı "developer imzam var" dedi; bu, ücretli Apple Developer Program üyeliği olarak kabul edildi. Developer ID ve noter onayı için bu üyelik gerekir. Ama bu Mac'in anahtar zincirinde **henüz imza sertifikası yok**. Geliştirme sırasında SMAppService daemon kaydı için imzalı derleme gerekir.
  - Kullanıcı Xcode → Settings → Accounts → Manage Certificates üzerinden önce **Apple Development**, sürüm için **Developer ID Application** sertifikası oluşturur. Bu adım kullanıcıya aittir; plan, buna gelmeden önce kullanıcıyı uyarmalı.
- **Sürüm akışı (yerel betik):**
  1. Release derlemesi.
  2. Developer ID ile imza (hardened runtime).
  3. `notarytool` ile noter onayı (kimlik bilgisi `notarytool store-credentials` profiliyle, kullanıcı oluşturur).
  4. Staple.
  5. DMG ya da zip.
  6. `gh release create`.
- **GitHub:** Depo `dikeckaan/boreas` (ad şu an boş), herkese açık, MIT lisanslı. Deponun oluşturulması ve ilk push kullanıcı onayıyla yapılır. README İngilizce ve Türkçe olur; kurulum, ilk açılıştaki onay adımı, desteklenen ve test edilmiş Mac'ler, güvenlik kuralları ve katkı rehberini (sensör eşleme tablosu) içerir.

## 9. Test

- **Birim testleri (BoreasCore):**
  - Eğri interpolasyonu.
  - "En yüksek kural kazanır" birleştirmesi.
  - Histerezis ve yumuşak geçiş.
  - Kritik tavan.
  - Geçersiz sensör davranışı.
  - SMC veri tipi kodlama ve çözme (flt, ui8, ui32, fpe2 vb.).
  - Profil JSON kodlaması.
- **Donanım soyutlaması:** `SMCClient` protokolü ve test için sahte SMC. Kontrol döngüsü ve güvenlik kuralları sahte SMC ve sahte saatle test edilir.
- **Elle test listesi (bu Mac'te):**
  - Okuma.
  - Elle moda geçip geri dönme.
  - Sabit devir.
  - Profil.
  - Uygulamayı öldürünce Otomatik'e dönme.
  - Uyku ve uyanma.
  - Servisi kaldırınca Otomatik'e dönme.

## 10. Builder'a kalanlar

- Kesin eğri değerleri, renk eşikleri ve animasyonlar.
- Sensör okumanın uygulamada mı yoksa serviste mi yapılacağı (kontrol döngüsü her durumda serviste).
- Kalıcılık biçimi.
- En düşük macOS sürümü.
- XPC arayüzünün kesin imzaları.
- Kod organizasyonu.
- Logonun son çizimi ve simge setinin üretimi.
