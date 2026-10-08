import Foundation

public enum LibraryError: LocalizedError, Equatable {
    case notLoaded, missingRoll, finishedRoll, emptyTitle, emptyImage, unsupportedLibrary, damagedLibrary
    public var errorDescription: String? {
        switch self {
        case .notLoaded: return "Fotoğraf arşivi henüz hazır değil."
        case .missingRoll: return "Bu rulo bulunamadı."
        case .finishedRoll: return "Bu rulo tamamlandı. Yeni bir rulo başlat."
        case .emptyTitle: return "Rulona bir isim ver."
        case .emptyImage: return "Fotoğraf verisi alınamadı; kare sayacın değişmedi."
        case .unsupportedLibrary: return "Bu arşiv daha yeni bir Latent sürümüyle oluşturulmuş."
        case .damagedLibrary: return "Arşiv okunamadı. Mevcut fotoğrafların değiştirilmedi."
        }
    }
}

public actor RollRepository {
    private struct Snapshot: Codable {
        var version = 1
        var rolls: [FilmRoll] = []
    }
    public nonisolated let directory: URL
    private var snapshot: Snapshot?
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder
    }()
    public init(directory: URL) { self.directory = directory }

    public nonisolated func imageURL(frameID: UUID, variant: ImageVariant) -> URL {
        directory.appendingPathComponent("Photos", isDirectory: true)
            .appendingPathComponent("\(frameID.uuidString)-\(variant.rawValue).jpg")
    }

    @discardableResult public func load() throws -> [FilmRoll] {
        snapshot = nil
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Photos", isDirectory: true),
                                                withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("library.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let decoded: Snapshot
            do { decoded = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url)) }
            catch { throw LibraryError.damagedLibrary }
            guard decoded.version == 1 else { throw LibraryError.unsupportedLibrary }
            let ids = decoded.rolls.map(\.id)
            let frames = decoded.rolls.flatMap(\.frames).map(\.id)
            guard Set(ids).count == ids.count, Set(frames).count == frames.count,
                  decoded.rolls.allSatisfy({ $0.frames.count <= FilmRoll.capacity }) else {
                throw LibraryError.damagedLibrary
            }
            snapshot = decoded
        } else { snapshot = Snapshot() }
        return snapshot!.rolls
    }

    public func createRoll(title: String) throws -> [FilmRoll] {
        guard var next = snapshot else { throw LibraryError.notLoaded }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw LibraryError.emptyTitle }
        next.rolls.insert(FilmRoll(title: String(title.prefix(60))), at: 0)
        try commit(next)
        return next.rolls
    }

    public func append(to rollID: UUID, orientation: FrameOrientation, files: CaptureFiles) throws -> [FilmRoll] {
        guard var next = snapshot else { throw LibraryError.notLoaded }
        guard let index = next.rolls.firstIndex(where: { $0.id == rollID }) else { throw LibraryError.missingRoll }
        guard !next.rolls[index].isFinished else { throw LibraryError.finishedRoll }
        guard !files.original.isEmpty, !files.developed.isEmpty, !files.thumbnail.isEmpty else { throw LibraryError.emptyImage }
        let frame = FilmFrame(orientation: orientation)
        let writes: [(ImageVariant, Data)] = [(.original, files.original), (.developed, files.developed), (.thumbnail, files.thumbnail)]
        var written: [URL] = []
        do {
            for (variant, data) in writes {
                let url = imageURL(frameID: frame.id, variant: variant)
                try data.write(to: url, options: .atomic)
                written.append(url)
            }
            next.rolls[index].frames.append(frame)
            if next.rolls[index].frames.count == FilmRoll.capacity { next.rolls[index].finishedAt = Date() }
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

    private func commit(_ next: Snapshot) throws {
        try encoder.encode(next).write(to: directory.appendingPathComponent("library.json"), options: .atomic)
        snapshot = next
    }
}
