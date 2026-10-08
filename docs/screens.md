# Latent · Ekran envanteri

**Durum:** 8 Ekim 2026 · `agent/ui` ikinci tur (film kenarı + tarih damgası)  
**Amaç:** Her ekranın bugün kodda ne yaptığını, PRD §7 ile farklarını ve Mert'le konuşulacak açık tasarım sorularını tek yerde toplamak. Ekran sohbetinin başlangıç noktasıdır; kararlar alındıkça bu dosya güncellenir.

Akış: **Arşiv → (Yeni rulo) → Kamera** ve **Arşiv → Albüm → Tek kare**. Kamera hem arşivden hem albümden tam ekran açılır.

| Ekran | Dosya | Sahip |
|---|---|---|
| Arşiv | `Latent/ArchiveView.swift` (`ArchiveView`) | UI |
| Yeni rulo | `Latent/ArchiveView.swift` (`NewRollView`) | UI |
| Kamera | `Latent/CameraView.swift` | Kamera ajanı |
| Albüm | `Latent/AlbumView.swift` (`AlbumView`) | UI |
| Tek kare | `Latent/AlbumView.swift` (`PhotoDetailView`) | UI |
| Ortak bileşenler | `Latent/DesignSystem.swift` | UI |

## Alınan kararlar

### Film kenarı ve tarih (Mert, 8 Ekim 2026)
Gerçek film kenar baskısı hissi için kenar yazısı **film + kare + tarih** taşır; tarih ayrıca eski kompakt kameralardaki gibi fotoğrafın köşesine turuncu damga olarak basılır. İkisi de **yalnızca gösterimdir**: kaydedilen JPEG'lere (orijinal, geliştirilmiş, küçük önizleme) işlenmez.

| Öğe | Biçim | Nerede | Kaynak |
|---|---|---|---|
| Kenar, tam | `LATENT COLOR 400 ▸ 07 ▸ 08.10.26` | Arşiv kapağı, tek kare, kamera vizörü, çerçeveli paylaşım | `roll.film` (asla sabit yazılmaz), `frame.number`, `frame.capturedAt` |
| Kenar, kompakt | `400 ▸ 07 ▸ 08.10.26` | Albüm ızgarası | Film adının son kelimesi |
| Köşe damgası | `'26 10 08` | Tek kare, kamera vizörü (bugünün tarihi), çerçeveli paylaşım | `frame.capturedAt` / kamera için `Date()` |

- Tarihler kullanıcının saat diliminde (`TimeZone.autoupdatingCurrent`), POSIX biçiminde: kenarda `dd.MM.yy`, damgada `'yy MM dd`.
- Kamera vizöründe kenar ve damga **bugünün** tarihini gösterir (çekilecek kare bugünün tarihini alacak).
- Damga: sağ alt köşe, monospaced semibold, `LatentTheme.orange`'dan biraz daha kırmızı/parlak LED rengi, hafif ışıma. Punto fotoğrafın uzun kenarının %3,2'si: küçük ve büyük gösterimde aynı oranda görünür. Özel font dosyası yok. VoiceOver'dan gizli (tarih kare etiketinde zaten okunuyor).
- Gerçek film markası (Kodak/Fujifilm) adı kullanılmaz (PRD §8/§13).
- Tek kaynak: `FilmImprint` (`DesignSystem.swift`). Ekran ve `PhotoProcessor.framedExport` aynı biçimi ve oranı kullanır.

**Albüm ızgarası gerekçeleri**
- *Kompakt kenarda tarih kalıyor.* İki sütunda bir kare yaklaşık 160 pt genişliğinde; 7 pt monospaced `400 ▸ 07 ▸ 08.10.26` (19 karakter) yaklaşık 90 pt tutuyor, delik sırasına değmeden sığıyor. Küçük ekranlar için güvenlik olarak `minimumScaleFactor(0.7)` var. Tarih düşerse kontakt baskıda günler arası geçiş (gezinin hangi günü) kayboluyordu; kenar zaten tek tarih taşıyıcısı.
- *Köşe damgası ızgarada yok.* Uzun kenarın %3,2'si ızgarada yaklaşık 5–7 pt'ye düşüyor: okunmuyor, sadece turuncu leke gibi duruyor ve 36 karede görsel gürültü yapıyor. Tarih bilgisi kenarda var; damga tek karede tam boyutta anlam kazanıyor.

