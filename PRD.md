# Latent — Ürün Gereksinimleri Dokümanı

**Sürüm:** 0.1 MVP  
**Tarih:** 8 Ekim 2026  
**Durum:** Tasarım yönü seçildi, ilk SwiftUI/AVFoundation prototipi hazır; gerçek cihaz doğrulaması bekliyor.  
**Platform:** iOS 17+  
**Ürün tipi:** Kamera + kişisel fotoğraf albümü

## 1. Ürün özeti

Latent, telefon kamerasını seçilmiş bir film ve sabit bir kadraj deneyimine dönüştürür. Kullanıcı bir gezi için 36 karelik bir rulo başlatır, aynı görsel karakterle fotoğraf çeker ve gezi sonunda otomatik oluşan bir hatıra albümüne sahip olur.

Ürün vaadi:

> Gezerken çek. Hatıra albümün kendiliğinden oluşsun.

Latent’in ilk amacı yeni bir sosyal ağ kurmak değildir. Kullanıcı, kimse onu takip etmese de güzel bir gezi albümü oluşturmak için uygulamayı açabilmelidir. Paylaşım, bu albümün doğal çıktısıdır.

## 2. Problem ve içgörü

Telefon kameraları fotoğraf çekmeyi kolaylaştırdı; ancak gezilerde yüzlerce fotoğraf çekiliyor ve çoğuna tekrar dönülmüyor. Küçük dijital kameraların ve analog fotoğraf estetiğinin yeniden ilgi görmesi, insanların daha sınırlı, karakterli ve özel bir çekim deneyimi aradığını düşündürüyor.

Latent şu ihtiyacı karşılamayı hedefler:

> Bir geziyi sıradan telefon fotoğrafları yığını olarak değil, ortak görsel dile sahip tamamlanmış bir koleksiyon olarak saklamak.

Bu hâlâ doğrulanacak bir ürün hipotezidir. MVP’nin amacı bu hissin gerçek kullanımda karşılık bulup bulmadığını görmek.

## 3. Hedef kullanıcı

İlk hedef kullanıcı:

- Gezi ve şehir yürüyüşlerinde fotoğraf çeken iPhone kullanıcıları.
- Film, analog kamera ve küçük dijital kamera estetiğini seven kişiler.
- Fotoğrafçı olmak zorunda kalmadan daha tutarlı ve özenli seriler üretmek isteyenler.
- Fotoğraflarını paylaşmak isteyen ama önce kendi arşivinde anlamlı bir bütün görmek isteyenler.

MVP’de profesyonel fotoğrafçılar, sosyal ağ yaratıcıları ve topluluk yöneticileri özel hedef kitle değildir.

## 4. Ürün ilkeleri

1. **Kısıt, karakter üretir.** Rulo kapasitesi ve sabit kadraj bilinçli seçim yapmayı destekler.
2. **Önce tek başına değer.** Kullanıcı sosyal özellik olmadan da bir gezi albümü oluşturabilmelidir.
3. **Fotoğraf kadar sunum da üründür.** Film kenarı, kare numarası ve albüm düzeni temel deneyimin parçasıdır.
4. **Native iOS davranışı, özel görsel dil.** Navigasyon ve izin akışları iOS’a tanıdık gelir; film ve kamera yüzeyi Latent’e özgüdür.
5. **Orijinal korunur.** Latent’in kırpılmış ve işlenmiş kopyası kullanılır; orijinal fotoğraf kaybolmaz.
6. **Kullanıcı kontrolü.** Fotoğrafın iPhone Fotoğraflar’a aktarılması ve paylaşılması otomatik yapılmaz; kullanıcı seçer.

## 5. MVP kapsamı

### Dahil

- Tek cihazda çalışan kişisel fotoğraf arşivi.
- Yeni rulo oluşturma ve isim verme.
- 36 karelik rulo sınırı.
- İlk film görünümü: `Latent Color 400`.
- Arka ana kamera, sabit 1× kadraj; zoom kontrolü yok.
- Dikey 2:3 ve yatay 3:2 çekim.
- Kamera önizlemesinde film çerçevesi.
- Skeuomorfik turuncu deklanşör ve çekimde haptic feedback.
- Fotoğrafı orijinal, geliştirilmiş ve küçük önizleme olarak cihazda saklama.
- Arşiv ekranı.
- Albüm/kontakt baskı ekranı.
- Tek fotoğraf ekranı.
- Film çerçeveli veya orijinal fotoğrafı sistem paylaşım ekranına gönderme.
- Ruloyu 36 kare dolmadan bitirme; çekilmiş kareleri koruma.
- Kamera izni, kamera hatası, oturum kesintisi ve kayıt hatası durumları.

