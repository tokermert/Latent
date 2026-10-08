import SwiftUI

struct ArchiveView: View {
    @EnvironmentObject private var library: LibraryModel
    @State private var newRoll = false
    @State private var cameraRoll: FilmRoll?
    @State private var pendingCameraRoll: FilmRoll?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack { BrandMark(); Spacer(); MicroLabel(text: "PHOTO SYSTEM / 01").accessibilityHidden(true) }
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
                            Button("İlk rulonu başlat") { newRoll = true }.buttonStyle(.borderedProminent)
                        }
                    } else {
                        ForEach(library.rolls) { roll in
                            NavigationLink { AlbumView(rollID: roll.id) } label: {
                                rollCover(roll)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(coverAccessibilityLabel(roll))
                                    .accessibilityHint("Albümü açar")
                            }.buttonStyle(.plain)
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
                        if let active = library.rolls.first(where: { !$0.isFinished }) { cameraRoll = active }
                        else { newRoll = true }
                    } label: { Image(systemName: "camera") }.buttonStyle(TactileShutterStyle(diameter: 58))
                        .disabled(!library.isLoaded).accessibilityLabel("Kamerayı aç")
                    Spacer()
                    Button { newRoll = true } label: { Label("Yeni rulo", systemImage: "plus").font(.caption).frame(minHeight: 44).contentShape(Rectangle()) }
                        .disabled(!library.isLoaded)
                }.padding(.horizontal, 26).padding(.vertical, 14).background(.white)
                    .overlay(alignment: .top) { Rectangle().fill(LatentTheme.rule).frame(height: 1) }
            }
            .sheet(isPresented: $newRoll, onDismiss: {
                if let pending = pendingCameraRoll { cameraRoll = pending; pendingCameraRoll = nil }
            }) { NewRollView { roll in pendingCameraRoll = roll } }
            .fullScreenCover(item: $cameraRoll) { roll in CameraView(rollID: roll.id) }
        }
    }

    private func rollCover(_ roll: FilmRoll) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let cover = roll.coverFrame {
                FilmBorder(number: cover.number, film: roll.film) { StoredPhoto(url: library.url(cover), aspectRatio: cover.orientation.aspectRatio) }
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
    let onCreated: (FilmRoll) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section("Bu rulonun hikâyesi") { TextField("Örneğin London", text: $title).textInputAutocapitalization(.words) }
                Section {
                    LabeledContent("Film", value: "Latent Color 400")
                    LabeledContent("Kapasite", value: "\(FilmRoll.capacity) kare")
                    LabeledContent("Format", value: "35 mm film · 3:2 / 2:3")
                } footer: { Text("Görünüm rulo boyunca sabit. Fotoğraflar bu cihazda saklanır.") }
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
                let roll = try await library.createRoll(title: title)
                onCreated(roll)
                dismiss()
            } catch { self.error = error.localizedDescription; saving = false }
        }
    }
}
