import SwiftUI

struct ArchiveView: View {
    @EnvironmentObject private var library: LibraryModel
    @State private var newRoll = false
    /// Yeni rulo sayfası, bitmemiş ruloyu bitirme onayıyla mı açıldı?
    @State private var newRollFinishesActive = false
    @State private var confirmReplacing: FilmRoll?
    @State private var cameraRoll: FilmRoll?
    @State private var pendingCameraRoll: FilmRoll?
    @State private var settings = false
    @State private var renaming: FilmRoll?
    @State private var deleting: FilmRoll?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack {
                        BrandMark(); Spacer(); MicroLabel(text: "PHOTO SYSTEM / 01").accessibilityHidden(true)
                        Button { settings = true } label: { Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44) }
                            .foregroundStyle(LatentTheme.ink).accessibilityLabel("Ayarlar")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        MicroLabel(text: "KİŞİSEL FOTOĞRAF ARŞİVİN")
                        Text("Arşivin.").tracking(-2).displayFont(size: 44).accessibilityAddTraits(.isHeader)
                    }
                    if !library.isLoaded {
                        if let error = library.errorMessage {
                            ContentUnavailableView("Arşiv açılamadı", systemImage: "externaldrive.badge.exclamationmark", description: Text(error))
                            Button("Tekrar dene") { Task { await library.load() } }
                        } else { ProgressView("Arşiv açılıyor…").frame(maxWidth: .infinity) }
                    } else if library.rolls.isEmpty {
                        VStack(alignment: .leading, spacing: 22) {
                            RoundedRectangle(cornerRadius: 3).stroke(LatentTheme.rule, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                                .frame(height: 240)
                                .overlay { VStack(spacing: 14) { Image(systemName: "film").font(.largeTitle).accessibilityHidden(true); Text("İlk hikâyen burada başlayacak.").font(.subheadline) }.foregroundStyle(LatentTheme.muted) }
                            Text("Bir gezi. Bir film. Senin bakışın.").font(.subheadline).foregroundStyle(LatentTheme.muted)
                            Button("İlk rulonu başlat") { startNewRoll() }.buttonStyle(.borderedProminent)
                        }
                    } else {
                        ForEach(library.rolls) { roll in
                            NavigationLink { AlbumView(rollID: roll.id) } label: {
                                rollCover(roll)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(coverAccessibilityLabel(roll))
                                    .accessibilityHint("Albümü açar")
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { renaming = roll } label: { Label("Yeniden adlandır", systemImage: "pencil") }
                                Button(role: .destructive) { deleting = roll } label: { Label("Sil", systemImage: "trash") }
                            }
                        }
                    }
                }.padding(26)
            }
            .background(LatentTheme.paper).foregroundStyle(LatentTheme.ink)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) { Text("Arşiv").font(.subheadline); MicroLabel(text: "\(library.rolls.count) RULO") }
                        .accessibilityElement(children: .ignore).accessibilityLabel("Arşiv, \(library.rolls.count) rulo")
                    Spacer()
                    Button {
                        if let active = library.activeRoll { cameraRoll = active } else { startNewRoll() }
                    } label: { Image(systemName: "camera") }.buttonStyle(TactileShutterStyle(diameter: 58))
                        .disabled(!library.isLoaded).accessibilityLabel("Kamerayı aç")
                    Spacer()
                    Button { startNewRoll() } label: { Label("Yeni rulo", systemImage: "plus").font(.caption).frame(minHeight: 44).contentShape(Rectangle()) }
                        .disabled(!library.isLoaded)
                }.padding(.horizontal, 26).padding(.vertical, 14).background(.white)
                    .overlay(alignment: .top) { Rectangle().fill(LatentTheme.rule).frame(height: 1) }
            }
            .sheet(isPresented: $newRoll, onDismiss: {
                if let pending = pendingCameraRoll { cameraRoll = pending; pendingCameraRoll = nil }
            }) { NewRollView(finishingActive: newRollFinishesActive) { roll in pendingCameraRoll = roll } }
            .fullScreenCover(item: $cameraRoll) { roll in CameraView(rollID: roll.id) }
            .sheet(isPresented: $settings) { SettingsView() }
            // Tek aktif rulo: yeni rulo, bitmemiş ruloyu bitirerek başlar.
            .confirmationDialog(replaceTitle, isPresented: Binding(get: { confirmReplacing != nil }, set: { if !$0 { confirmReplacing = nil } }), titleVisibility: .visible, presenting: confirmReplacing) { active in
                Button("\(active.title) rulosunu bitir ve yeni rulo başlat", role: .destructive) {
                    newRollFinishesActive = true; newRoll = true
                }
                Button("Vazgeç", role: .cancel) { }
            } message: { active in
                Text("Yeni rulo başlatırsan \(active.title) tamamlanır, kalan \(active.remaining) kare kullanılamaz. Çektiğin fotoğraflar korunur.")
            }
            .confirmationDialog("Rulo silinsin mi?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { roll in
                Button("\(roll.title) rulosunu sil", role: .destructive) { delete(roll) }
            } message: { roll in
                Text(roll.frames.isEmpty ? "Bu rulo silinecek." : "\(roll.frames.count) fotoğraf kalıcı olarak silinecek. Bu işlem geri alınamaz.")
            }
            .renameRollAlert($renaming) { self.error = $0 }
            .alert("İşlem tamamlanamadı", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Tamam") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private var replaceTitle: String {
        guard let active = confirmReplacing else { return "" }
        return "\(active.title) rulosu bitmedi (\(active.exposuresUsed)/\(FilmRoll.capacity))."
    }

    /// Aktif rulo varsa önce bitirme onayı ister; yoksa yeni rulo sayfasını açar.
    private func startNewRoll() {
        if let active = library.activeRoll { confirmReplacing = active }
        else { newRollFinishesActive = false; newRoll = true }
    }

    private func delete(_ roll: FilmRoll) {
        Task { do { try await library.deleteRoll(roll.id) } catch { self.error = error.localizedDescription } }
    }

    private func rollCover(_ roll: FilmRoll) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let cover = roll.coverFrame {
                FilmBorder(number: cover.number, film: roll.film, date: cover.capturedAt) { StoredPhoto(url: library.url(cover), aspectRatio: cover.orientation.aspectRatio) }
            } else {
                FilmBorder(number: 0, film: roll.film) {
                    Rectangle().fill(Color(white: 0.95)).aspectRatio(3.0 / 2.0, contentMode: .fit)
                        .overlay { Label("İlk kareyi çek", systemImage: "camera").font(.subheadline).foregroundStyle(LatentTheme.muted) }
                }
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(roll.title).tracking(-1).displayFont(size: 31, relativeTo: .title)
                    Text(roll.createdAt, format: .dateTime.day().month(.abbreviated).year()).font(.system(.caption, design: .monospaced)).foregroundStyle(LatentTheme.muted)
                }
                Spacer(); Image(systemName: "arrow.up.right").frame(width: 44, height: 44).overlay(Circle().stroke(LatentTheme.rule)).accessibilityHidden(true)
            }
            HStack {
                Circle().fill(roll.isFinished ? LatentTheme.muted : LatentTheme.orange).frame(width: 6, height: 6)
                MicroLabel(text: roll.isFinished ? "TAMAMLANDI · \(roll.filmShortName)" : "\(roll.filmShortName) · 35 mm FİLM")
                Spacer(); MicroLabel(text: roll.counterText)
            }.padding(.top, 12).overlay(alignment: .top) { Rectangle().fill(LatentTheme.rule).frame(height: 1) }
        }.padding(.bottom, 18)
    }

    /// Örnek: "London, 12 Eki 2026, 7 kare, devam ediyor, 29 kare kaldı"
    private func coverAccessibilityLabel(_ roll: FilmRoll) -> String {
        let base = "\(roll.title), \(LatentAccessibility.date(roll.createdAt)), \(roll.frames.count) kare"
        return roll.isFinished ? base + ", tamamlandı" : base + ", devam ediyor, \(roll.remaining) kare kaldı"
    }
}

