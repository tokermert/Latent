import XCTest
@testable import LatentCore

final class StorageTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LatentTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private var files: CaptureFiles {
        CaptureFiles(original: Data([1, 2, 3]), developed: Data([4, 5]), thumbnail: Data([6]))
    }
    private func photoNames(_ dir: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Photos").path))
    }
    private func manifestVersion(_ dir: URL) throws -> Int? {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("library.json")))
        return (object as? [String: Any])?["version"] as? Int
    }
    private func roll(_ repository: RollRepository, frames count: Int) async throws -> UUID {
        _ = try await repository.load()
        let id = try await repository.createRoll(title: "London")[0].id
        for _ in 0..<count { _ = try await repository.append(to: id, orientation: .portrait, files: files) }
        return id
    }

    func testVersion1ManifestMigratesWithoutLoss() async throws {
        let dir = try directory()
        let rollID = UUID(), frameIDs = [UUID(), UUID(), UUID()]
        let frames = frameIDs.map { #"{"id":"\#($0.uuidString)","capturedAt":0,"orientation":"portrait"}"# }.joined(separator: ",")
        let v1 = #"{"version":1,"rolls":[{"id":"\#(rollID.uuidString)","title":"London","createdAt":0,"film":"LATENT COLOR 400","frames":[\#(frames)],"finishedAt":10}]}"#
        try Data(v1.utf8).write(to: dir.appendingPathComponent("library.json"))
        let repository = RollRepository(directory: dir)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Photos"), withIntermediateDirectories: true)
        for id in frameIDs { for v in ImageVariant.allCases { try Data([1]).write(to: repository.imageURL(frameID: id, variant: v)) } }

        let rolls = try await repository.load()
        XCTAssertEqual(rolls.count, 1)
        XCTAssertEqual(rolls[0].title, "London")
        XCTAssertEqual(rolls[0].frames.map(\.id), frameIDs)
        XCTAssertEqual(rolls[0].frames.map(\.number), [1, 2, 3])
        XCTAssertEqual(rolls[0].exposuresUsed, 3)
        XCTAssertEqual(rolls[0].remaining, 33)
        XCTAssertNotNil(rolls[0].finishedAt)
        XCTAssertNil(rolls[0].coverFrameID)
        XCTAssertEqual(rolls[0].coverFrame?.id, frameIDs[0])
        XCTAssertEqual(try photoNames(dir).count, 9, "Migration must keep every referenced photo")

        let renamed = try await repository.renameRoll(rollID, title: "Londra")
        XCTAssertEqual(try manifestVersion(dir), 2)
        let reloaded = try await RollRepository(directory: dir).load()
        XCTAssertEqual(reloaded, renamed)
    }

    func testFutureManifestIsUnsupportedAndUntouched() async throws {
        let dir = try directory(); let url = dir.appendingPathComponent("library.json")
        let bytes = Data(#"{"version":3,"rolls":[]}"#.utf8); try bytes.write(to: url)
        do { _ = try await RollRepository(directory: dir).load(); XCTFail("Loaded a newer manifest") }
        catch { XCTAssertEqual(error as? LibraryError, .unsupportedLibrary) }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testInconsistentNumbersAreDamaged() async throws {
        let dir = try directory()
        let frames = [2, 1].map { #"{"id":"\#(UUID().uuidString)","number":\#($0),"capturedAt":0,"orientation":"portrait"}"# }.joined(separator: ",")
        let v2 = #"{"version":2,"rolls":[{"id":"\#(UUID().uuidString)","title":"X","createdAt":0,"film":"LATENT COLOR 400","frames":[\#(frames)],"exposuresUsed":2}]}"#
        try Data(v2.utf8).write(to: dir.appendingPathComponent("library.json"))
        do { _ = try await RollRepository(directory: dir).load(); XCTFail("Accepted out-of-order numbers") }
        catch { XCTAssertEqual(error as? LibraryError, .damagedLibrary) }
    }

    func testDeletedFrameKeepsNumbersAndSlot() async throws {
        let dir = try directory(); let repository = RollRepository(directory: dir)
        let id = try await roll(repository, frames: 5)
        let before = try await repository.load()[0]
        let deleted = before.frames[2]
        let after = try await repository.deleteFrame(rollID: id, frameID: deleted.id)[0]
        XCTAssertEqual(after.frames.map(\.number), [1, 2, 4, 5])
        XCTAssertEqual(after.exposuresUsed, 5); XCTAssertEqual(after.remaining, 31)
        for v in ImageVariant.allCases {
            XCTAssertFalse(FileManager.default.fileExists(atPath: repository.imageURL(frameID: deleted.id, variant: v).path))
        }
        XCTAssertEqual(try photoNames(dir).count, 12)
        let next = try await repository.append(to: id, orientation: .landscape, files: files)[0]
        XCTAssertEqual(next.frames.map(\.number), [1, 2, 4, 5, 6])
        let reloaded = try await RollRepository(directory: dir).load()
        XCTAssertEqual(reloaded[0], next)
        do { _ = try await repository.deleteFrame(rollID: id, frameID: deleted.id); XCTFail("Deleted twice") }
        catch { XCTAssertEqual(error as? LibraryError, .missingFrame) }
    }

    func testDeletingDoesNotReopenThirtySixLimit() async throws {
        let repository = RollRepository(directory: try directory())
        let id = try await roll(repository, frames: 35)
        var current = try await repository.load()[0]
        current = try await repository.deleteFrame(rollID: id, frameID: current.frames[0].id)[0]
        current = try await repository.deleteFrame(rollID: id, frameID: current.frames[0].id)[0]
        XCTAssertEqual(current.remaining, 1); XCTAssertFalse(current.isFinished)
        current = try await repository.append(to: id, orientation: .portrait, files: files)[0]
        XCTAssertEqual(current.frames.count, 34); XCTAssertTrue(current.isFinished)
        XCTAssertEqual(current.frames.last?.number, 36)
        do { _ = try await repository.append(to: id, orientation: .portrait, files: files); XCTFail("37th exposure accepted") }
        catch { XCTAssertEqual(error as? LibraryError, .finishedRoll) }
    }

    func testOrphanCleanupRemovesOnlyUnreferencedFrameFiles() async throws {
        let dir = try directory(); let repository = RollRepository(directory: dir)
        _ = try await roll(repository, frames: 1)
        let photos = dir.appendingPathComponent("Photos")
        let orphan = UUID()
        let orphanNames = ImageVariant.allCases.map { "\(orphan.uuidString)-\($0.rawValue).jpg" }
        let foreign = ["notes.txt", "\(UUID().uuidString)-raw.jpg", "\(UUID().uuidString.lowercased())-original.jpg", "IMG_0001.jpg"]
        for name in orphanNames + foreign { try Data([9]).write(to: photos.appendingPathComponent(name)) }
        _ = try await RollRepository(directory: dir).load()
        let names = try photoNames(dir)
        XCTAssertTrue(names.isDisjoint(with: orphanNames))
        XCTAssertTrue(Set(foreign).isSubset(of: names))
        XCTAssertEqual(names.count, 3 + foreign.count)
    }

    func testOrphanCleanupNeverRunsOnUnreadableManifest() async throws {
        let dir = try directory(); let repository = RollRepository(directory: dir)
        _ = try await roll(repository, frames: 1)
        let manifest = dir.appendingPathComponent("library.json")
        for bytes in [Data("broken".utf8), Data(#"{"version":99,"rolls":[]}"#.utf8)] {
            try bytes.write(to: manifest)
            do { _ = try await RollRepository(directory: dir).load(); XCTFail("Loaded unreadable manifest") } catch { }
            XCTAssertEqual(try photoNames(dir).count, 3, "Photos deleted while manifest was unreadable")
        }
    }

    func testMissingManifestNeverDeletesPhotos() async throws {
        let dir = try directory(); let repository = RollRepository(directory: dir)
        _ = try await roll(repository, frames: 1)
        try FileManager.default.removeItem(at: dir.appendingPathComponent("library.json"))
        let rolls = try await RollRepository(directory: dir).load()
        XCTAssertTrue(rolls.isEmpty)
        XCTAssertEqual(try photoNames(dir).count, 3, "Photos deleted without a manifest")
    }

    func testDeleteRollRemovesManifestEntryThenFiles() async throws {
        let dir = try directory(); let repository = RollRepository(directory: dir)
        let doomed = try await roll(repository, frames: 2)
        let kept = try await repository.createRoll(title: "Kept")[0].id
        _ = try await repository.append(to: kept, orientation: .portrait, files: files)
        let rolls = try await repository.deleteRoll(doomed)
        XCTAssertEqual(rolls.map(\.id), [kept])
        XCTAssertEqual(try photoNames(dir).count, 3)
        let reloaded = try await RollRepository(directory: dir).load()
        XCTAssertEqual(reloaded, rolls)
        do { _ = try await repository.deleteRoll(doomed); XCTFail("Deleted twice") }
        catch { XCTAssertEqual(error as? LibraryError, .missingRoll) }
    }

    func testFailedDeleteCommitKeepsFiles() async throws {
        let dir = try directory(); let repository = RollRepository(directory: dir)
        let id = try await roll(repository, frames: 1)
        let manifest = dir.appendingPathComponent("library.json")
        try FileManager.default.removeItem(at: manifest)
        try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
        do { _ = try await repository.deleteRoll(id); XCTFail("Expected disk failure") } catch { }
        XCTAssertEqual(try photoNames(dir).count, 3)
        try FileManager.default.removeItem(at: manifest)
        let rolls = try await repository.finish(id)
        XCTAssertEqual(rolls.map(\.id), [id], "Failed delete changed in-memory state")
    }

    func testRenameRoll() async throws {
        let repository = RollRepository(directory: try directory())
        let id = try await roll(repository, frames: 0)
        let trimmed = try await repository.renameRoll(id, title: "  Paris \n")[0].title
        XCTAssertEqual(trimmed, "Paris")
        let long = try await repository.renameRoll(id, title: String(repeating: "a", count: 80))[0].title
        XCTAssertEqual(long.count, 60)
        do { _ = try await repository.renameRoll(id, title: "   "); XCTFail("Accepted empty title") }
        catch { XCTAssertEqual(error as? LibraryError, .emptyTitle) }
        do { _ = try await repository.renameRoll(UUID(), title: "X"); XCTFail("Renamed missing roll") }
        catch { XCTAssertEqual(error as? LibraryError, .missingRoll) }
    }

    func testCoverSelectionAndFallback() async throws {
        let dir = try directory(); let repository = RollRepository(directory: dir)
        let id = try await roll(repository, frames: 3)
        let frames = try await repository.load()[0].frames
        var current = try await repository.setCover(id, frameID: frames[1].id)[0]
        XCTAssertEqual(current.coverFrame?.id, frames[1].id)
        let reloaded = try await RollRepository(directory: dir).load()
        XCTAssertEqual(reloaded[0].coverFrameID, frames[1].id)
        do { _ = try await repository.setCover(id, frameID: UUID()); XCTFail("Accepted foreign frame") }
        catch { XCTAssertEqual(error as? LibraryError, .missingFrame) }
        current = try await repository.deleteFrame(rollID: id, frameID: frames[1].id)[0]
        XCTAssertNil(current.coverFrameID); XCTAssertEqual(current.coverFrame?.id, frames[0].id)
        _ = try await repository.setCover(id, frameID: frames[2].id)
        current = try await repository.setCover(id, frameID: nil)[0]
        XCTAssertEqual(current.coverFrame?.id, frames[0].id)
    }

    func testShareExportsClear() throws {
        let tmp = try directory()
        let shares = ShareExports.directory(in: tmp)
        try FileManager.default.createDirectory(at: shares, withIntermediateDirectories: true)
        try Data([1]).write(to: shares.appendingPathComponent("Latent-x.jpg"))
        ShareExports.clear(in: tmp)
        XCTAssertFalse(FileManager.default.fileExists(atPath: shares.path))
        ShareExports.clear(in: tmp) // missing directory is fine
    }
}
