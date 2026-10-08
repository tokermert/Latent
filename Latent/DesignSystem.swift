import SwiftUI
import UIKit

enum LatentTheme {
    static let orange = Color(red: 0.94, green: 0.35, blue: 0.12)
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.08)
    static let muted = Color(red: 0.39, green: 0.42, blue: 0.39)
    static let paper = Color.white
    static let gold = Color(red: 0.85, green: 0.74, blue: 0.49)
    static let rule = Color(white: 0.9)
}

struct MicroLabel: View {
    var text: String
    var body: some View {
        Text(text).font(.system(.caption, design: .monospaced))
            .foregroundStyle(LatentTheme.muted)
    }
}

/// Büyük başlıklar için sabit punto yerine Dynamic Type ile ölçeklenen sistem fontu.
/// Tasarımdaki taban punto korunur; büyük yazı ayarında `relativeTo` stiliyle birlikte büyür.
struct DisplayFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
    }
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight)).fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    func displayFont(size: CGFloat, weight: Font.Weight = .medium, relativeTo style: Font.TextStyle = .largeTitle) -> some View {
        modifier(DisplayFont(size: size, weight: weight, relativeTo: style))
    }
}

extension FilmRoll {
    /// "LATENT COLOR 400" → "COLOR 400": dar etiketlerde marka öneki tekrarlanmaz.
    var filmShortName: String { film.hasPrefix("LATENT ") ? String(film.dropFirst("LATENT ".count)) : film }
    /// "07 / 36" biçiminde sayaç: kullanılan poz (silinenler dahil) / `FilmRoll.capacity`.
    var counterText: String { String(format: "%02d / %02d", exposuresUsed, Self.capacity) }
}

/// VoiceOver metinleri. Görsel etiketler (ör. "07", "400 ▸ 07 ▸ 08.10.26") yerine tek cümle okunur.
enum LatentAccessibility {
    static func date(_ date: Date) -> String { date.formatted(.dateTime.day().month(.abbreviated).year()) }
    /// Örnek: "London, kare 7, 12 Eki 2026"
    static func frame(rollTitle: String, number: Int, capturedAt: Date) -> String {
        "\(rollTitle), kare \(number), \(date(capturedAt))"
    }
}

/// Film üzerine basılan yazılar: kenar baskısı ve kompakt kamera tarih damgası.
/// Ekranda (`FilmBorder`, `dateStamp`) ve çerçeveli paylaşım çıktısında (`PhotoProcessor.framedExport`)
/// aynı biçim kullanılır. Yalnızca gösterim içindir; kaydedilen JPEG'lere işlenmez.
enum FilmImprint {
    /// Tam: "LATENT COLOR 400 ▸ 07 ▸ 08.10.26"; kompakt: "400 ▸ 07 ▸ 08.10.26". Tarih yoksa düşer.
    static func edge(film: String, number: Int, date: Date?, compact: Bool) -> String {
        let name = compact ? (film.split(separator: " ").last.map(String.init) ?? film) : film
        var parts = [name, String(format: "%02d", number)]
        if let date { parts.append(edgeDate.string(from: date)) }
        return parts.joined(separator: " ▸ ")
    }
    /// "'26 10 08": eski kompakt kameraların dijital tarih damgası.
    static func stamp(_ date: Date) -> String { stampDate.string(from: date) }

    /// Damga puntosu, fotoğrafın uzun kenarına oranlı; küçük ve büyük gösterimde aynı görünür.
    static let stampScale: CGFloat = 0.032
    /// LatentTheme.orange'dan biraz daha kırmızı ve parlak: LED damga rengi.
    static let stampUIColor = UIColor(red: 1.0, green: 0.38, blue: 0.14, alpha: 0.92)
    static var stampColor: Color { Color(uiColor: stampUIColor) }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }
    private static let edgeDate = formatter("dd.MM.yy")
    private static let stampDate = formatter("''yy MM dd")
}

