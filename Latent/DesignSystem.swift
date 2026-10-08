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

struct BrandMark: View {
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            Text("latent").font(.system(size: 33, weight: .medium)).tracking(-1.7)
            Circle().fill(LatentTheme.orange).frame(width: 6, height: 6)
        }.foregroundStyle(LatentTheme.ink).accessibilityElement(children: .combine)
    }
}

struct FilmBorder<Content: View>: View {
    var number: Int
    var compact = false
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
                Text(compact ? String(format: "400 · %02d ▷", number) : String(format: "LATENT COLOR 400 · %02d ▷", number))
                    .font(.system(size: compact ? 7 : 9, design: .monospaced)).tracking(0.5)
                    .foregroundStyle(LatentTheme.gold).padding(.leading, side).padding(.bottom, compact ? 5 : 8)
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
