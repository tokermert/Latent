import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import LatentCore

final class LibraryTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LatentTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }
    private var files: CaptureFiles {
        CaptureFiles(original: Data([1, 2, 3]), developed: Data([4, 5]), thumbnail: Data([6]))
    }

    func testRelaunchPreservesRollAndOriginalBytes() async throws {
        let dir = try directory(); let repository = RollRepository(directory: dir)
        _ = try await repository.load()
        let created = try await repository.createRoll(title: "  London  ")
        let saved = try await repository.append(to: created[0].id, orientation: .portrait, files: files)
        let reloaded = try await RollRepository(directory: dir).load()
        XCTAssertEqual(reloaded, saved)
        XCTAssertEqual(reloaded[0].title, "London")
        XCTAssertEqual(try Data(contentsOf: repository.imageURL(frameID: saved[0].frames[0].id, variant: .original)), files.original)
    }

    func testThirtySeventhCaptureDoesNotWriteFiles() async throws {
        let dir = try directory(); let repository = RollRepository(directory: dir)
        _ = try await repository.load(); let id = try await repository.createRoll(title: "London")[0].id
        for _ in 0..<36 { _ = try await repository.append(to: id, orientation: .landscape, files: files) }
        do { _ = try await repository.append(to: id, orientation: .portrait, files: files); XCTFail("Accepted 37th frame") }
        catch { XCTAssertEqual(error as? LibraryError, .finishedRoll) }
        let rolls = try await repository.load()
        XCTAssertEqual(rolls[0].frames.count, 36); XCTAssertTrue(rolls[0].isFinished)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Photos").path).count, 108)
    }

    func testEarlyFinishKeepsFramesAndRejectsFurtherCapture() async throws {
        let repository = RollRepository(directory: try directory()); _ = try await repository.load()
        let id = try await repository.createRoll(title: "London")[0].id
        _ = try await repository.append(to: id, orientation: .portrait, files: files)
        let rolls = try await repository.finish(id)
        XCTAssertEqual(rolls[0].frames.count, 1); XCTAssertTrue(rolls[0].isFinished)
        do { _ = try await repository.append(to: id, orientation: .portrait, files: files); XCTFail("Accepted closed roll") }
        catch { XCTAssertEqual(error as? LibraryError, .finishedRoll) }
    }

    func testFailedManifestCommitRollsBackNewAssets() async throws {
        let dir = try directory(); let repository = RollRepository(directory: dir); _ = try await repository.load()
        let id = try await repository.createRoll(title: "London")[0].id
        let manifest = dir.appendingPathComponent("library.json")
        try FileManager.default.removeItem(at: manifest)
        try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
        do { _ = try await repository.append(to: id, orientation: .portrait, files: files); XCTFail("Expected disk failure") }
        catch { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Photos").path).isEmpty)
        try FileManager.default.removeItem(at: manifest)
        let saved = try await repository.append(to: id, orientation: .portrait, files: files)
        XCTAssertEqual(saved[0].frames.count, 1)
    }

    func testDamagedManifestIsNotSilentlyReplaced() async throws {
        let dir = try directory(); let url = dir.appendingPathComponent("library.json")
        let bytes = Data("damaged".utf8); try bytes.write(to: url)
        let repository = RollRepository(directory: dir)
        do { _ = try await repository.load(); XCTFail("Expected damaged library error") }
        catch { XCTAssertEqual(error as? LibraryError, .damagedLibrary) }
        do { _ = try await repository.createRoll(title: "New"); XCTFail("Should not overwrite unreadable library") }
        catch { XCTAssertEqual(error as? LibraryError, .notLoaded) }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testEmptyCaptureDoesNotConsumeFrame() async throws {
        let repository = RollRepository(directory: try directory()); _ = try await repository.load()
        let id = try await repository.createRoll(title: "London")[0].id
        do {
            _ = try await repository.append(to: id, orientation: .portrait, files: CaptureFiles(original: Data(), developed: Data([1]), thumbnail: Data([1])))
            XCTFail("Accepted empty image")
        } catch { XCTAssertEqual(error as? LibraryError, .emptyImage) }
        let rolls = try await repository.load(); XCTAssertTrue(rolls[0].frames.isEmpty)
    }

    func testCenteredPortraitAndLandscapeCrop() {
        let p = CropGeometry.rect(width: 3024, height: 4032, aspectRatio: 2.0 / 3.0)
        XCTAssertEqual(p, CGRect(x: 168, y: 0, width: 2688, height: 4032))
        let l = CropGeometry.rect(width: 4032, height: 3024, aspectRatio: 1.5)
        XCTAssertEqual(l, CGRect(x: 0, y: 168, width: 4032, height: 2688))
        XCTAssertEqual(CropGeometry.rect(width: 0, height: 1, aspectRatio: 1.5), .zero)
    }
}
