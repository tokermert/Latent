import Foundation

public enum LibraryError: LocalizedError, Equatable {
    case notLoaded, missingRoll, missingFrame, finishedRoll, emptyTitle, emptyImage, unsupportedLibrary, damagedLibrary
    public var errorDescription: String? {
        switch self {
        case .notLoaded: return "Fotoğraf arşivi henüz hazır değil."
        case .missingRoll: return "Bu rulo bulunamadı."
        case .missingFrame: return "Bu kare bulunamadı."
        case .finishedRoll: return "Bu rulo tamamlandı. Yeni bir rulo başlat."
        case .emptyTitle: return "Rulona bir isim ver."
        case .emptyImage: return "Fotoğraf verisi alınamadı; kare sayacın değişmedi."
        case .unsupportedLibrary: return "Bu arşiv daha yeni bir Latent sürümüyle oluşturulmuş."
        case .damagedLibrary: return "Arşiv okunamadı. Mevcut fotoğrafların değiştirilmedi."
        }
    }
}

/// Temporary framed images handed to the share sheet. Safe to clear at launch.
public enum ShareExports {
    public static func directory(in temporaryDirectory: URL = FileManager.default.temporaryDirectory) -> URL {
        temporaryDirectory.appendingPathComponent("LatentShares", isDirectory: true)
    }
    public static func clear(in temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        try? FileManager.default.removeItem(at: directory(in: temporaryDirectory))
    }
}

