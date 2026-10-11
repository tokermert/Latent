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
    /// Beta measurement counters (PRD §12). Stay on device unless the user shares a summary.
    public internal(set) var albumOpenCount: Int
    public internal(set) var shareCount: Int
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
        self.albumOpenCount = 0; self.shareCount = 0
    }

    /// Only one roll may be open at a time: the newest unfinished one. Archives from before this
    /// rule may hold several unfinished rolls; they are left as they are.
    public static func activeRoll(in rolls: [FilmRoll]) -> FilmRoll? {
        rolls.filter { !$0.isFinished }.max { $0.createdAt < $1.createdAt }
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, film, frames, finishedAt, exposuresUsed, coverFrameID, albumOpenCount, shareCount
    }
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
        albumOpenCount = try c.decodeIfPresent(Int.self, forKey: .albumOpenCount) ?? 0
        shareCount = try c.decodeIfPresent(Int.self, forKey: .shareCount) ?? 0
    }
}

/// The optional roll summary a beta tester shares by hand (PRD §12).
/// Numbers and times only: no roll title, photo, file path, location or identifier.
public struct FeedbackSummary: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public enum FinishKind: String, Codable, Sendable {
        /// All 36 exposures used.
        case full
        /// Finished before 36.
        case early
        /// Still open.
        case inProgress
    }
    public struct Frame: Codable, Equatable, Sendable {
        public var number: Int
        public var capturedAt: Date
    }
    public struct Orientations: Codable, Equatable, Sendable {
        public var portrait: Int
        public var landscape: Int
    }
    public struct Roll: Codable, Equatable, Sendable {
        /// 1 = oldest roll. Stands in for the roll identifier.
        public var index: Int
        public var createdAt: Date
        public var finishedAt: Date?
        public var finishKind: FinishKind
        public var exposuresUsed: Int
        public var remaining: Int
        public var deletedFrames: Int
        public var frames: [Frame]
        public var orientations: Orientations
        public var albumOpenCount: Int
        public var shareCount: Int
    }

    public var schemaVersion: Int
    public var appVersion: String
    public var generatedAt: Date
    public var rollCount: Int
    public var rolls: [Roll]

    public init(rolls: [FilmRoll], appVersion: String, generatedAt: Date = Date()) {
        schemaVersion = Self.currentSchemaVersion
        self.appVersion = appVersion
        self.generatedAt = generatedAt
        rollCount = rolls.count
        self.rolls = rolls.sorted { $0.createdAt < $1.createdAt }.enumerated().map { offset, roll in
            Roll(index: offset + 1,
                 createdAt: roll.createdAt,
                 finishedAt: roll.finishedAt,
                 finishKind: roll.exposuresUsed >= FilmRoll.capacity ? .full : (roll.isFinished ? .early : .inProgress),
                 exposuresUsed: roll.exposuresUsed,
                 remaining: roll.remaining,
                 deletedFrames: max(0, roll.exposuresUsed - roll.frames.count),
                 frames: roll.frames.map { Frame(number: $0.number, capturedAt: $0.capturedAt) },
                 orientations: Orientations(portrait: roll.frames.filter { $0.orientation == .portrait }.count,
                                            landscape: roll.frames.filter { $0.orientation == .landscape }.count),
                 albumOpenCount: roll.albumOpenCount,
                 shareCount: roll.shareCount)
        }
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public func jsonData() throws -> Data { try Self.makeEncoder().encode(self) }

    /// Writes `latent-ozet-<yyyy-MM-dd>.json` into `directory` (the share-exports folder in the app).
    @discardableResult public func write(in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let url = directory.appendingPathComponent("latent-ozet-\(formatter.string(from: generatedAt)).json")
        try jsonData().write(to: url, options: .atomic)
        return url
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
