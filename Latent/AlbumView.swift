import SwiftUI
import UIKit

struct AlbumView: View {
    let rollID: UUID
    @EnvironmentObject private var library: LibraryModel
    @State private var camera = false
    @State private var confirmFinish = false
    @State private var renaming: FilmRoll?
    @State private var deletingFrame: FilmFrame?
    @State private var recordedOpen = false
    @State private var error: String?
    private var roll: FilmRoll? { library.roll(rollID) }
    var body: some View {
        ScrollView {
            if let roll {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        MicroLabel(text: "\(roll.frames.count) KARE · 35 mm FİLM")
                        // Geçici: ada dokunmak yeniden adlandırır (docs/screens.md).
                        Button { renaming = roll } label: {
                            Text(roll.title).tracking(-2).displayFont(size: 44).multilineTextAlignment(.leading)
                        }.buttonStyle(.plain)
                        MicroLabel(text: roll.film)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(roll.title), \(roll.frames.count) kare, \(roll.film), 35 mm film")
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityAction(named: "Yeniden adlandır") { renaming = roll }
                    if roll.frames.isEmpty {
                        ContentUnavailableView("Rulon hazır", systemImage: "camera", description: Text("İlk kareni çekerek başla."))
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], alignment: .leading, spacing: 24) {
                            ForEach(roll.frames) { frame in
                                NavigationLink { PhotoDetailView(rollID: rollID, frameID: frame.id) } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        FilmBorder(number: frame.number, compact: true, film: roll.film, date: frame.capturedAt) {
                                            StoredPhoto(url: library.url(frame), aspectRatio: frame.orientation.aspectRatio)
                                        }
                                        MicroLabel(text: String(format: "%02d", frame.number))
                                    }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(LatentAccessibility.frame(rollTitle: roll.title, number: frame.number, capturedAt: frame.capturedAt))
                                    .accessibilityAddTraits(.isImage)
                                }
                                .buttonStyle(.plain)
                                .contextMenu { FrameMenuItems(roll: roll, frame: frame, onCover: { setCover(frame) }, onDelete: { deletingFrame = frame }) }
                            }
                        }
                    }
                    HStack { MicroLabel(text: roll.isFinished ? "RULO TAMAMLANDI" : "\(roll.remaining) BOŞ KARE"); Spacer() }
                }.padding(24)
            }
        }
        .background(.white).foregroundStyle(LatentTheme.ink)
        .navigationTitle("Albüm").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let roll, !roll.isFinished {
                ToolbarItem(placement: .topBarTrailing) { Button("Ruloyu bitir") { confirmFinish = true } }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let roll, !roll.isFinished {
                Button { camera = true } label: { Image(systemName: "camera") }
                    .buttonStyle(TactileShutterStyle(diameter: 60)).accessibilityLabel("Bu ruloya fotoğraf çek")
                    .padding(18).frame(maxWidth: .infinity).background(.white)
            }
        }
        .task {
            // Ölçüm: albüm görünümü başına bir kez; detaydan geri dönüş tekrar saymaz.
            guard !recordedOpen else { return }
            recordedOpen = true
            try? await library.recordAlbumOpened(rollID)
        }
        .fullScreenCover(isPresented: $camera) { CameraView(rollID: rollID) }
        .confirmationDialog("Ruloyu bitir?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Ruloyu bitir", role: .destructive) {
                Task { do { try await library.finish(rollID) } catch { self.error = error.localizedDescription } }
            }
        } message: { Text("Çektiğin \(roll?.frames.count ?? 0) fotoğraf korunacak. Kalan \(roll?.remaining ?? 0) kare kullanılamayacak.") }
        .confirmationDialog("Kare silinsin mi?", isPresented: Binding(get: { deletingFrame != nil }, set: { if !$0 { deletingFrame = nil } }), titleVisibility: .visible, presenting: deletingFrame) { frame in
            Button("Kareyi sil", role: .destructive) { delete(frame) }
        } message: { _ in Text(FrameMenuItems.deleteMessage(roll)) }
        .renameRollAlert($renaming) { self.error = $0 }
        .alert("İşlem tamamlanamadı", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Tamam") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func setCover(_ frame: FilmFrame) {
        Task { do { try await library.setCover(frame.id, for: rollID) } catch { self.error = error.localizedDescription } }
    }
    private func delete(_ frame: FilmFrame) {
        Task { do { try await library.deleteFrame(frame.id, from: rollID) } catch { self.error = error.localizedDescription } }
    }
}