struct NewRollView: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var saving = false
    @State private var error: String?
    /// true ise kaydedince mevcut aktif rulo tamamlanır (kullanıcı arşivde onayladı).
    var finishingActive = false
    let onCreated: (FilmRoll) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section("Bu rulonun hikâyesi") {
                    TextField("Örneğin London", text: $title).textInputAutocapitalization(.words)
                        .onChange(of: title) { _, new in if new.count > RollTitle.limit { title = String(new.prefix(RollTitle.limit)) } }
                }
                Section {
                    LabeledContent("Film", value: "Latent Color 400")
                    LabeledContent("Kapasite", value: "\(FilmRoll.capacity) kare")
                    LabeledContent("Format", value: "35 mm film · 3:2 / 2:3")
                } footer: {
                    if finishingActive, let active = library.activeRoll {
                        Text("Görünüm rulo boyunca sabit. Fotoğraflar bu cihazda saklanır. Filmi taktığında \(active.title) tamamlanır.")
                    } else { Text("Görünüm rulo boyunca sabit. Fotoğraflar bu cihazda saklanır.") }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button { create() } label: { HStack { Text("Filmi tak"); Spacer(); if saving { ProgressView() } else { Image(systemName: "arrow.right") } } }
                    .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("Yeni rulo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() }.disabled(saving) } }
            .interactiveDismissDisabled(saving)
        }
    }
    private func create() {
        saving = true
        Task {
            do {
                let roll = try await library.createRoll(title: title, finishingActive: finishingActive)
                onCreated(roll)
                dismiss()
            } catch { self.error = error.localizedDescription; saving = false }
        }
    }
}

/// Rulo adı sınırı; depolama katmanı da aynı sınırla keser (PRD §9).
enum RollTitle {
    static let limit = 60
}

/// Arşiv ve albümde ortak "Yeniden adlandır" alert'i (iOS yerleşik TextField'lı alert).
private struct RenameRollAlert: ViewModifier {
    @Binding var roll: FilmRoll?
    let onError: (String) -> Void
    @EnvironmentObject private var library: LibraryModel
    @State private var text = ""
    func body(content: Content) -> some View {
        content
            .alert("Ruloyu yeniden adlandır", isPresented: Binding(get: { roll != nil }, set: { if !$0 { roll = nil } })) {
                TextField("Rulo adı", text: $text).textInputAutocapitalization(.words)
                Button("Vazgeç", role: .cancel) { }
                Button("Kaydet") { save() }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: { Text("En fazla \(RollTitle.limit) karakter.") }
            .onChange(of: roll?.id, initial: true) { text = roll?.title ?? "" }
            .onChange(of: text) { _, new in if new.count > RollTitle.limit { text = String(new.prefix(RollTitle.limit)) } }
    }
    private func save() {
        guard let id = roll?.id else { return }
        let title = text
        Task { do { try await library.renameRoll(id, title: title) } catch { onError(error.localizedDescription) } }
    }
}

extension View {
    func renameRollAlert(_ roll: Binding<FilmRoll?>, onError: @escaping (String) -> Void) -> some View {
        modifier(RenameRollAlert(roll: roll, onError: onError))
    }
}
