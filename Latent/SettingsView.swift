import SwiftUI
import UIKit
import AVFoundation

enum LatentConfig {
    // TODO: Mert gerçek geri bildirim adresini verecek.
    static let feedbackEmail = "latent.feedback@example.com"
    static var feedbackMailURL: URL? {
        URL(string: "mailto:\(feedbackEmail)?subject=Latent%20geri%20bildirim")
    }
    /// "0.1.0 (1)"
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// Geçici menü: iOS yerleşik Form kalıbıyla. Nihai tasarım Mert'le konuşulacak (docs/screens.md).
struct SettingsView: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(FilmImprint.showStampKey) private var showDateStamp = true
    @State private var cameraDenied = SettingsView.isCameraDenied
    @State private var share: ShareItem?
    @State private var preparingSummary = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Tarih damgası", isOn: $showDateStamp)
                } footer: {
                    Text("Fotoğrafın köşesindeki turuncu tarih. Yalnızca ekranda ve çerçeveli paylaşımda görünür; fotoğraflarına işlenmez. Film kenarındaki tarih her zaman kalır.")
                }
                if cameraDenied {
                    Section {
                        Button { openSystemSettings() } label: { Label("Kamera iznini aç", systemImage: "camera") }
                    } footer: { Text("Latent'in kamerayı kullanma izni kapalı. Ayarlar'da açabilirsin.") }
                }
                Section {
                    NavigationLink { HelpView() } label: { Label("Yardım", systemImage: "questionmark.circle") }
                    NavigationLink { PrivacyView() } label: { Label("Gizlilik", systemImage: "hand.raised") }
                }
                Section {
                    Button { shareSummary() } label: {
                        HStack {
                            Label("Rulo özetini paylaş", systemImage: "square.and.arrow.up")
                            Spacer()
                            if preparingSummary { ProgressView() }
                        }
                    }.disabled(preparingSummary || !library.isLoaded)
                    if let mail = LatentConfig.feedbackMailURL {
                        Link(destination: mail) { Label("E-posta gönder", systemImage: "envelope") }
                    }
                } header: { Text("Geri bildirim") } footer: {
                    Text("Rulo özeti yalnızca kullanım sayılarından oluşur; fotoğraf, rulo adı ve konum içermez. Kime gönderileceğini sen seçersin. E-posta: \(LatentConfig.feedbackEmail)")
                }
                Section {
                    LabeledContent("Sürüm", value: LatentConfig.versionText)
                } header: { Text("Hakkında") } footer: {
                    Text("Latent Color 400 özgün bir görünümdür; herhangi bir film markasını taklit etmez.")
                }
            }
            .navigationTitle("Ayarlar").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .sheet(item: $share) { ActivitySheet(url: $0.url) }
            .alert("Özet hazırlanamadı", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Tamam") { error = nil }
            } message: { Text(error ?? "") }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { cameraDenied = Self.isCameraDenied }
            }
        }
    }

    private static var isCameraDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    private func shareSummary() {
        preparingSummary = true
        Task {
            do {
                let url = try await library.feedbackSummaryURL()
                share = ShareItem(url: url)
            }
            catch { self.error = error.localizedDescription }
            preparingSummary = false
        }
    }
}

/// Yardım ve Gizlilik sayfalarındaki başlık + metin çifti.
private struct InfoEntry: Identifiable {
    let title: String
    let text: String
    var id: String { title }
    init(_ title: String, _ text: String) { self.title = title; self.text = text }
}

private struct InfoList: View {
    let title: String
    let entries: [InfoEntry]
    var body: some View {
        List(entries) { entry in
            Section { Text(entry.text) } header: { Text(entry.title).textCase(nil).accessibilityAddTraits(.isHeader) }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

struct HelpView: View {
    private let entries: [InfoEntry] = [
        InfoEntry("Rulo nedir?", "Bir rulo, bir gezi ya da bir dönem için başlattığın \(FilmRoll.capacity) karelik filmdir. Adını sen verirsin; film görünümü rulo boyunca aynı kalır ve kareler kendiliğinden bir albüm olur."),
        InfoEntry("Neden \(FilmRoll.capacity) kare?", "Gerçek 35 mm film rulosu gibi. Sınırlı kare, her çekimi biraz daha düşünerek yapmayı ve gezinin sonunda derli toplu bir seri elde etmeyi sağlar."),
        InfoEntry("Neden zoom yok?", "Latent tek bir sabit kadrajla çeker (ana kamera, 1×). Yaklaşmak için birkaç adım atarsın; bütün rulo aynı bakış açısını taşır."),
        InfoEntry("Sildiğim kare neden geri gelmiyor?", "Filmde olduğu gibi, çekilen her kare rulodan bir hak kullanır. Bir kareyi silmek fotoğrafı kaldırır ama kare hakkını geri vermez; numaralar da değişmez."),
        InfoEntry("Fotoğraflarım nerede saklanıyor?", "Yalnızca bu cihazda, Latent'in kendi klasöründe. Hesap ya da sunucu yok. iCloud cihaz yedeğin açıksa bu klasör de yedeğe dahil olur. Fotoğraflar'a otomatik kaydedilmez."),
        InfoEntry("Orijinal fotoğrafı nasıl paylaşırım?", "Albümde bir kareyi aç, sağ üstteki paylaş menüsünden \"Orijinali paylaş\"ı seç. Kırpılmamış, işlenmemiş hâli gönderilir. \"Film çerçevesiyle paylaş\" ise çerçeveli bir kopya hazırlar."),
        InfoEntry("Kamera iznini nasıl açarım?", "iPhone Ayarlar → Latent → Kamera anahtarını aç. İzin kapalıysa Latent'in Ayarlar menüsünde \"Kamera iznini aç\" satırı seni oraya götürür."),
    ]
    var body: some View { InfoList(title: "Yardım", entries: entries) }
}

struct PrivacyView: View {
    private let entries: [InfoEntry] = [
        InfoEntry("Hesap ve sunucu yok", "Latent'i kullanmak için hesap açman gerekmez. Uygulamanın bir sunucusu yoktur."),
        InfoEntry("Veri toplanmaz", "Analytics, reklam ya da takip yok. Uygulama içi sayaçlar (ör. albüm açma) yalnızca cihazında tutulur."),
        InfoEntry("Fotoğraflar cihazında", "Fotoğrafların ve ruloların yalnızca bu cihazda saklanır. iPhone Fotoğraflar arşivine otomatik kaydedilmez; dışarıya yalnızca senin seçtiğin paylaşımlarla çıkar."),
        InfoEntry("Kamera izni", "Kamera izni yalnızca fotoğraf çekmek için kullanılır."),
        InfoEntry("Rulo özeti", "Ayarlar'daki rulo özeti yalnızca sen paylaşırsan cihazdan çıkar. İçinde fotoğraf, rulo adı ya da konum yoktur; yalnızca kullanım sayıları bulunur."),
    ]
    var body: some View { InfoList(title: "Gizlilik", entries: entries) }
}