/// Fotoğrafın sağ alt köşesine turuncu tarih damgası bindirir. VoiceOver'dan gizlidir;
/// tarih zaten kare etiketinde okunur.
struct DateStamp: ViewModifier {
    let date: Date
    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { proxy in
                let size = max(proxy.size.width, proxy.size.height) * FilmImprint.stampScale
                Text(FilmImprint.stamp(date))
                    .font(.system(size: size, weight: .semibold, design: .monospaced))
                    .foregroundStyle(FilmImprint.stampColor)
                    .blur(radius: size * 0.02)
                    .shadow(color: FilmImprint.stampColor.opacity(0.7), radius: size * 0.3)
                    .lineLimit(1).fixedSize()
                    .padding(.trailing, size * 1.1).padding(.bottom, size * 0.8)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomTrailing)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    func dateStamp(_ date: Date) -> some View { modifier(DateStamp(date: date)) }
}

struct BrandMark: View {
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            Text("latent").tracking(-1.7).displayFont(size: 33, relativeTo: .title)
            Circle().fill(LatentTheme.orange).frame(width: 6, height: 6).accessibilityHidden(true)
        }.foregroundStyle(LatentTheme.ink).accessibilityElement(children: .combine)
    }
}

struct FilmBorder<Content: View>: View {
    var number: Int
    var compact = false
    /// Kenar baskısı; varsayılan ilk film görünümü. Rulo bilinen yerlerde `roll.film` geçilir.
    var film = "LATENT COLOR 400"
    /// Kenara basılacak çekim tarihi; nil ise yazılmaz.
    var date: Date? = nil
    @ViewBuilder var content: () -> Content
    private var side: CGFloat { compact ? 8 : 16 }
    var body: some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: compact ? 3 : 6))
            .padding(.leading, side).padding(.trailing, side + 5)
            .padding(.top, compact ? 8 : 12).padding(.bottom, compact ? 18 : 27)
            .background(LatentTheme.ink)
            .overlay(alignment: .trailing) {
                VStack(spacing: compact ? 3 : 5) {
                    ForEach(0..<9) { _ in Rectangle().fill(LatentTheme.gold).frame(width: compact ? 3 : 6, height: compact ? 3 : 5) }
                }.padding(.trailing, compact ? 3 : 5).accessibilityHidden(true)
            }
            .overlay(alignment: .bottomLeading) {
                Text(FilmImprint.edge(film: film, number: number, date: date, compact: compact))
                    .font(.system(size: compact ? 7 : 9, design: .monospaced)).tracking(0.5)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(LatentTheme.gold).padding(.leading, side).padding(.trailing, side + 5).padding(.bottom, compact ? 5 : 8)
                    .accessibilityHidden(true)
            }
    }
}

struct TactileShutterStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    var diameter: CGFloat = 82
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 21, weight: .medium)).foregroundStyle(Color(red: 0.24, green: 0.10, blue: 0.04))
            .frame(width: diameter - 14, height: diameter - 14)
            .background {
                Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.56, blue: 0.20), LatentTheme.orange, Color(red: 0.88, green: 0.25, blue: 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom), lineWidth: 2))
                    .shadow(color: Color(red: 0.61, green: 0.18, blue: 0.04), radius: 0, y: configuration.isPressed ? 1 : 4)
                    .shadow(color: .black.opacity(0.28), radius: configuration.isPressed ? 2 : 4, y: configuration.isPressed ? 1 : 7)
            }
            .offset(y: configuration.isPressed ? 2 : -2)
            .frame(width: diameter, height: diameter)
            .background {
                Circle().fill(LinearGradient(colors: [Color(white: 0.76), .white, Color(white: 0.54)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().fill(Color(white: 0.13)).padding(4)
            }
            .contentShape(Circle()).opacity(enabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct StoredPhoto: View {
    let url: URL
    var aspectRatio: Double
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            Color(white: 0.94)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary).accessibilityLabel("Fotoğraf açılamadı") }
            else { ProgressView() }
        }
        .aspectRatio(aspectRatio, contentMode: .fit).clipped()
        .task(id: url) {
            image = nil; failed = false
            let path = url.path
            let loaded = await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: path) }.value
            guard !Task.isCancelled else { return }
            image = loaded; failed = loaded == nil
        }
    }
}