### MVP dışında

- Kullanıcı hesabı ve bulut senkronizasyonu.
- Online portfolyo, takip, keşfet ve community.
- Çoklu cihaz desteği.
- Kodak/Fujifilm isimli film benzetimleri.
- Lens seçimi: 35 mm, 50 mm, 18–55 mm.
- Gerçek zamanlı film filtresi ve gren önizlemesi.
- Video, RAW, manuel pozlama ve manuel netleme.
- Baskı siparişi.
- Ödeme, abonelik ve premium paketler.
- Bildirimler, widget ve sosyal giriş.

## 6. Ana kullanıcı akışı

### İlk kullanım

1. Kullanıcı Latent’i açar.
2. Arşiv boşsa “İlk rulonu başlat” çağrısını görür.
3. Ruloya isim verir; örneğin `London`.
4. Film bilgisi gösterilir: `Latent Color 400 · 36 kare · 35 mm`.
5. Kamera izni istenir ve kamera ekranı açılır.

### Gezi sırasında çekim

1. Kullanıcı gözüne bir kadraj kestirir.
2. Latent’i açar; aktif rulo ve aynı kamera kurulumu hazırdır.
3. Kamera 1× çalışır; zoom kontrolü bulunmaz.
4. Kullanıcı telefonu dikey veya yatay tutar. Film iç kadrajı 2:3 veya 3:2 olur.
5. Kullanıcı turuncu deklanşöre basar.
6. Düğme görsel olarak içeri hareket eder, kısa haptic oluşur.
7. Fotoğraf işlenir ve aktif ruloya eklenir.
8. Sayaç bir artar; örneğin `07 / 36`.
9. Uygulamadaki fotoğraf film çerçevesiyle arşivde görünür.

### Rulo bitirme

1. Kullanıcı albüm ekranında “Ruloyu bitir” seçeneğine basar.
2. Latent kaç fotoğrafın korunacağını ve kalan karelerin kullanılamayacağını açıkça gösterir.
3. Onay sonrası rulo kapanır; yeni fotoğraf eklenemez.
4. 36. karede rulo otomatik tamamlanır.

### Geri dönme ve paylaşma

1. Kullanıcı arşivden `London` kapağını açar.
2. Albümde kareleri kontakt baskı düzeninde görür.
3. Tek kareye girer; film kenarı ve paspartulu sunumu inceler.
4. İster çerçeveli çıktıyı, ister orijinali paylaşır.

## 7. Ekran gereksinimleri

### 7.1 Arşiv

- Boş durumda ilk rulo oluşturma çağrısı.
- Her rulo için kapak fotoğrafı.
- Kapakta siyah film çerçevesi ve altın kenar işaretleri.
- Rulo adı, tarih, film adı ve kare sayısı.
- Devam eden ve tamamlanan rulo durumu.
- Kamera açma ve yeni rulo başlatma eylemleri.

### 7.2 Kamera

- Arka kamera önizlemesi.
- Önizlemenin iç alanı kaydedilen fotoğrafın oranıyla eşleşmeli.
- Film çerçevesi kamera önizlemesini çevrelemeli.
- Rulo adı ve sayaç görünür olmalı.
- Zoom ve lens seçimi olmamalı.
- Deklanşör en az 44 pt dokunma alanına sahip olmalı.
- Hızlı ardışık dokunuşlar tek bir çekim olarak işlenmeli; kayıt sürerken düğme devre dışı kalmalı.
- Kamera izni reddedilirse neden ve Ayarlar’a geçiş gösterilmeli.

### 7.3 Albüm

- Dikey ve yatay kareler kendi oranlarını korumalı.
- Her karede film kenarı ve kare numarası görünmeli.
- Kareler düzenli fakat tamamen mekanik olmayan bir kontakt baskı ritmi taşımalı.
- Aktif ruloda kalan kare sayısı görünmeli.
- Tamamlanan rulo yeni kare kabul etmemeli.

### 7.4 Tek kare

- Fotoğraf büyük ve okunabilir gösterilmeli.
- Film çerçevesi, film adı, rulo adı, tarih ve kare numarası görünmeli.
- Paspartu göster/gizle seçeneği bulunmalı.
- Orijinal paylaşım ve çerçeveli paylaşım seçenekleri bulunmalı.

## 8. Görsel dil

Seçilen yön modern konsepttir:

- Beyaz ve kırık beyaz yüzeyler.
- Siyah film çerçeveleri.
- Turuncu vurgu ve deklanşör.
- Altın film işaretleri.
- Serifsiz, sade ve teknik bilgi için monospaced yazı.
- Geniş boşluklar ve fotoğrafa ayrılmış alan.
- Braun/Dieter Rams çizgisinde az ve anlaşılır kontrol.
- Skeuomorfizm yalnızca deklanşör gibi fiziksel hissin değer kattığı noktalarda.

