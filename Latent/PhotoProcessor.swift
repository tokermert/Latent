import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct ProcessedCapture: Sendable {
    let files: CaptureFiles
    let orientation: FrameOrientation
}

enum PhotoProcessingError: LocalizedError {
    case unreadableImage
    var errorDescription: String? { "Fotoğraf işlenemedi. Lütfen tekrar dene." }
}

enum PhotoProcessor {
    static func process(data: Data, orientation: FrameOrientation) throws -> ProcessedCapture {
        guard let input = UIImage(data: data) else { throw PhotoProcessingError.unreadableImage }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        // Drawing applies EXIF rotation before calculating a portrait/landscape crop.
        let normalized = UIGraphicsImageRenderer(size: input.size, format: format).image { _ in
            input.draw(in: CGRect(origin: .zero, size: input.size))
        }
        guard let cg = normalized.cgImage else { throw PhotoProcessingError.unreadableImage }
        let crop = CropGeometry.rect(width: Double(cg.width), height: Double(cg.height), aspectRatio: orientation.aspectRatio)
        guard let cropped = cg.cropping(to: crop.integral) else { throw PhotoProcessingError.unreadableImage }
        // Original Latent look; this is not an official film-stock emulation.
        let color = CIFilter.colorControls()
        color.inputImage = CIImage(cgImage: cropped)
        color.saturation = 0.9; color.contrast = 1.04; color.brightness = 0.01
        guard let output = color.outputImage,
              let rendered = CIContext().createCGImage(output, from: output.extent) else { throw PhotoProcessingError.unreadableImage }
        let image = UIImage(cgImage: rendered)
        let scale = min(1, 500 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let developed = image.jpegData(compressionQuality: 0.94), let small = thumbnail.jpegData(compressionQuality: 0.8) else { throw PhotoProcessingError.unreadableImage }
        return ProcessedCapture(files: CaptureFiles(original: data, developed: developed, thumbnail: small), orientation: orientation)
    }

    static func framedExport(imageURL: URL, title: String, number: Int, film: String, capturedAt: Date) throws -> URL {
        guard let input = UIImage(contentsOfFile: imageURL.path) else { throw PhotoProcessingError.unreadableImage }
        let width: CGFloat = 1800
        let border: CGFloat = 140
        let filmSide: CGFloat = 38
        let photoWidth = width - border * 2 - filmSide * 2
        let photoHeight = photoWidth * input.size.height / input.size.width
        let height = photoHeight + 360
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let filmRect = CGRect(x: border, y: 110, width: width - border * 2, height: photoHeight + 90)
            UIColor(red: 0.07, green: 0.08, blue: 0.06, alpha: 1).setFill(); context.fill(filmRect)
            let photoRect = CGRect(x: border + filmSide, y: 135, width: photoWidth, height: photoHeight)
            input.draw(in: photoRect)
            // Köşe tarih damgası: ekrandaki `DateStamp` ile aynı oran, renk ve hafif ışıma.
            let stampSize = max(photoWidth, photoHeight) * FilmImprint.stampScale
            let stampStyle: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: stampSize, weight: .semibold), .foregroundColor: FilmImprint.stampUIColor]
            let stamp = FilmImprint.stamp(capturedAt) as NSString
            let stampBounds = stamp.size(withAttributes: stampStyle)
            context.cgContext.saveGState()
            context.cgContext.clip(to: photoRect)
            context.cgContext.setShadow(offset: .zero, blur: stampSize * 0.6, color: FilmImprint.stampUIColor.withAlphaComponent(0.7).cgColor)
            stamp.draw(at: CGPoint(x: photoRect.maxX - stampSize * 1.1 - stampBounds.width, y: photoRect.maxY - stampSize * 0.8 - stampBounds.height), withAttributes: stampStyle)
            context.cgContext.restoreGState()
            let gold = UIColor(red: 0.85, green: 0.74, blue: 0.49, alpha: 1)
            gold.setFill()
            for tick in 0..<12 { context.fill(CGRect(x: width - border - 24, y: 170 + CGFloat(tick) * 24, width: 13, height: 13)) }
            let edgeStyle: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 18, weight: .regular), .foregroundColor: gold]
            (FilmImprint.edge(film: film, number: number, date: capturedAt, compact: false) as NSString).draw(at: CGPoint(x: border + filmSide, y: photoHeight + 155), withAttributes: edgeStyle)
            let titleStyle: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 40, weight: .medium), .foregroundColor: UIColor.black]
            (title as NSString).draw(in: CGRect(x: border, y: height - 110, width: width - border * 2, height: 58), withAttributes: titleStyle)
        }
        guard let data = image.jpegData(compressionQuality: 0.94) else { throw PhotoProcessingError.unreadableImage }
        let directory = ShareExports.directory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Latent-\(UUID().uuidString).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }
}
