import Foundation
import CoreGraphics
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
        print("7 core checks passed.")
    }
}