İlk film görünümü `Latent Color 400` yalnızca özgün bir renk işleme denemesidir. Gerçek bir Kodak veya Fujifilm ürünü olduğu iddia edilmez; marka isimleri ve lisans konusu sonraki fazda ayrıca değerlendirilir.

## 9. Fonksiyonel gereksinimler

### Rulo

- Sistem aynı anda birden fazla rulo saklayabilmeli.
- Bir rulo en fazla 36 kare içermeli.
- Rulo adı boş bırakılamamalı; en fazla 60 karakter olmalı.
- Rulo kapatıldığında çekilmiş kareler korunmalı.
- Kapatılan rulo yeniden açılabilmeli fakat yeni kare kabul etmemeli.

### Fotoğraf saklama

- Orijinal JPEG korunmalı.
- Geliştirilmiş/kırpılmış JPEG saklanmalı.
- Albüm için küçük önizleme saklanmalı.
- Veriler `Application Support/Latent/` altında tutulmalı.
- Manifest atomik yazılmalı.
- Fotoğraf dosyaları yazılamazsa sayaç artmamalı.
- Bozuk manifest otomatik olarak boş arşivle değiştirilmemeli.

### Fotoğraf işleme

- EXIF yönü normalize edilmeli.
- Dikey çekim 2:3, yatay çekim 3:2 merkez kırpılmalı.
- İlk görünümde hafif doygunluk, kontrast ve parlaklık ayarı uygulanmalı.
- Canlı kamera önizlemesi ilk MVP’de filtresiz olabilir; kayıtlı çıktı işlenmiş olmalı.

### Paylaşım

- Sistem paylaşım paneli kullanılmalı.
- Paylaşım varsayılan olarak otomatik başlamamalı.
- Çerçeveli çıktı uygulama içinde render edilmeli.
- Orijinal ve çerçeveli çıktı ayrı seçenekler olmalı.

## 10. Teknik yaklaşım

- **UI:** SwiftUI.
- **Kamera:** AVFoundation / `AVCaptureSession` / `AVCapturePhotoOutput`.
- **Haptic:** `UIImpactFeedbackGenerator` ile rigid impact; düğmeye basıldığı anda tetiklenir.
- **Görüntü işleme:** UIKit + Core Image.
- **Saklama:** JSON manifest + yerel JPEG dosyaları.
- **Minimum sürüm:** iOS 17.
- **İzin:** `NSCameraUsageDescription` mevcut.
- **Mimari sınır:** Kamera oturumu ayrı servis; rulo saklama actor tabanlı repository; ekranlar SwiftUI model katmanına bağlanır.

Mevcut kaynaklar [Latent.xcodeproj](/Users/merttoker/Documents/Codex/2026-09-14/sel/outputs/Latent/Latent.xcodeproj) altında bulunmaktadır. Kurulum ve cihaz kabul notları [README.md](/Users/merttoker/Documents/Codex/2026-09-14/sel/outputs/Latent/README.md) dosyasındadır.

## 11. MVP kabul kriterleri

MVP tamamlanmış sayılırsa:

- [ ] Xcode’da temiz Debug derlemesi alınır.
- [ ] Gerçek iPhone’a kurulup açılır.
- [ ] Kamera izni reddi ve tekrar izin verme akışı çalışır.
- [ ] Portre ve iki yatay yönde önizleme/kayıt yönü doğru olur.
- [ ] Önizleme kadrajı ile kaydedilen kadraj eşleşir.
- [ ] Deklanşör görseli basılı durumda içeri hareket eder.
- [ ] Çekimde hissedilir bir haptic oluşur; hızlı çift dokunuş çift kayıt oluşturmaz.
- [ ] Bir fotoğraf üç yerel dosya varyantıyla kaydedilir.
- [ ] Uygulama kapanıp açıldığında rulo ve fotoğraflar korunur.
- [ ] 36. kareden sonra 37. kare kabul edilmez.
- [ ] Rulo erken bitirildiğinde mevcut kareler silinmez.
- [ ] Arşiv, albüm ve tek kare görünümleri çalışır.
- [ ] Çerçeveli çıktı ve orijinal çıktı paylaşılabilir.
- [ ] VoiceOver, büyük yazı ve düşük bellek senaryoları gözden geçirilir.
- [ ] App Store gizlilik ve kamera açıklamaları son hâline getirilir.

## 12. Başarı ölçümü

İlk MVP testinde takip edilecek sinyaller:

