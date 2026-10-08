import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import LatentCore

// A dependency-free smoke suite for Macs with Command Line Tools but no XCTest.
// The full regression suite remains in Tests/LatentCoreTests.
@main
struct Checks {
    enum Failure: Error { case check(String) }
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.check(message) }
    }
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LatentSmoke-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = RollRepository(directory: directory)
        let initial = try await repository.load()
        try require(initial.isEmpty, "Fresh library must be empty")
        let roll = try await repository.createRoll(title: "  London  ")[0]
        let files = CaptureFiles(original: Data([1, 2, 3]), developed: Data([4, 5]), thumbnail: Data([6]))
        _ = try await repository.append(to: roll.id, orientation: .portrait, files: files)
        let reopened = RollRepository(directory: directory)
        let saved = try await reopened.load()
        try require(saved[0].title == "London" && saved[0].frames.count == 1, "Relaunch lost a frame")
        let original = try Data(contentsOf: reopened.imageURL(frameID: saved[0].frames[0].id, variant: .original))
        try require(original == files.original, "Original bytes changed")
        print("PASS: relaunch and original preservation")

        for _ in 1..<36 { _ = try await reopened.append(to: roll.id, orientation: .landscape, files: files) }
        do { _ = try await reopened.append(to: roll.id, orientation: .portrait, files: files); throw Failure.check("37th frame accepted") }
        catch LibraryError.finishedRoll { }
        let paths = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Photos").path)
        try require(paths.count == 108, "Rejected capture created assets")
        print("PASS: 36-frame boundary and asset count")

        let early = try await reopened.createRoll(title: "Weekend")[0]
        _ = try await reopened.append(to: early.id, orientation: .portrait, files: files)
        let closed = try await reopened.finish(early.id)
        try require(closed[0].isFinished && closed[0].frames.count == 1, "Early finish removed frames")
        do { _ = try await reopened.append(to: early.id, orientation: .portrait, files: files); throw Failure.check("Closed roll accepted a frame") }
        catch LibraryError.finishedRoll { }
        print("PASS: early finish preserves photographs")

        let empty = try await reopened.createRoll(title: "Empty")[0]
        do {
            _ = try await reopened.append(to: empty.id, orientation: .portrait, files: CaptureFiles(original: Data(), developed: Data([1]), thumbnail: Data([1])))
            throw Failure.check("Empty capture accepted")
        } catch LibraryError.emptyImage { }
        let afterEmpty = try await reopened.load()
        try require(afterEmpty[0].frames.isEmpty, "Empty capture consumed a frame")
        print("PASS: empty capture leaves counter unchanged")

        let manifest = directory.appendingPathComponent("library.json")
        let previousManifest = try Data(contentsOf: manifest)
        try FileManager.default.removeItem(at: manifest)
        try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
        var failed = false
        do { _ = try await reopened.append(to: empty.id, orientation: .portrait, files: files) } catch { failed = true }
        try require(failed, "Manifest failure not propagated")
        let afterFailure = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Photos").path)
        try require(afterFailure.count == 111, "Failed capture left new orphan files")
        try FileManager.default.removeItem(at: manifest)
        try previousManifest.write(to: manifest)
        let retried = try await reopened.append(to: empty.id, orientation: .portrait, files: files)
        try require(retried[0].frames.count == 1, "Failed save changed in-memory counter")
        print("PASS: failed manifest write rolls back only new files")

        let broken = Data("broken".utf8); try broken.write(to: manifest)
        let damaged = RollRepository(directory: directory)
        do { _ = try await damaged.load(); throw Failure.check("Damaged library silently loaded") }
        catch LibraryError.damagedLibrary { }
        do { _ = try await damaged.createRoll(title: "No"); throw Failure.check("Damaged library overwritten") }
        catch LibraryError.notLoaded { }
        try require(try Data(contentsOf: manifest) == broken, "Damaged file changed")
        print("PASS: corrupt manifest preserved")

        try require(CropGeometry.rect(width: 3024, height: 4032, aspectRatio: 2.0 / 3.0) == CGRect(x: 168, y: 0, width: 2688, height: 4032), "Portrait crop mismatch")
        try require(CropGeometry.rect(width: 4032, height: 3024, aspectRatio: 1.5) == CGRect(x: 0, y: 168, width: 4032, height: 2688), "Landscape crop mismatch")
        print("PASS: centered 2:3 and 3:2 crop geometry")
        try await storageChecks()
        try await rollRuleChecks()
        print("20 core checks passed.")
    }

    static func photoCount(_ directory: URL) throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Photos").path).count
    }

    static func storageChecks() async throws {
        let files = CaptureFiles(original: Data([1, 2, 3]), developed: Data([4, 5]), thumbnail: Data([6]))
        func fresh() throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("LatentSmoke-\(UUID())")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        // Version 1 migration
        let v1Dir = try fresh(); defer { try? FileManager.default.removeItem(at: v1Dir) }
        let frameIDs = [UUID(), UUID(), UUID()]
        let frameJSON = frameIDs.map { #"{"id":"\#($0.uuidString)","capturedAt":0,"orientation":"landscape"}"# }.joined(separator: ",")
        let v1 = #"{"version":1,"rolls":[{"id":"\#(UUID().uuidString)","title":"London","createdAt":0,"film":"LATENT COLOR 400","frames":[\#(frameJSON)]}]}"#
        try Data(v1.utf8).write(to: v1Dir.appendingPathComponent("library.json"))
        let migrating = RollRepository(directory: v1Dir)
        try FileManager.default.createDirectory(at: v1Dir.appendingPathComponent("Photos"), withIntermediateDirectories: true)
        for id in frameIDs { for v in ImageVariant.allCases { try Data([1]).write(to: migrating.imageURL(frameID: id, variant: v)) } }
        let migrated = try await migrating.load()
        try require(migrated[0].frames.map(\.id) == frameIDs && migrated[0].frames.map(\.number) == [1, 2, 3], "v1 frames renumbered or lost")
        try require(migrated[0].exposuresUsed == 3 && migrated[0].remaining == 33 && migrated[0].coverFrameID == nil, "v1 counters wrong")
        try require(try photoCount(v1Dir) == 9, "Migration deleted referenced photos")
        let appended = try await migrating.append(to: migrated[0].id, orientation: .portrait, files: files)
        try require(appended[0].frames.last?.number == 4, "First v2 capture misnumbered")
        let header = try JSONSerialization.jsonObject(with: Data(contentsOf: v1Dir.appendingPathComponent("library.json"))) as? [String: Any]
        try require(header?["version"] as? Int == RollRepository.manifestVersion, "Commit did not write the current manifest version")
        let reread = try await RollRepository(directory: v1Dir).load()
        try require(reread == appended, "Migrated library changed on reload")
        print("PASS: version 1 manifest migrates without loss")

        // Frame deletion keeps numbers and does not return the exposure
        let dir = try fresh(); defer { try? FileManager.default.removeItem(at: dir) }
        let repository = RollRepository(directory: dir); _ = try await repository.load()
        let rollID = try await repository.createRoll(title: "Istanbul")[0].id
        var roll = FilmRoll(title: "")
        for _ in 0..<5 { roll = try await repository.append(to: rollID, orientation: .portrait, files: files)[0] }
        let deleted = roll.frames[2] // frame 03
        roll = try await repository.deleteFrame(rollID: rollID, frameID: deleted.id)[0]
        try require(roll.frames.map(\.number) == [1, 2, 4, 5] && roll.remaining == 31, "Delete renumbered or freed a slot")
        try require(try photoCount(dir) == 12, "Deleted frame files remain")
        roll = try await repository.append(to: rollID, orientation: .portrait, files: files)[0]
        try require(roll.frames.last?.number == 6, "Next capture reused a deleted number")
        print("PASS: frame deletion keeps numbering and counter")

        for _ in 0..<30 { roll = try await repository.append(to: rollID, orientation: .portrait, files: files)[0] }
        try require(roll.isFinished && roll.frames.count == 35 && roll.frames.last?.number == 36, "36 exposure boundary wrong after delete")
        do { _ = try await repository.append(to: rollID, orientation: .portrait, files: files); throw Failure.check("Deleted frame reopened the roll") }
        catch LibraryError.finishedRoll { }
        print("PASS: deleted frame never returns one of 36 exposures")

        // Cover
        roll = try await repository.setCover(rollID, frameID: roll.frames[3].id)[0]
        let coverID = roll.frames[3].id
        try require(roll.coverFrame?.id == coverID, "Cover not applied")
        roll = try await repository.deleteFrame(rollID: rollID, frameID: coverID)[0]
        try require(roll.coverFrameID == nil && roll.coverFrame?.id == roll.frames.first?.id, "Deleted cover not reset")
        print("PASS: cover selection and fallback")

        // Rename
        roll = try await repository.renameRoll(rollID, title: "  " + String(repeating: "x", count: 70))[0]
        try require(roll.title.count == 60 && !roll.title.hasPrefix(" "), "Rename not trimmed/limited")
        do { _ = try await repository.renameRoll(rollID, title: " \n "); throw Failure.check("Empty rename accepted") }
        catch LibraryError.emptyTitle { }
        print("PASS: rename trims and limits title")

        // Roll deletion
        let other = try await repository.createRoll(title: "Other")[0].id
        _ = try await repository.append(to: other, orientation: .landscape, files: files)
        let remaining = try await repository.deleteRoll(rollID)
        let photosLeft = try photoCount(dir)
        try require(remaining.map(\.id) == [other] && photosLeft == 3, "Roll delete left files or removed others")
        let reloaded = try await RollRepository(directory: dir).load()
        try require(reloaded == remaining, "Roll delete not persisted")
        print("PASS: roll deletion removes manifest entry and files")

        // Orphans: removed after a good load, never after a bad one
        let photos = dir.appendingPathComponent("Photos")
        let orphan = "\(UUID().uuidString)-developed.jpg"
        let foreign = ["notes.txt", "\(UUID().uuidString)-raw.jpg", "\(UUID().uuidString.lowercased())-original.jpg"]
        for name in [orphan] + foreign { try Data([9]).write(to: photos.appendingPathComponent(name)) }
        let manifest = dir.appendingPathComponent("library.json")
        let good = try Data(contentsOf: manifest)
        try Data("broken".utf8).write(to: manifest)
        do { _ = try await RollRepository(directory: dir).load(); throw Failure.check("Broken manifest loaded") }
        catch LibraryError.damagedLibrary { }
        try require(try photoCount(dir) == 3 + 1 + foreign.count, "Files deleted while manifest was broken")
        try FileManager.default.removeItem(at: manifest)
        _ = try await RollRepository(directory: dir).load()
        try require(try photoCount(dir) == 3 + 1 + foreign.count, "Files deleted while manifest was missing")
        try good.write(to: manifest)
        _ = try await RollRepository(directory: dir).load()
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: photos.path))
        try require(!names.contains(orphan) && Set(foreign).isSubset(of: names) && names.count == 3 + foreign.count, "Orphan cleanup wrong")
        print("PASS: orphan cleanup only after a readable manifest")

        // Share exports
        let tmp = try fresh(); defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: ShareExports.directory(in: tmp), withIntermediateDirectories: true)
        try Data([1]).write(to: ShareExports.directory(in: tmp).appendingPathComponent("Latent-x.jpg"))
        ShareExports.clear(in: tmp)
        try require(!FileManager.default.fileExists(atPath: ShareExports.directory(in: tmp).path), "Share exports not cleared")
        print("PASS: temporary share exports cleared")
    }

    static func rollRuleChecks() async throws {
        let files = CaptureFiles(original: Data([1, 2, 3]), developed: Data([4, 5]), thumbnail: Data([6]))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LatentSmoke-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifest = dir.appendingPathComponent("library.json")
        let repository = RollRepository(directory: dir); _ = try await repository.load()

        // Single active roll
        let london = try await repository.createRoll(title: "Gizli Londra")[0].id
        _ = try await repository.append(to: london, orientation: .portrait, files: files)
        let before = try Data(contentsOf: manifest)
        do { _ = try await repository.createRoll(title: "Paris"); throw Failure.check("Second open roll accepted") }
        catch LibraryError.activeRollExists { }
        try require(try Data(contentsOf: manifest) == before, "Rejected roll changed the manifest")
        print("PASS: only one roll may be open")

        let rolls = try await repository.createRoll(title: "Gizli Paris", finishingActive: true)
        try require(rolls.count == 2 && !rolls[0].isFinished && rolls[1].isFinished && rolls[1].frames.count == 1, "finishingActive wrong")
        let reread = try await RollRepository(directory: dir).load()
        try require(reread == rolls, "finishingActive not saved in one commit")
        let active = await repository.activeRoll()
        try require(active?.id == rolls[0].id, "Active roll is not the newest open roll")
        print("PASS: finishing the open roll and starting a new one")

        // Legacy archive with two open rolls: untouched, still blocks a new roll
        let legacyDir = FileManager.default.temporaryDirectory.appendingPathComponent("LatentSmoke-\(UUID())")
        defer { try? FileManager.default.removeItem(at: legacyDir) }
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let newer = UUID()
        let legacy = Data(#"{"version":2,"rolls":[{"id":"\#(UUID().uuidString)","title":"A","createdAt":0,"film":"LATENT COLOR 400","frames":[],"exposuresUsed":0},{"id":"\#(newer.uuidString)","title":"B","createdAt":50,"film":"LATENT COLOR 400","frames":[],"exposuresUsed":0}]}"#.utf8)
        try legacy.write(to: legacyDir.appendingPathComponent("library.json"))
        let legacyRepository = RollRepository(directory: legacyDir)
        let legacyRolls = try await legacyRepository.load()
        try require(legacyRolls.allSatisfy { !$0.isFinished } && FilmRoll.activeRoll(in: legacyRolls)?.id == newer, "Legacy open rolls changed")
        do { _ = try await legacyRepository.createRoll(title: "C"); throw Failure.check("Legacy archive accepted a third open roll") }
        catch LibraryError.activeRollExists { }
        try require(try Data(contentsOf: legacyDir.appendingPathComponent("library.json")) == legacy, "Legacy manifest rewritten")
        print("PASS: legacy archive with several open rolls is left alone")

        // Counters persist in manifest v3
        _ = try await repository.recordAlbumOpened(london)
        _ = try await repository.recordAlbumOpened(london)
        let counted = try await repository.recordShare(london)
        let header = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any]
        let countedReread = try await RollRepository(directory: dir).load()
        try require(counted[1].albumOpenCount == 2 && counted[1].shareCount == 1 && countedReread == counted
                    && header?["version"] as? Int == 3, "Counters not persisted in v3")
        try require(legacyRolls.allSatisfy { $0.albumOpenCount == 0 && $0.shareCount == 0 }, "v2 counters not defaulted to 0")
        print("PASS: album-open and share counters (manifest v3)")

        // Feedback summary: numbers only
        let summary = FeedbackSummary(rolls: counted, appVersion: "0.1.0 (1)")
        let json = String(decoding: try summary.jsonData(), as: UTF8.self)
        try require(summary.rollCount == 2 && summary.rolls.map(\.finishKind) == [.early, .inProgress], "Summary finish kinds wrong")
        try require(summary.rolls[0].exposuresUsed == 1 && summary.rolls[0].albumOpenCount == 2 && summary.rolls[0].shareCount == 1
                    && summary.rolls[0].orientations.portrait == 1 && summary.rolls[0].deletedFrames == 0, "Summary counts wrong")
        try require(!json.contains("Gizli") && !counted.contains { json.contains($0.id.uuidString) }
                    && !counted.flatMap(\.frames).contains { json.contains($0.id.uuidString) }, "Summary leaks titles or ids")
        print("PASS: feedback summary has counts and no titles or ids")
    }
}
