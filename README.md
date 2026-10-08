# Latent · İlk iOS geliştirme dilimi

Gezileri 36 karelik filmler halinde saklayan kişisel fotoğraf albümü.

## Durum

SwiftUI/AVFoundation proje taslağı hazırlanmıştır. **Gerçek iPhone’da henüz çalıştırılmadı; Xcode kurulumu ve ilk cihaz derlemesi bekleniyor.** Swift sözdizimi ve proje/plist yapısı kontrol edilmiştir; çekirdek işlevler için ayrı Swift kontrolleri bulunur.

## Açmak ve çalıştırmak

1. Xcode’u aç; ilk açılışı tamamla ve iOS platform desteğinin indirildiğini doğrula.
2. Bu klasördeki `Latent.xcodeproj` dosyasını Xcode ile aç.
3. `Latent` hedefinde **Signing & Capabilities → Team** altında kendi Apple hesabını seç. Gerekirse bundle identifier’ı benzersiz bir değerle değiştir; mevcut `com.example.Latent` geliştirme için yer tutucudur.
4. iPhone’u bağla, güven isteğini onayla ve gerekiyorsa telefonda Developer Mode’u aç. Hedef cihaz olarak iPhone’u seç, Run’a bas.
5. Uygulamada ilk rulonu oluştur ve kamera izni ver. iOS 17 veya üzeri hedeflenmiştir.

Xcode’un kurulumu, hesapla giriş ve cihaz güveni kullanıcı tarafından tamamlanmalıdır. App Store yayını bu aşamanın parçası değildir. Apple yönergeleri: [Xcode kurulumu](https://developer.apple.com/xcode/), [Cihazda çalıştırma](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

## Yazılan akış

- Rulo oluşturma ve 36 kare sınırı; film görünümü rulo boyunca sabit.
- Arka ana kamera, sabit 1×; zoom kontrolü yok. Otomatik netleme ve pozlama devam eder. “Sabit” ifadesi kadraj büyütmesini belirtir, netleme mesafesini değil.
- Dikey 2:3 ve yatay 3:2 merkez kadraj. Önizleme iç alanı bu oranda hazırlanır; gerçek cihazda önizleme/kayıt eşleşmesi ayrıca doğrulanmalıdır.
- Koyu yuvada turuncu fiziksel düğme hissi ve çekimde rigid haptic. Sistem haptic ayarları ve cihaz desteği sonucu etkiler.
- Orijinal JPEG + kırpılmış/işlenmiş JPEG + küçük önizleme cihaz içinde saklanır. iPhone Fotoğraflar arşivine otomatik kopyalanmaz.
- Beyaz albüm yüzeyleri, siyah film kenarları, altın kare işaretleri; arşiv → albüm → tek kare.
- Çerçeveli/paspartulu paylaşım çıktısı veya orijinali paylaşma. Dışarı aktarım yalnızca kullanıcının sistem paylaşım ekranında yaptığı seçimle gerçekleşir.
- Erken rulo bitirme onayı; çekilmiş kareler korunur.
- Kamera izni reddi, kamera yokluğu, oturum kesintisi, kayıt hatası durumları. Başarısız kayıtta işlenmiş fotoğraf bellekte tutulur ve tekrar kayıt denenebilir; uygulama zorla kapatılırsa bu henüz kaydedilememiş fotoğraf kaybolabilir.

## Tasarım kararı

Onaylanan yön: beyaz–turuncu–siyah, bol boşluk, serifsiz yazı; film kenarları her fotoğraf sunumunda görünür. Skeuomorfik detay deklanşörde yoğunlaşır. Bu tasarım bir Material/Figma kitaplığından aktarılmadı; seçilen konsept SwiftUI bileşenleriyle uygulanmıştır.

`Latent Color 400` ilk özgün görünüm denemesidir: hafif doygunluk/kontrast/parlaklık ayarı. Kodak/Fujifilm benzetimi veya kalibre edilmiş ISO/ASA davranışı iddiası yoktur. Canlı kamera şu anda filtrelenmemiş önizleme gösterir; görünüm kaydedilen kopyaya uygulanır. Film greni ve canlı efekt sonraki geliştirmeye açıktır.

## Kaynak yapısı

- `Latent/`: uygulama, tasarım bileşenleri, kamera, görüntü işleme ve ekranlar.
- `Core/Sources/LatentCore/`: rulo modelleri, kırpma hesabı ve dosya saklama. Aynı dosyalar Xcode hedefinde doğrudan derlenir.
- `Core/Tests/LatentCoreTests/`: XCTest regresyon senaryoları (Xcode gerekir).
- `Core/Checks/`: yalnızca Command Line Tools ile çalışabilen bağımsız kontroller.

Çekirdek kontrolleri:

```sh
cd Core
swift run LatentCoreChecks
```

Xcode kurulduktan sonra tam XCTest paketi:

```sh
cd Core
swift test
```

Dosyalar `Application Support/Latent/` altında tutulur. `library.json` atomik yazılır; yeni fotoğraf dosyaları yazıldıktan sonra sayaç güncellenir. Kaydetme hatasında yalnızca o çekime ait yeni dosyalar geri alınır. Okunamayan arşiv otomatik sıfırlanmaz. Ani süreç sonlandırmasının dosya yazımı ile manifest yazımı arasına denk gelmesi durumunda sahipsiz dosyalar kalabilir; bunlar mevcut fotoğrafları korumak için otomatik silinmez.

## Gerçek cihazda ilk kabul kontrolü

- [ ] Xcode’da temiz Debug derlemesi ve iPhone’a kurulum.
- [ ] İzni reddet → açıklama; Ayarlar’dan izin ver → kamera açılır.
- [ ] Portre, sağ yatay ve sol yatay çekimlerinde yazı/yön doğru.
- [ ] Kadrajın kenarına nesne yerleştir → önizleme ile kayıt eşleşir.
- [ ] Deklanşöre basılı tutma/release, haptic zamanlaması ve hızlı art arda dokunuş.
- [ ] Kaydet → uygulamayı kapat/aç → rulo ve fotoğraf korunur.
- [ ] Arka plana geç/dön, kamerayı başka uygulamada kullan/dön.
- [ ] 36. kare tamamlanır, 37. kare kabul edilmez; erken bitirme fotoğraf silmez.
- [ ] Albüm/tek kare düşük bellekli cihazda akıcıdır; büyük yazı ve VoiceOver kontrolü.
- [ ] Çerçeveli paylaşımın oranı, rengi ve yazıları hedef uygulamada doğru görünür.

Hesap, bulut, topluluk, lens seçimi, ödeme, app icon ve App Store hazırlıkları sonraki aşamadadır. `PrivacyInfo.xcprivacy` mevcut bağımlılıksız kapsamı yansıtır; yeni SDK/özellik eklenince yeniden gözden geçirilmelidir.