- Kullanıcının ilk ruloyu oluşturup ilk kareyi çekme oranı.
- İlk çekimden sonra aynı ruloda ikinci ve beşinci kareye ulaşma oranı.
- Bir ruloyu en az 6 kareyle bitirme oranı.
- Kullanıcının albümü tekrar açma oranı.
- Çerçeveli çıktıyı veya orijinali paylaşma oranı.
- Kullanıcıların “kamera hissi”, “kısıtlayıcı kadraj” ve “albümün geri dönülebilir olması” hakkındaki nitel geri bildirimi.

İlk aşamada sosyal takipçi, beğeni ve günlük aktif kullanıcı sayısı ana başarı ölçütü değildir.

## 13. Riskler ve kararlar

### Beklemek yerine anında görme

İlk MVP’de fotoğraf çekildikten sonra kare albüme eklenir ve görülebilir. “Banyo edip topluca açma” fikri ürünün güçlü bir sonraki deneyi olarak saklanır. Böylece uygulama, fotoğrafı gizleyerek temel çekim motivasyonunu riske atmaz.

### Sabit lens hissi

MVP’de tek bir 1× kadraj vardır. 35 mm/50 mm seçimleri, gerçek cihaz eşdeğerleri ve görüntü kalitesi ölçüldükten sonra eklenmelidir. 35 mm film formatı ile 35 mm objektif eşdeğeri ayrı kavramlardır.

### Film markaları

Kodak veya Fujifilm benzetimleri ileride ücretli paket fikrine dönüşebilir. Lisans, marka kullanımı ve görünümün teknik olarak ne kadar doğru olduğu doğrulanmadan bu isimler MVP’ye alınmaz.

### Yerel saklama

İlk sürümde kullanıcı hesabı olmadığı için cihaz kaybında arşiv geri getirilemez. Bulut senkronizasyonu ürün doğrulamasından sonra ele alınmalıdır.

### Dosya bütünlüğü

Fotoğraf varlıkları ve manifest ayrı dosyalarda tutulduğu için süreç ani sonlandığında sahipsiz dosyalar oluşabilir. Bu durum mevcut fotoğrafları koruyacak şekilde ele alınır; sonraki fazda açılışta orphan asset temizliği eklenebilir.

## 14. Sonraki fazlar

### Faz 1 — MVP’yi cihazda doğrulama

- Xcode derlemesi, gerçek iPhone kamera testi ve yön/kadraj düzeltmeleri.
- Haptic zamanlaması ve düğme hissi.
- Fotoğraf işleme hızı ve bellek kullanımı.
- App icon, onboarding metni ve App Store temel hazırlığı.

### Faz 2 — Koleksiyon deneyimini güçlendirme

- Banyo modu deneyi.
- Rulo tamamlanma animasyonu.
- Birden fazla çerçeve/paspartu düzeni.
- Daha iyi film efekti ve gren.
- Fotoğraflar’a manuel kaydetme.

### Faz 3 — Görsel karakter seçenekleri

- Sabit 35 mm ve 50 mm kadrajları.
- Sınırlı film görünümleri.
- Film seçimini rulo başında kilitleme.
- Ücretli görünüm paketleri.

### Faz 4 — Paylaşım ve topluluk

- Paylaşılabilir albüm linki.
- Kişisel online portfolyo.
- Kullanıcı profili ve takip.
- Keşfet/community.

## 15. Gelir hipotezi

İlk ürün doğrulanmadan abonelik eklenmemeli. Kullanıcılar tekrar rulo başlatıyor ve yeni görünüm istiyorsa şu modeller test edilebilir:

- Tek seferlik Pro açılımı.
- Film görünümü paketleri.
- Premium albüm/çerçeve şablonları.
- Baskıya uygun yüksek çözünürlüklü çıktı.
- İleride bulut arşiv ve online portfolyo.

İlk ticari sinyal, kullanıcıların tek bir filtreyi denemesi değil; başka bir gezi için ikinci ruloyu başlatmasıdır.

## 16. Açık sorular

- Fotoğraf çekildikten sonra önizleme her zaman açık mı kalacak, yoksa banyo modu ayrı bir rulo seçeneği mi olacak?
- Rulo kapağı otomatik ilk kare mi olacak, yoksa kullanıcı kapak karesini seçebilecek mi?
- Rulo tamamlanınca ikinci rulo önerisi nasıl gösterilecek?
- Gerçek film markaları kullanılacaksa lisans ve isimlendirme yaklaşımı ne olacak?
- Yerel arşivin yedeklenmesi için iCloud/CloudKit hangi doğrulama sinyalinden sonra eklenecek?
- App Store ilk sürümünde yalnızca iPhone mu desteklenecek?

