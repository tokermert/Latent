# Latent · TestFlight yol haritası

**Hedef:** 10–20 kişilik kapalı TestFlight betası (PRD §12).
**Durum (8 Ekim 2026):** Dalga 1 `main`'de ve cihazda doğrulandı. Dalga 2 ajanlarda.

İşaretler: ✅ bitti · 🔄 ajanlarda · 👤 Mert · ⏸ Mert'in kararını bekliyor

---

## 1. Ürün özellikleri

| Durum | İş | Kim |
|---|---|---|
| ✅ | Rulo oluşturma, 36 kare sınırı, erken bitirme | — |
| ✅ | Kamera: sabit 1×, 2:3 / 3:2, cihaz yönünden kayıt, akıcı dönüş | Kamera |
| ✅ | Üç varyantla güvenli kayıt, v1 → v2 arşiv taşıma, sahipsiz dosya temizliği | Depolama |
| ✅ | Albüm, tek kare, çerçeveli / orijinal paylaşım | — |
| ✅ | VoiceOver ve büyük yazı ilk geçişi | UI |
| 🔄 | Film kenarında film adı, kare ve tarih; köşede tarih damgası (PR #5) | UI |
| 🔄 | Tek aktif rulo kuralı ve "önceki ruloyu bitir" onayı | Depolama + UI |
| 🔄 | Rulo / kare silme, ad değiştirme, kapak seçme (geçici iOS kalıplarıyla) | UI |
| 🔄 | Ayarlar menüsü: tarih damgası, Yardım, Gizlilik, Geri bildirim, Hakkında | UI |
| 🔄 | Rulo özeti (ölçüm) ve albüm/paylaşım sayaçları | Depolama + UI |
| 🔄 | Görüntü işleme performansı | Depolama |
| 🔄 | Kamera sağlamlığı: arka plana geçişte kayıt, bellek uyarısı, VoiceOver | Kamera |
| ⏸ | Ekran tasarımı kararları (`docs/screens.md`): kontakt baskı düzeni, rulo tamamlanma anı, paspartu, silme akışlarının son hâli | Mert + UI |
| ⏸ | UX incelemesi (ekran görüntüleriyle) | Mert → UX ajanı |

**TestFlight için zorunlu olanlar:** 🔄 satırlarının tamamı. ⏸ satırları betayı engellemez; geçici hâlleriyle beta açılabilir.

## 2. Yayın hazırlığı (teknik)

| Durum | İş | Kim |
|---|---|---|
| 🔄 | Geçici uygulama ikonu ve asset catalog | Kamera |
| 🔄 | `ITSAppUsesNonExemptEncryption = false` (her yüklemedeki şifreleme sorusunu kaldırır) | Kamera |
| 🔄 | `PrivacyInfo.xcprivacy` güncellemesi (UserDefaults) | Kamera |
| ✅ | Kamera izni açıklaması (`NSCameraUsageDescription`) | — |
| ✅ | Gizlilik politikası taslağı → `docs/privacy-policy.md` | Baş ajan |
| ✅ | TestFlight metinleri ve görüşme rehberi → `docs/testflight.md` | Baş ajan |

## 3. 👤 Mert'in yapacakları

Sıra önemli, çünkü ilk ikisi Apple tarafında birkaç gün sürebilir.

1. **Apple Developer Program üyeliği** — developer.apple.com/programs, yıllık $99. Onay 1–2 gün sürebilir. **Bunu hemen başlat.**
2. **Bundle ID kararı.** Örneğin `com.merttoker.latent`. Bir kez yüklendikten sonra değiştirilemez.
3. **Geri bildirim e-postası.** Örneğin `latent@…`. Uygulamadaki "E-posta gönder" satırına ve TestFlight'a yazılacak.
4. **Gizlilik politikası URL'si.** `docs/privacy-policy.md` metnini bir web sayfasına koy. Notion'da herkese açık bir sayfa ya da GitHub Pages yeterli. Harici test için Apple bu URL'yi istiyor.
5. **App Store Connect'te uygulama kaydı.** "My Apps → +", ad: Latent, dil: Türkçe, bundle ID.
6. **İlk yükleme.** Xcode → Product → Archive → Distribute App → TestFlight & App Store.
7. **Dahili test.** Kendin ve en fazla 100 ekip üyesi; inceleme gerektirmez.
8. **Harici test.** Testçi listesi ve Beta App Review. İlk inceleme yaklaşık 1 gün sürer. Metinler `docs/testflight.md`'de.
9. **Son ikon tasarımı.** İsteğe bağlı; beta geçici ikonla çıkabilir.
10. **Testçi bulma.** Önümüzdeki 4–6 hafta içinde gezisi olan 10–20 kişi (PRD §12).

## 4. Beta öncesi son kontrol (cihazda)

- [ ] Temiz kurulum: boş arşiv, ilk rulo, kamera izni, ilk kare
- [ ] Kamera izni reddedilir, sonra Ayarlar'dan açılır
- [ ] 36 kare doldurulur, 37. kare kabul edilmez
- [ ] Kare silinir, kare hakkı geri gelmez, numaralar korunur
- [ ] Aktif rulo varken yeni rulo başlatılır: onay penceresi çıkar, önceki rulo biter
- [ ] Rulo silinir, dosyaları da silinir
- [ ] Uygulama zorla kapatılıp açılır: veri kaybı yok
- [ ] Önceki sürümün arşiviyle güncelleme yapılır: rulolar korunur
- [ ] Rulo özeti paylaşılır: JSON'da rulo adı ve fotoğraf yok
- [ ] Çerçeveli paylaşım Instagram ve Mesajlar'da doğru görünür
- [ ] VoiceOver ile tam akış; en büyük yazı boyutu
- [ ] Eski bir cihazda (ör. iPhone 12) çekim hızı ve bellek
- [ ] Xcode → Product → Archive başarılı