---

## 1. Arşiv

### Bugün
- Üstte `latent•` markası ve dekoratif `PHOTO SYSTEM / 01` etiketi; altında "KİŞİSEL FOTOĞRAF ARŞİVİN" + büyük "Arşivin." başlığı.
- Yükleniyor / okunamadı (tekrar dene) / boş durumları var. Boş durum: kesikli çizgili alan, "İlk hikâyen burada başlayacak.", "İlk rulonu başlat".
- Rulolar tek sütun, en yeni üstte. Her kapak: film çerçeveli **kapak karesi** (`roll.coverFrame`; kenarında film ▸ kare ▸ tarih) (kare yoksa gri alan + "İlk kareyi çek"), rulo adı, **oluşturma** tarihi, ok ikonu, alt satırda durum noktası (turuncu = devam, gri = tamam), `COLOR 400 · 35 mm FİLM` ve `07 / 36` sayaç.
- Alt çubuk: "Arşiv · N RULO", ortada turuncu kamera düğmesi, sağda "Yeni rulo".
- Kamera düğmesi listedeki **ilk** devam eden ruloyu açar (ilk = en son oluşturulan); yoksa yeni rulo sayfasını açar.

### PRD §7.1 ile farklar
- ✅ Boş durum, kapak, siyah çerçeve + altın işaretler, ad/tarih/film/sayaç, devam/tamam durumu, kamera ve yeni rulo eylemleri.
- ⚠️ Kapak her zaman ilk kare; seçilemiyor (PRD §16 açık soru).
- ⚠️ Tarih ruloyu oluşturma tarihi; gezinin tarih aralığı (ilk–son kare) değil.
- ⚠️ Devam eden ve tamamlanan rulolar aynı listede; yalnızca 6 pt'lik nokta ve metinle ayrışıyor.
- ⚠️ Aynı anda birden fazla devam eden rulo olabiliyor; kamera düğmesinin hangisini açacağı kullanıcıya görünmüyor.
- ❌ Rulo silme ve ad değiştirme yok (depolama API'si bekleniyor, bkz. "Sonraki tur").

### Açık sorular
1. **Kapak seçimi:** Varsayılan ilk kare mi, son kare mi? Seçim nereden yapılır — albümde kareye uzun basma ("Kapak yap"), tek kare ekranında menü, yoksa albüm başlığındaki kapağa dokunup seçici mi?
2. **Devam eden rulo öne çıksın mı?** Üstte ayrı, daha büyük bir "Şu an yüklü film" kartı + altta tamamlananlar arşivi gibi iki katmanlı bir düzen?
3. **Birden fazla aktif rulo** serbest mi? Değilse yeni rulo başlatırken mevcut ruloyu bitirme/bırakma sorusu mu sorulur?
4. Kapakta tarih: oluşturma tarihi mi, "12–18 Eki 2026" gibi aralık mı?
5. `PHOTO SYSTEM / 01` kalsın mı, anlamlı bir bilgiye mi dönüşsün (ör. toplam kare)?
6. Liste uzadığında (10+ rulo) yine tek sütun büyük kapak mı, yıl/ay başlıkları mı?

---

## 2. Yeni rulo

### Bugün
- Sistem `Form` sayfası (sheet): ad alanı ("Örneğin London"), sabit bilgiler — Film: Latent Color 400 · Kapasite: 36 kare · Format: **35 mm film** · 3:2 / 2:3 — ve "Filmi tak" düğmesi.
- Kaydedince sheet kapanır ve kamera tam ekran açılır.

### PRD §6 / §9 ile farklar
- ✅ Ad zorunlu, film bilgisi gösteriliyor, kamera hemen açılıyor.
- ⚠️ 60 karakter sınırı UI'da görünmüyor; depolama katmanı sessizce kesiyor.
- ⚠️ Görsel olarak tamamen standart iOS formu; ürünün film/kamera dili burada yok.

### Açık sorular
1. "Filmi tak" anı bir ritüel mi olmalı (film kutusu, rulonun kameraya sarılması, kısa haptic) yoksa sade form mu kalsın?
2. 60 karakter: sayaç mı gösterelim, sınırda mı keselim?
3. İleride film seçimi gelince (Faz 3) bu sayfa film kutularından seçim ekranına mı dönüşecek? Şimdiden yer ayıralım mı?

---

## 3. Kamera *(Kamera ajanının dosyası — burada yalnızca gözlem)*

### Bugün
- Üst: geri düğmesi (rulo adı) + `07 / 36` sayaç. Ortada film çerçeveli canlı önizleme (iç alan 2:3 / 3:2). Altında `1× · SABİT KADRAJ` ve film adı. Vizör kenarında film ▸ sıradaki kare ▸ bugünün tarihi, köşede turuncu tarih damgası (yalnızca gösterim). Turuncu deklanşör, son çekilen karenin küçük önizlemesi, "N. KARE KAYDEDİLDİ".
- Hata durumları: izin reddi → Ayarlar, kesinti → tekrar dene, kayıt hatası → kaydı yeniden dene.

### PRD §7.2 ile farklar / notlar
- ✅ Önizleme, film çerçevesi, ad + sayaç, zoom yok, 44 pt+ deklanşör, kayıt sürerken devre dışı.
- ✅ Sayaç ve film adı modelden geliyor (`roll.counterText`, `roll.filmShortName`).
- ⚠️ Vizördeki tarih ekran yeniden çizildikçe güncellenir; kamera gece yarısını geçerek açık kalırsa bir sonraki çizime kadar eski tarih görünebilir.
- ⚠️ 36. kare çekildiğinde yalnızca "Rulo tamamlandı" metni çıkıyor; tamamlanma anı tasarlanmadı.

### Açık sorular
1. **Rulo tamamlanma anı** (36. kare veya erken bitirme): kamera ekranında kısa bir "film sarılıyor" animasyonu + haptic, ardından otomatik olarak albüme mi geçelim? İkinci rulo önerisi (PRD §16) burada mı, albümde mi?
2. Son 3–5 karede sayaç uyarısı (renk/ton değişimi) olsun mu?

---

## 4. Albüm

### Bugün
- Başlık: `N KARE · 35 mm FİLM`, büyük rulo adı, film adı.
- Kareler **iki sütun düzenli ızgara**; her karede kompakt film kenarı (`400 ▸ 07 ▸ 08.10.26`; köşe damgası yok, gerekçe yukarıda) ve altında tekrar kare numarası. Dikey/yatay kareler kendi oranını koruyor.
- Altta "N BOŞ KARE" ya da "RULO TAMAMLANDI". Devam eden ruloda sağ üstte "Ruloyu bitir" (onay penceresi korunacak/kullanılamayacak kare sayısını söylüyor) ve altta deklanşör.

### PRD §7.3 ile farklar
- ✅ Oranlar korunuyor, film kenarı + numara, kalan kare sayısı, tamamlanan rulo kare kabul etmiyor.
- ❌ "Düzenli fakat tamamen mekanik olmayan kontakt baskı ritmi" yok — şu an tamamen mekanik ızgara.
- ⚠️ Dikey ve yatay kareler aynı sütun genişliğinde olduğu için yatay kareler çok küçük, satırlarda yükseklik boşlukları oluşuyor.
- ⚠️ Kare numarası hem film kenarında hem altında; tekrar.
- ❌ Kare silme, kapak seçimi, rulo adını değiştirme/silme yok.

### Açık sorular
1. **Kontakt baskı ritmi:** Hangi "mekanik olmayan" yaklaşım?
   - (a) Gerçek kontakt baskı gibi şeritler: 6'lı sıralar halinde film şeridi, yatay kareler tam genişlik, dikeyler yan yana.
   - (b) Oran duyarlı sıra yerleşimi: yatay kare tek başına satır, iki dikey yan yana; ritmi kare sırası belirler.
   - (c) Sabit ızgara + hafif, kareye bağlı (deterministik) eğim/kayma — kâğıda elle dizilmiş baskılar hissi. Her açılışta aynı görünmeli.
   - (d) Karışık ölçek: rulonun kapağı/ilk karesi büyük, gerisi küçük.
2. Albümün üst kısmında kapak karesi büyük gösterilsin mi (albümün "kapağı")?
3. **Silme akışları:** Kare silme albümde mi (uzun bas → bağlam menüsü) yoksa yalnızca tek kare ekranında mı? Silinen karenin numarası boşalır mı (film gerçekliği: kare "yanmış" olur, sayaç geri gelmez) yoksa kareler yeniden numaralanır mı? Rulo silme yalnızca arşivde mi?
4. Tamamlanmış rulonun albümü farklı görünsün mü (ör. "banyo edilmiş" kâğıt dokusu, tarih aralığı, kare sayısı özeti)?
5. "Ruloyu bitir" sağ üstte metin düğmesi olarak mı kalsın, yoksa sayfa sonunda daha ağır bir eylem mi?

---

## 5. Tek kare

### Bugün
- Film çerçeveli geliştirilmiş fotoğraf (kenar `LATENT COLOR 400 ▸ 07 ▸ 08.10.26`, sağ altta `'26 10 08` damgası), altında rulo adı + tarih, sağda `COLOR 400 / 07 / 36` (`roll.film` ve `FilmRoll.capacity`'den).
- Çerçeveli paylaşım çıktısı aynı kenar yazısını ve köşe damgasını taşır; orijinal paylaşım damgasızdır.
- Sağ üstte paylaş menüsü: "Film çerçevesiyle paylaş" (uygulama içinde render) ve "Orijinali paylaş".

### PRD §7.4 ile farklar
- ✅ Büyük fotoğraf, film çerçevesi, film adı, rulo adı, tarih, kare numarası; iki paylaşım seçeneği.
- ❌ **Paspartu göster/gizle seçeneği yok.**
- ⚠️ Kareler arasında kaydırarak geçiş yok; her kare için albüme dönmek gerekiyor.
- ✅ Çerçeveli dışa aktarım film adını ve çekim tarihini rulodan/kareden alıyor (`framedExport(…, film:, capturedAt:)`).
- ❌ Kare silme / kapak yapma eylemi yok.

### Açık sorular
1. Paspartu: ekranda bir anahtar mı, fotoğrafa dokununca geçiş mi? Paylaşım çıktısı da bu seçimi mi izlesin?
   - Tarih damgası da bu anahtara bağlansın mı (ör. "damgalı / temiz" gösterim ve paylaşım)? Şu an her zaman açık.
2. Sola/sağa kaydırma ile önceki/sonraki kareye geçiş eklensin mi?
3. Tek kare ekranının arka planı: beyaz kâğıt mı, karanlık "ışık masası" mı?
4. Kare bilgisi (çekim saati, yön) ne kadar detaylı gösterilsin?

---

## Ortak: erişilebilirlik (bu tur)

- **VoiceOver:** Rulo kapağı tek öğe olarak okunur ("London, 12 Eki 2026, 7 kare, devam ediyor, 29 kare kaldı"); albüm ve tek karedeki kareler "London, kare 7, 12 Eki 2026" olarak okunur. Film kenarı yazısı, köşe tarih damgası, altın delikler, ok ikonu, durum noktası ve `PHOTO SYSTEM / 01` gizli. "Arşivin." ve albüm başlığı header.
- **Dynamic Type:** Büyük başlıklar (`latent`, "Arşivin.", rulo adları) `displayFont` ile ScaledMetric üzerinden ölçeklenir. Film kenarı yazısı (7–9 pt) bilinçli olarak sabit: baskı dokusunun parçası ve VoiceOver'dan gizli.
- **Dokunma alanı:** "Yeni rulo" en az 44 pt. Deklanşörler 58–82 pt.
- Kamera ekranının erişilebilirliği Kamera ajanında.

## Sonraki tur (depolama PR'ı birleşince)

Depolama ajanı (`agent/storage`) `LibraryModel`'e rulo/kare silme, rulo adını değiştirme ve kapak seçimi API'leri ekliyor. O PR birleşince UI tarafında yapılacaklar — yukarıdaki açık sorulara Mert'le karar verildikten sonra:

- [ ] Arşiv: rulo bağlam menüsü (ad değiştir, sil) + silme onayı.
- [ ] Albüm/tek kare: kare silme akışı ve onayı.
- [ ] Kapak seçimi UI'ı ve arşiv kapağının seçilen kareyi göstermesi.
- [ ] Albüm başlığında ad düzenleme (60 karakter sınırı görünür).