public actor RollRepository {
    /// Manifest schema. 1: initial release. 2: frame numbers, exposure counter, cover frame.
    public static let manifestVersion = 2
    private struct Header: Decodable { var version: Int }
    private struct Snapshot: Codable {
        var version = RollRepository.manifestVersion
        var rolls: [FilmRoll] = []
    }
    public nonisolated let directory: URL
    private var snapshot: Snapshot?
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder
    }()
    public init(directory: URL) { self.directory = directory }

    private nonisolated var photosDirectory: URL { directory.appendingPathComponent("Photos", isDirectory: true) }

    public nonisolated func imageURL(frameID: UUID, variant: ImageVariant) -> URL {
        photosDirectory.appendingPathComponent("\(frameID.uuidString)-\(variant.rawValue).jpg")
    }

    @discardableResult public func load() throws -> [FilmRoll] {
        snapshot = nil
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("library.json")
        if FileManager.default.fileExists(atPath: url.path) {
            var decoded: Snapshot
            do {
                let data = try Data(contentsOf: url)
                let version = try JSONDecoder().decode(Header.self, from: data).version
                guard (1...Self.manifestVersion).contains(version) else { throw LibraryError.unsupportedLibrary }
                decoded = try JSONDecoder().decode(Snapshot.self, from: data)
            } catch LibraryError.unsupportedLibrary { throw LibraryError.unsupportedLibrary }
            catch { throw LibraryError.damagedLibrary }
            if decoded.version == 1 { Self.migrateFromVersion1(&decoded) }
            try Self.validate(&decoded)
            snapshot = decoded
            // Only after an existing manifest was read successfully: a missing or unreadable
            // manifest must never cost photographs.
            removeOrphanedFiles(keeping: decoded.rolls)
        } else { snapshot = Snapshot() }
        return snapshot!.rolls
    }

    public func createRoll(title: String) throws -> [FilmRoll] {
        guard var next = snapshot else { throw LibraryError.notLoaded }
        next.rolls.insert(FilmRoll(title: try Self.normalizedTitle(title)), at: 0)
        try commit(next)
        return next.rolls
    }

    public func renameRoll(_ rollID: UUID, title: String) throws -> [FilmRoll] {
        guard var next = snapshot else { throw LibraryError.notLoaded }
        guard let index = next.rolls.firstIndex(where: { $0.id == rollID }) else { throw LibraryError.missingRoll }
        next.rolls[index].title = try Self.normalizedTitle(title)
        try commit(next)
        return next.rolls
    }

    public func append(to rollID: UUID, orientation: FrameOrientation, files: CaptureFiles) throws -> [FilmRoll] {
        guard var next = snapshot else { throw LibraryError.notLoaded }
        guard let index = next.rolls.firstIndex(where: { $0.id == rollID }) else { throw LibraryError.missingRoll }
        guard !next.rolls[index].isFinished else { throw LibraryError.finishedRoll }
        guard !files.original.isEmpty, !files.developed.isEmpty, !files.thumbnail.isEmpty else { throw LibraryError.emptyImage }
        let frame = FilmFrame(number: next.rolls[index].nextFrameNumber, orientation: orientation)
        let writes: [(ImageVariant, Data)] = [(.original, files.original), (.developed, files.developed), (.thumbnail, files.thumbnail)]
        var written: [URL] = []
        do {
            for (variant, data) in writes {
                let url = imageURL(frameID: frame.id, variant: variant)
                try data.write(to: url, options: .atomic)
                written.append(url)
            }
            next.rolls[index].frames.append(frame)
            next.rolls[index].exposuresUsed += 1
            if next.rolls[index].exposuresUsed == FilmRoll.capacity { next.rolls[index].finishedAt = Date() }
            try commit(next)
        } catch {
            // Only remove files from this failed capture; never modify existing photographs.
            for url in written { try? FileManager.default.removeItem(at: url) }
            throw error
        }
        return next.rolls
    }

    public func finish(_ rollID: UUID) throws -> [FilmRoll] {
        guard var next = snapshot else { throw LibraryError.notLoaded }
        guard let index = next.rolls.firstIndex(where: { $0.id == rollID }) else { throw LibraryError.missingRoll }
        if next.rolls[index].finishedAt == nil { next.rolls[index].finishedAt = Date() }
        try commit(next)
        return next.rolls
    }

    /// `frameID == nil` resets the cover to the first frame.
    public func setCover(_ rollID: UUID, frameID: UUID?) throws -> [FilmRoll] {
        guard var next = snapshot else { throw LibraryError.notLoaded }
        guard let index = next.rolls.firstIndex(where: { $0.id == rollID }) else { throw LibraryError.missingRoll }
        if let frameID, !next.rolls[index].frames.contains(where: { $0.id == frameID }) { throw LibraryError.missingFrame }
        next.rolls[index].coverFrameID = frameID
        try commit(next)
        return next.rolls
    }

    /// Removes the roll from the manifest first, then its files. An interrupted delete leaves
    /// only orphaned files, which the next `load()` removes.
    public func deleteRoll(_ rollID: UUID) throws -> [FilmRoll] {
        guard var next = snapshot else { throw LibraryError.notLoaded }
        guard let index = next.rolls.firstIndex(where: { $0.id == rollID }) else { throw LibraryError.missingRoll }
        let removed = next.rolls.remove(at: index)
        try commit(next)
        removeFiles(of: removed.frames)
        return next.rolls
    }

    /// The exposure stays used: the roll's remaining count and other frame numbers do not change.
    public func deleteFrame(rollID: UUID, frameID: UUID) throws -> [FilmRoll] {
        guard var next = snapshot else { throw LibraryError.notLoaded }
        guard let index = next.rolls.firstIndex(where: { $0.id == rollID }) else { throw LibraryError.missingRoll }
        guard let frameIndex = next.rolls[index].frames.firstIndex(where: { $0.id == frameID }) else { throw LibraryError.missingFrame }
        let removed = next.rolls[index].frames.remove(at: frameIndex)
        if next.rolls[index].coverFrameID == frameID { next.rolls[index].coverFrameID = nil }
        try commit(next)
        removeFiles(of: [removed])
        return next.rolls
    }

    private func commit(_ next: Snapshot) throws {
        var next = next
        next.version = Self.manifestVersion
        try encoder.encode(next).write(to: directory.appendingPathComponent("library.json"), options: .atomic)
        snapshot = next
    }

    private func removeFiles(of frames: [FilmFrame]) {
        for frame in frames {
            for variant in ImageVariant.allCases { try? FileManager.default.removeItem(at: imageURL(frameID: frame.id, variant: variant)) }
        }
    }

    /// Deletes `<UUID>-<variant>.jpg` files whose frame is not in the manifest. Other names are left alone.
    private func removeOrphanedFiles(keeping rolls: [FilmRoll]) {
        let known = Set(rolls.flatMap(\.frames).map(\.id))
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: photosDirectory.path) else { return }
        for name in names {
            guard let id = Self.frameID(fromFileName: name), !known.contains(id) else { continue }
            try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(name))
        }
    }

    static func frameID(fromFileName name: String) -> UUID? {
        guard name.hasSuffix(".jpg") else { return nil }
        let stem = name.dropLast(4)
        guard let dash = stem.lastIndex(of: "-"),
              ImageVariant(rawValue: String(stem[stem.index(after: dash)...])) != nil else { return nil }
        let uuidText = String(stem[..<dash])
        guard let id = UUID(uuidString: uuidText), id.uuidString == uuidText else { return nil }
        return id
    }

    private static func normalizedTitle(_ title: String) throws -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw LibraryError.emptyTitle }
        return String(title.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Version 1 had no deletion: frame numbers follow array order and every exposure is still present.
    private static func migrateFromVersion1(_ snapshot: inout Snapshot) {
        for r in snapshot.rolls.indices {
            for f in snapshot.rolls[r].frames.indices { snapshot.rolls[r].frames[f].number = f + 1 }
            snapshot.rolls[r].exposuresUsed = snapshot.rolls[r].frames.count
            snapshot.rolls[r].coverFrameID = nil
        }
        snapshot.version = manifestVersion
    }

    private static func validate(_ snapshot: inout Snapshot) throws {
        let ids = snapshot.rolls.map(\.id)
        let frames = snapshot.rolls.flatMap(\.frames).map(\.id)
        guard Set(ids).count == ids.count, Set(frames).count == frames.count else { throw LibraryError.damagedLibrary }
        for r in snapshot.rolls.indices {
            let roll = snapshot.rolls[r]
            let numbers = roll.frames.map(\.number)
            guard roll.exposuresUsed <= FilmRoll.capacity, roll.frames.count <= roll.exposuresUsed,
                  numbers.allSatisfy({ $0 >= 1 && $0 <= roll.exposuresUsed }),
                  zip(numbers, numbers.dropFirst()).allSatisfy({ $0 < $1 }) else { throw LibraryError.damagedLibrary }
            // A dangling cover is harmless; fall back to the first frame rather than refusing the library.
            if let cover = roll.coverFrameID, !roll.frames.contains(where: { $0.id == cover }) {
                snapshot.rolls[r].coverFrameID = nil
            }
        }
    }
}
