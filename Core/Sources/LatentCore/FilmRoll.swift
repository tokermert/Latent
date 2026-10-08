import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum FrameOrientation: String, Codable, Sendable {
    case portrait, landscape
    public var aspectRatio: Double { self == .portrait ? 2.0 / 3.0 : 3.0 / 2.0 }
}

public struct FilmFrame: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    /// Exposure number on the roll (1...36). Kept when earlier frames are deleted.
    public internal(set) var number: Int
    public let capturedAt: Date
    public let orientation: FrameOrientation
    public init(id: UUID = UUID(), number: Int, capturedAt: Date = Date(), orientation: FrameOrientation) {
        self.id = id; self.number = number; self.capturedAt = capturedAt; self.orientation = orientation
    }

    private enum CodingKeys: String, CodingKey { case id, number, capturedAt, orientation }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        // Version 1 manifests have no number; RollRepository assigns it during migration.
        number = try c.decodeIfPresent(Int.self, forKey: .number) ?? 0
        capturedAt = try c.decode(Date.self, forKey: .capturedAt)
        orientation = try c.decode(FrameOrientation.self, forKey: .orientation)
    }
}

public struct FilmRoll: Identifiable, Codable, Hashable, Sendable {
    public static let capacity = 36
    public let id: UUID
    public internal(set) var title: String
    public let createdAt: Date
    public let film: String
    public internal(set) var frames: [FilmFrame]
    public internal(set) var finishedAt: Date?
    /// Exposures taken on this roll, including deleted frames. A deleted frame never frees a slot.
    public internal(set) var exposuresUsed: Int
    /// Chosen cover; nil means the first remaining frame.
    public internal(set) var coverFrameID: UUID?
    public var isFinished: Bool { finishedAt != nil || exposuresUsed >= Self.capacity }
    public var remaining: Int { max(0, Self.capacity - exposuresUsed) }
    /// Number the next capture will carry.
    public var nextFrameNumber: Int { exposuresUsed + 1 }
    public var coverFrame: FilmFrame? {
        if let coverFrameID, let frame = frames.first(where: { $0.id == coverFrameID }) { return frame }
        return frames.first
    }
    public init(title: String, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id; self.title = title; self.createdAt = createdAt
        self.film = "LATENT COLOR 400"; self.frames = []; self.finishedAt = nil
        self.exposuresUsed = 0; self.coverFrameID = nil
    }

    private enum CodingKeys: String, CodingKey { case id, title, createdAt, film, frames, finishedAt, exposuresUsed, coverFrameID }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        film = try c.decode(String.self, forKey: .film)
        frames = try c.decode([FilmFrame].self, forKey: .frames)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        // Version 1: no deletions existed, so every exposure is still in `frames`.
        exposuresUsed = try c.decodeIfPresent(Int.self, forKey: .exposuresUsed) ?? frames.count
        coverFrameID = try c.decodeIfPresent(UUID.self, forKey: .coverFrameID)
    }
}

public enum ImageVariant: String, CaseIterable, Sendable { case original, developed, thumbnail }

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
