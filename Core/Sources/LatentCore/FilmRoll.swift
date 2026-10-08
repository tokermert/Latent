import Foundation
import CoreGraphics

public enum FrameOrientation: String, Codable, Sendable {
    case portrait, landscape
    public var aspectRatio: Double { self == .portrait ? 2.0 / 3.0 : 3.0 / 2.0 }
}

public struct FilmFrame: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let capturedAt: Date
    public let orientation: FrameOrientation
    public init(id: UUID = UUID(), capturedAt: Date = Date(), orientation: FrameOrientation) {
        self.id = id; self.capturedAt = capturedAt; self.orientation = orientation
    }
}

public struct FilmRoll: Identifiable, Codable, Hashable, Sendable {
    public static let capacity = 36
    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let film: String
    public internal(set) var frames: [FilmFrame]
    public internal(set) var finishedAt: Date?
    public var isFinished: Bool { finishedAt != nil || frames.count >= Self.capacity }
    public var remaining: Int { max(0, Self.capacity - frames.count) }
    public init(title: String, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id; self.title = title; self.createdAt = createdAt
        self.film = "LATENT COLOR 400"; self.frames = []; self.finishedAt = nil
    }
}

public enum ImageVariant: String, Sendable { case original, developed, thumbnail }

public struct CaptureFiles: Sendable {
    public let original: Data
    public let developed: Data
    public let thumbnail: Data
    public init(original: Data, developed: Data, thumbnail: Data) {
        self.original = original; self.developed = developed; self.thumbnail = thumbnail
    }
}

public enum CropGeometry {
    /// A centered crop in the coordinate space of an already upright image.
    public static func rect(width: Double, height: Double, aspectRatio: Double) -> CGRect {
        guard width.isFinite, height.isFinite, aspectRatio.isFinite,
              width > 0, height > 0, aspectRatio > 0 else { return .zero }
        let croppedWidth = min(width, height * aspectRatio)
        let croppedHeight = min(height, width / aspectRatio)
        return CGRect(x: (width - croppedWidth) / 2, y: (height - croppedHeight) / 2,
                      width: croppedWidth, height: croppedHeight)
    }
}
