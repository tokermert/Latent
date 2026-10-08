import SwiftUI
import UIKit

struct AlbumView: View {
    let rollID: UUID
    @EnvironmentObject private var library: LibraryModel
    @State private var camera = false
    @State private var confirmFinish = false
    @State private var error: String?
    private var roll: FilmRoll? { library.roll(rollID) }
    var body: some View {
        ScrollView {
            if let roll {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        MicroLabel(text: "\(roll.frames.count) KARE · 35 mm FİLM")
                        Text(roll.title).tracking(-2).displayFont(size: 44)
                        MicroLabel(text: roll.film)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(roll.title), \(roll.frames.count) kare, \(roll.film), 35 mm film")
                    .accessibilityAddTraits(.isHeader)
                    if roll.frames.isEmpty {
                        ContentUnavailableView("Rulon hazır", systemImage: "camera", description: Text("İlk kareni çekerek başla."))
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], alignment: .leading, spacing: 24) {
                            ForEach(Array(roll.frames.enumerated()), id: \.element.id) { index, frame in
                                NavigationLink { PhotoDetailView(rollID: rollID, frameID: frame.id) } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        FilmBorder(number: index + 1, compact: true, film: roll.film) {
                                            StoredPhoto(url: library.url(frame), aspectRatio: frame.orientation.aspectRatio)
                                        }
                                        MicroLabel(text: String(format: "%02d", index + 1))
                                    }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(LatentAccessibility.frame(rollTitle: roll.title, number: index + 1, capturedAt: frame.capturedAt))
                                    .accessibilityAddTraits(.isImage)
                                }.buttonStyle(.plain)
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
        .fullScreenCover(isPresented: $camera) { CameraView(rollID: rollID) }
        .confirmationDialog("Ruloyu bitir?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Ruloyu bitir", role: .destructive) {
                Task { do { try await library.finish(rollID) } catch { self.error = error.localizedDescription } }
            }
        } message: { Text("Çektiğin \(roll?.frames.count ?? 0) fotoğraf korunacak. Kalan \(roll?.remaining ?? 0) kare kullanılamayacak.") }
        .alert("İşlem tamamlanamadı", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Tamam") { error = nil }
        } message: { Text(error ?? "") }
    }
}

struct PhotoDetailView: View {
    let rollID: UUID
    let frameID: UUID
    @EnvironmentObject private var library: LibraryModel
    @State private var share: ShareItem?
    @State private var exporting = false
    @State private var error: String?
    private var roll: FilmRoll? { library.roll(rollID) }
    private var frame: FilmFrame? { roll?.frames.first { $0.id == frameID } }
    private var number: Int { (roll?.frames.firstIndex { $0.id == frameID } ?? 0) + 1 }
    var body: some View {
        ScrollView {
            if let frame, let roll {
                VStack(alignment: .leading, spacing: 24) {
                    FilmBorder(number: number, film: roll.film) { StoredPhoto(url: library.url(frame, variant: .developed), aspectRatio: frame.orientation.aspectRatio) }
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
                        Button("Orijinali paylaş") { if let frame { share = ShareItem(url: library.url(frame, variant: .original)) } }
                    } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Fotoğrafı paylaş")
                }
            }
        }
        .sheet(item: $share) { ActivitySheet(url: $0.url) }
        .alert("Paylaşım hazırlanamadı", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Tamam") { error = nil } } message: { Text(error ?? "") }
    }
    private func export() {
        guard let frame, let roll else { return }
        exporting = true
        let url = library.url(frame, variant: .developed); let title = roll.title; let index = number
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { try PhotoProcessor.framedExport(imageURL: url, title: title, number: index) }.value
                share = ShareItem(url: result)
            } catch { self.error = error.localizedDescription }
            exporting = false
        }
    }
}

private struct ShareItem: Identifiable { let id = UUID(); let url: URL }
private struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