/// Albüm karesinin bağlam menüsü ve tek kare menüsü için ortak eylemler: kapak yap, sil.
struct FrameMenuItems: View {
    let roll: FilmRoll
    let frame: FilmFrame
    let onCover: () -> Void
    let onDelete: () -> Void
    var body: some View {
        if roll.coverFrame?.id == frame.id {
            Button { } label: { Label("Rulonun kapağı", systemImage: "checkmark") }.disabled(true)
        } else {
            Button(action: onCover) { Label("Kapak yap", systemImage: "rectangle.portrait.on.rectangle.portrait") }
        }
        Button(role: .destructive, action: onDelete) { Label("Sil", systemImage: "trash") }
    }

    /// Silme onayı: kare hakkının geri gelmediğini açıkça söyler.
    static func deleteMessage(_ roll: FilmRoll?) -> String {
        guard let roll, !roll.isFinished else {
            return "Bu kare silinecek. Rulo tamamlandığı için yerine yeni kare çekilemez."
        }
        return "Bu kare silinecek. Kare hakkı geri gelmez: kalan \(roll.remaining) kare."
    }
}

struct PhotoDetailView: View {
    let rollID: UUID
    let frameID: UUID
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(FilmImprint.showStampKey) private var showDateStamp = true
    @State private var share: ShareItem?
    @State private var exporting = false
    @State private var confirmDelete = false
    @State private var error: String?
    private var roll: FilmRoll? { library.roll(rollID) }
    private var frame: FilmFrame? { roll?.frames.first { $0.id == frameID } }
    private var number: Int { frame?.number ?? 0 }
    var body: some View {
        ScrollView {
            if let frame, let roll {
                VStack(alignment: .leading, spacing: 24) {
                    FilmBorder(number: number, film: roll.film, date: frame.capturedAt) {
                        StoredPhoto(url: library.url(frame, variant: .developed), aspectRatio: frame.orientation.aspectRatio).dateStamp(frame.capturedAt)
                    }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(LatentAccessibility.frame(rollTitle: roll.title, number: number, capturedAt: frame.capturedAt))
                        .accessibilityAddTraits(.isImage)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) { Text(roll.title).font(.headline); Text(frame.capturedAt, format: .dateTime.day().month().year()).font(.caption) }
                        Spacer(); MicroLabel(text: "\(roll.filmShortName)\n" + String(format: "%02d / %02d", number, FilmRoll.capacity))
                            .accessibilityLabel("\(roll.film), kare \(number) / \(FilmRoll.capacity)")
                    }
                }.padding(30).background(.white).padding(.vertical, 20)
            }
        }
        .background(.white).navigationTitle(String(format: "Kare %02d", number)).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if exporting { ProgressView() }
                else {
                    Menu {
                        Button("Film çerçevesiyle paylaş") { export() }
                        Button("Orijinali paylaş") { if let frame { present(library.url(frame, variant: .original)) } }
                    } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Fotoğrafı paylaş")
                }
            }
            if let roll, let frame {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        FrameMenuItems(roll: roll, frame: frame, onCover: setCover, onDelete: { confirmDelete = true })
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Kare seçenekleri")
                }
            }
        }
        .sheet(item: $share) { ActivitySheet(url: $0.url) }
        .confirmationDialog("Kare silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Kareyi sil", role: .destructive) { delete() }
        } message: { Text(FrameMenuItems.deleteMessage(roll)) }
        .alert("İşlem tamamlanamadı", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Tamam") { error = nil } } message: { Text(error ?? "") }
    }
    /// Paylaşım sayfasını açar ve paylaşımı sayar (çerçeveli ve orijinal için aynı sayaç).
    private func present(_ url: URL) {
        share = ShareItem(url: url)
        Task { try? await library.recordShare(rollID) }
    }
    private func export() {
        guard let frame, let roll else { return }
        exporting = true
        let url = library.url(frame, variant: .developed); let title = roll.title; let index = number
        let film = roll.film; let capturedAt = frame.capturedAt; let showStamp = showDateStamp
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try PhotoProcessor.framedExport(imageURL: url, title: title, number: index, film: film, capturedAt: capturedAt, showStamp: showStamp)
                }.value
                present(result)
            } catch { self.error = error.localizedDescription }
            exporting = false
        }
    }
    private func setCover() {
        Task { do { try await library.setCover(frameID, for: rollID) } catch { self.error = error.localizedDescription } }
    }
    private func delete() {
        Task {
            do { try await library.deleteFrame(frameID, from: rollID); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct ShareItem: Identifiable { let id = UUID(); let url: URL }
struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
