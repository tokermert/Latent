import SwiftUI
import CoreImage
import ImageIO

/// Example photos for the film picker. Each one is the bundled base photo developed with the real
/// `FilmLook` pipeline at run time, so a sample shows exactly what that film does to a capture.
enum FilmSamples {
    /// Base photos `sample-1.jpg` … `sample-4.jpg`: portrait, sky and sea, street, evening interior.
    static let count = 4

    /// `index` is 0-based (`0..<count`). `maxPixel` is the long edge in pixels (not points).
    /// Rendered off the main thread and kept in memory; nil for a bad index or missing file.
    static func image(stock: FilmStock, index: Int, maxPixel: CGFloat) async -> UIImage? {
        guard (0..<count).contains(index), maxPixel > 0 else { return nil }
        let key = "\(stock.id)-\(index)-\(Int(maxPixel.rounded()))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = await Task.detached(priority: .userInitiated) { render(stock: stock, index: index, maxPixel: maxPixel) }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    /// NSCache is thread-safe.
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 64
        return cache
    }()

    private static func render(stock: FilmStock, index: Int, maxPixel: CGFloat) -> UIImage? {
        guard let url = Bundle.main.url(forResource: "sample-\(index + 1)", withExtension: "jpg"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel.rounded()),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let base = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        // Fixed seed: the same sample always shows the same grain.
        let output = FilmLook.apply(CIImage(cgImage: base), stock: stock, seed: 0x5A3D_0000 + UInt64(index))
        guard let rendered = PhotoProcessor.ciContext.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: rendered)
    }
}

#if DEBUG
/// Every film (rows) on every sample (columns), for tuning `FilmLook.parameters(for:)` in Xcode Previews.
struct FilmLookPreviewGrid: View {
    var maxPixel: CGFloat = 600
    @State private var images: [String: UIImage] = [:]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(horizontalSpacing: 6, verticalSpacing: 10) {
                ForEach(FilmStock.all) { stock in
                    GridRow {
                        Text(stock.shortName)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .frame(width: 80, alignment: .leading)
                        ForEach(0..<FilmSamples.count, id: \.self) { index in
                            Group {
                                if let image = images["\(stock.id)-\(index)"] {
                                    Image(uiImage: image).resizable().scaledToFit()
                                } else {
                                    Color.gray.opacity(0.2)
                                }
                            }
                            .frame(width: 180, height: 180)
                        }
                    }
                }
            }
            .padding()
        }
        .task {
            for stock in FilmStock.all {
                for index in 0..<FilmSamples.count {
                    images["\(stock.id)-\(index)"] = await FilmSamples.image(stock: stock, index: index, maxPixel: maxPixel)
                }
            }
        }
    }
}

#Preview("Film görünümleri") {
    FilmLookPreviewGrid()
}
#endif
