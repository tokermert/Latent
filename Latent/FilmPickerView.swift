import SwiftUI
import UIKit

extension FilmStock {
    /// VoiceOver için: "LATENT GOLD 200" → "Latent Gold 200". POSIX yerel ayarı, Türkçe
    /// büyük/küçük harf dönüşümünün "SLIDE" → "Slıde" yapmasını önler.
    var spokenName: String { name.capitalized(with: Locale(identifier: "en_US_POSIX")) }
    var spokenShortName: String { shortName.capitalized(with: Locale(identifier: "en_US_POSIX")) }
}

/// Yeni rulo sayfasındaki film seçimi: yatay kaydırılan film kartları.
/// Her kartta ad, ISO, tek cümle karakter ve filmin örneklerinden küçük bir kontakt şerit var.
struct FilmPicker: View {
    @Binding var selection: FilmStock
    @State private var preview: SamplePreview?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(FilmStock.all, id: \.id) { stock in
                    FilmCard(stock: stock, selected: stock.id == selection.id,
                             onSelect: { selection = stock },
                             onSample: { preview = SamplePreview(stock: stock, index: $0) })
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 4)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .sheet(item: $preview) { FilmSampleViewer(stock: $0.stock, startIndex: $0.index) }
    }
}

private struct SamplePreview: Identifiable {
    let id = UUID()
    let stock: FilmStock
    let index: Int
}

private struct FilmCard: View {
    let stock: FilmStock
    let selected: Bool
    let onSelect: () -> Void
    let onSample: (Int) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Kartın üst kısmı seçim düğmesi; örnek kareler ayrı düğmeler (iç içe düğme yok).
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(stock.shortName).font(.headline).tracking(-0.3)
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? LatentTheme.orange : LatentTheme.rule)
                    }
                    MicroLabel(text: stock.isMonochrome ? "ISO \(stock.iso) · S/B" : "ISO \(stock.iso)")
                    Text(stock.summary).font(.footnote).foregroundStyle(LatentTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(stock.spokenName), ISO \(stock.iso)\(stock.isMonochrome ? ", siyah beyaz" : ""), \(stock.summary)")
            .accessibilityAddTraits(selected ? .isSelected : [])

            HStack(alignment: .top, spacing: 6) {
                ForEach(0..<FilmSamples.count, id: \.self) { index in
                    Button { onSample(index) } label: {
                        FilmBorder(number: index + 1, compact: true, film: stock.name) {
                            FilmSampleImage(stock: stock, index: index, maxPixel: 360, fixedAspectRatio: 2.0 / 3.0)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Örnek \(index + 1), \(stock.spokenShortName)")
                    .accessibilityHint("Büyük görünümde açar")
                    .accessibilityAddTraits(.isImage)
                }
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .topLeading)
        .background(LatentTheme.paper, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? LatentTheme.orange : LatentTheme.rule, lineWidth: selected ? 2 : 1)
        }
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

/// `FilmSamples` örneğini yükler; gelene kadar gri yer tutucu ve ProgressView gösterir.
/// `fixedAspectRatio` verilirse görsel o orana kırpılır (kontakt şerit); verilmezse kendi oranıyla gösterilir.
/// `base` true ise filmin uygulanmadığı taban görüntü (`FilmSamples.baseImage`) yüklenir.
struct FilmSampleImage: View {
    let stock: FilmStock
    let index: Int
    let maxPixel: CGFloat
    var fixedAspectRatio: Double? = nil
    var base = false
    @State private var image: UIImage?
    @State private var failed = false
    private var aspectRatio: Double {
        if let fixedAspectRatio { return fixedAspectRatio }
        guard let image, image.size.height > 0 else { return 3.0 / 2.0 }
        return image.size.width / image.size.height
    }
    var body: some View {
        ZStack {
            Color(white: 0.94)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                Image(systemName: "photo").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipped()
        .task(id: stock.id) {
            image = nil; failed = false
            let loaded = base
                ? await FilmSamples.baseImage(index: index, maxPixel: maxPixel)
                : await FilmSamples.image(stock: stock, index: index, maxPixel: maxPixel)
            guard !Task.isCancelled else { return }
            image = loaded; failed = loaded == nil
        }
    }
}

/// Örneklerin büyük görünümü: sayfa sayfa kaydırılır, kenarda film adı ve örnek numarası.
/// Basılı tutunca filmsiz taban görüntü gösterilir; bırakınca film. VoiceOver'da "Filmsiz göster" eylemi.
struct FilmSampleViewer: View {
    let stock: FilmStock
    @State private var index: Int
    /// Parmak ekrandayken ve kaydırma başlamadan (10 pt) true.
    @GestureState private var pressing = false
    /// VoiceOver eylemiyle açılan filmsiz görünüm; sayfa değişince kapanır.
    @State private var baseToggled = false
    @Environment(\.dismiss) private var dismiss
    private var showingBase: Bool { pressing || baseToggled }
    init(stock: FilmStock, startIndex: Int) {
        self.stock = stock
        _index = State(initialValue: startIndex)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                TabView(selection: $index) {
                    ForEach(0..<FilmSamples.count, id: \.self) { i in
                        let base = showingBase && i == index
                        FilmBorder(number: i + 1, film: stock.name) {
                            // İki görüntü üst üste; taban önceden yüklenir, geçiş anında olur.
                            ZStack {
                                FilmSampleImage(stock: stock, index: i, maxPixel: 1600)
                                FilmSampleImage(stock: stock, index: i, maxPixel: 1600, base: true)
                                    .opacity(base ? 1 : 0)
                            }
                            .overlay(alignment: .topLeading) {
                                if base {
                                    Text("FİLMSİZ").font(.system(.caption2, design: .monospaced).weight(.semibold))
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                                        .foregroundStyle(.white).padding(8)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0).updating($pressing) { value, state, _ in
                                state = abs(value.translation.width) < 10 && abs(value.translation.height) < 10
                            }
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Örnek \(i + 1), \(base ? "filmsiz" : stock.spokenShortName)")
                        .accessibilityAddTraits(.isImage)
                        .accessibilityAction(named: base ? "Filmle göster" : "Filmsiz göster") { baseToggled.toggle() }
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .onChange(of: index) { baseToggled = false }
                Text("Filmsiz hâlini görmek için basılı tut.").font(.footnote).foregroundStyle(LatentTheme.muted)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    MicroLabel(text: stock.isMonochrome ? "\(stock.name) · ISO \(stock.iso) · S/B" : "\(stock.name) · ISO \(stock.iso)")
                    Text(stock.summary).font(.subheadline).foregroundStyle(LatentTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.bottom, 12)
            }
            .background(LatentTheme.paper)
            .navigationTitle(stock.shortName).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }
    }
}
