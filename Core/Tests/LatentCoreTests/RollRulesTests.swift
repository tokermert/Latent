import XCTest
@testable import LatentCore

final class RollRulesTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LatentTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private var files: CaptureFiles {
        CaptureFiles(original: Data([1, 2, 3]), developed: Data([4, 5]), thumbnail: Data([6]))
    }
    private func manifest(_ dir: URL) -> URL { dir.appendingPathComponent("library.json") }

    // MARK: Single active roll

    func testSecondRollIsBlockedWhileOneIsOpen() async throws {
        let dir = try directory(); let repository = RollRepository(directory: dir); _ = try await repository.load()
        let first = try await repository.createRoll(title: "London")[0]
        let before = try Data(contentsOf: manifest(dir))
        do { _ = try await repository.createRoll(title: "Paris"); XCTFail("Opened a second roll") }
        catch { XCTAssertEqual(error as? LibraryError, .activeRollExists) }
        XCTAssertEqual(try Data(contentsOf: manifest(dir)), before)
        let active = await repository.activeRoll()
        XCTAssertEqual(active?.id, first.id)
        _ = try await repository.finish(first.id)
        let rolls = try await repository.createRoll(title: "Paris")
        XCTAssertEqual(rolls.map(\.title), ["Paris", "London"])
        XCTAssertEqual(FilmRoll.activeRoll(in: rolls)?.title, "Paris")
    }

    func testFinishingActiveClosesOldRollAndCreatesNewOneTogether() async throws {
        let dir = try directory(); let repository = RollRepository(directory: dir); _ = try await repository.load()
        let old = try await repository.createRoll(title: "London")[0].id
        _ = try await repository.append(to: old, orientation: .portrait, files: files)
        let rolls = try await repository.createRoll(title: "Paris", finishingActive: true)
        XCTAssertEqual(rolls.count, 2)
        XCTAssertEqual(rolls[0].title, "Paris"); XCTAssertFalse(rolls[0].isFinished)
        XCTAssertTrue(rolls[1].isFinished); XCTAssertEqual(rolls[1].frames.count, 1)
        let reloaded = try await RollRepository(directory: dir).load()
        XCTAssertEqual(reloaded, rolls)
    }

    func testFailedFinishingActiveCommitChangesNothing() async throws {
        let dir = try directory(); let repository = RollRepository(directory: dir); _ = try await repository.load()
        let old = try await repository.createRoll(title: "London")[0].id
        try FileManager.default.removeItem(at: manifest(dir))
        try FileManager.default.createDirectory(at: manifest(dir), withIntermediateDirectories: false)
        do { _ = try await repository.createRoll(title: "Paris", finishingActive: true); XCTFail("Expected disk failure") } catch { }
        let active = await repository.activeRoll()
        XCTAssertEqual(active?.id, old, "Failed commit finished the old roll in memory")
    }

    func testFinishingActiveWithoutOpenRollJustCreates() async throws {
        let repository = RollRepository(directory: try directory()); _ = try await repository.load()
        let rolls = try await repository.createRoll(title: "London", finishingActive: true)
        XCTAssertEqual(rolls.count, 1); XCTAssertFalse(rolls[0].isFinished)
    }

    func testLegacyArchiveWithSeveralOpenRollsIsLeftAlone() async throws {
        let dir = try directory()
        let older = UUID(), newer = UUID()
        func roll(_ id: UUID, _ created: Int) -> String {
            #"{"id":"\#(id.uuidString)","title":"R","createdAt":\#(created),"film":"LATENT COLOR 400","frames":[],"exposuresUsed":0}"#
        }
        let bytes = Data(#"{"version":2,"rolls":[\#(roll(older, 0)),\#(roll(newer, 100))]}"#.utf8)
        try bytes.write(to: manifest(dir))
        let repository = RollRepository(directory: dir)
        let rolls = try await repository.load()
        XCTAssertTrue(rolls.allSatisfy { !$0.isFinished }, "Load finished a roll on its own")
        XCTAssertEqual(FilmRoll.activeRoll(in: rolls)?.id, newer)
        do { _ = try await repository.createRoll(title: "New"); XCTFail("Opened another roll") }
        catch { XCTAssertEqual(error as? LibraryError, .activeRollExists) }
        XCTAssertEqual(try Data(contentsOf: manifest(dir)), bytes)
    }

    // MARK: Counters and manifest v3

    func testAlbumAndShareCountersPersist() async throws {
        let dir = try directory(); let repository = RollRepository(directory: dir); _ = try await repository.load()
        let id = try await repository.createRoll(title: "London")[0].id
        _ = try await repository.recordAlbumOpened(id)
        _ = try await repository.recordAlbumOpened(id)
        let rolls = try await repository.recordShare(id)
        XCTAssertEqual(rolls[0].albumOpenCount, 2); XCTAssertEqual(rolls[0].shareCount, 1)
        let reloaded = try await RollRepository(directory: dir).load()
        XCTAssertEqual(reloaded, rolls)
        do { _ = try await repository.recordShare(UUID()); XCTFail("Counted a missing roll") }
        catch { XCTAssertEqual(error as? LibraryError, .missingRoll) }
    }

    func testVersion2ManifestMigratesToVersion3WithoutLoss() async throws {
        let dir = try directory()
        let rollID = UUID(), frameIDs = [UUID(), UUID()]
        let frames = zip(frameIDs, [1, 3]).map { #"{"id":"\#($0.uuidString)","number":\#($1),"capturedAt":5,"orientation":"landscape"}"# }.joined(separator: ",")
        let v2 = #"{"version":2,"rolls":[{"id":"\#(rollID.uuidString)","title":"London","createdAt":0,"film":"LATENT COLOR 400","frames":[\#(frames)],"exposuresUsed":3,"coverFrameID":"\#(frameIDs[1].uuidString)","finishedAt":9}]}"#
        try Data(v2.utf8).write(to: manifest(dir))
        let repository = RollRepository(directory: dir)
        let rolls = try await repository.load()
        XCTAssertEqual(rolls[0].frames.map(\.id), frameIDs)
        XCTAssertEqual(rolls[0].frames.map(\.number), [1, 3])
        XCTAssertEqual(rolls[0].exposuresUsed, 3); XCTAssertEqual(rolls[0].coverFrameID, frameIDs[1])
        XCTAssertEqual(rolls[0].albumOpenCount, 0); XCTAssertEqual(rolls[0].shareCount, 0)
        let counted = try await repository.recordAlbumOpened(rollID)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest(dir))) as? [String: Any]
        XCTAssertEqual(object?["version"] as? Int, 3)
        let reloaded = try await RollRepository(directory: dir).load()
        XCTAssertEqual(reloaded, counted)
    }

    // MARK: Feedback summary

    func testFeedbackSummaryCountsAndPrivacy() async throws {
        let repository = RollRepository(directory: try directory()); _ = try await repository.load()
        let secret = "Gizli Gezi Adı"
        let early = try await repository.createRoll(title: secret)[0].id
        _ = try await repository.append(to: early, orientation: .portrait, files: files)
        _ = try await repository.append(to: early, orientation: .landscape, files: files)
        var rolls = try await repository.append(to: early, orientation: .portrait, files: files)
        rolls = try await repository.deleteFrame(rollID: early, frameID: rolls[0].frames[1].id)
        _ = try await repository.recordAlbumOpened(early)
        _ = try await repository.recordShare(early)
        let full = try await repository.createRoll(title: secret + " 2", finishingActive: true)[0].id
        for _ in 0..<36 { _ = try await repository.append(to: full, orientation: .landscape, files: files) }
        rolls = try await repository.createRoll(title: secret + " 3")

        let summary = FeedbackSummary(rolls: rolls, appVersion: "0.1.0 (1)")
        XCTAssertEqual(summary.rollCount, 3)
        XCTAssertEqual(summary.rolls.map(\.index), [1, 2, 3])
        XCTAssertEqual(summary.rolls.map(\.finishKind), [.early, .full, .inProgress])
        let first = summary.rolls[0]
        XCTAssertEqual(first.exposuresUsed, 3); XCTAssertEqual(first.remaining, 33); XCTAssertEqual(first.deletedFrames, 1)
        XCTAssertEqual(first.frames.map(\.number), [1, 3])
        XCTAssertEqual(first.orientations, FeedbackSummary.Orientations(portrait: 2, landscape: 0))
        XCTAssertEqual(first.albumOpenCount, 1); XCTAssertEqual(first.shareCount, 1)
        XCTAssertNotNil(first.finishedAt)
        XCTAssertEqual(summary.rolls[1].frames.count, 36); XCTAssertEqual(summary.rolls[1].remaining, 0)
        XCTAssertNil(summary.rolls[2].finishedAt)

        let json = String(decoding: try summary.jsonData(), as: UTF8.self)
        XCTAssertFalse(json.contains("Gizli"), "Roll title leaked")
        for roll in rolls {
            XCTAssertFalse(json.contains(roll.id.uuidString), "Roll id leaked")
            for frame in roll.frames { XCTAssertFalse(json.contains(frame.id.uuidString), "Frame id leaked") }
        }
        XCTAssertFalse(json.contains(".jpg")); XCTAssertFalse(json.contains("/"))
        XCTAssertTrue(json.contains("\"schemaVersion\" : 1"))
    }

    func testFeedbackSummaryFileRoundTrips() throws {
        let dir = try directory()
        let generated = Date(timeIntervalSince1970: 1_791_460_800) // 2026-10-08T12:00:00Z
        let summary = FeedbackSummary(rolls: [FilmRoll(title: "X")], appVersion: "0.1.0 (1)", generatedAt: generated)
        let url = try summary.write(in: dir)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("latent-ozet-2026-10-"))
        XCTAssertEqual(url.pathExtension, "json")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FeedbackSummary.self, from: Data(contentsOf: url))
        XCTAssertEqual(decoded.rollCount, 1); XCTAssertEqual(decoded.rolls[0].finishKind, .inProgress)
        XCTAssertEqual(decoded.generatedAt, generated)
    }

    // MARK: Film stock

    func testFilmStockLookup() {
        XCTAssertEqual(FilmStock.all.map(\.id), ["color400", "gold200", "slide100", "mono400"])
        XCTAssertEqual(Set(FilmStock.all.map(\.name)).count, FilmStock.all.count)
        XCTAssertEqual(FilmStock.default, .color400)
        XCTAssertEqual(FilmStock.stock(id: "mono400"), .mono400)
        XCTAssertNil(FilmStock.stock(id: "nope"))
        XCTAssertEqual(FilmStock.stock(named: "LATENT GOLD 200"), .gold200)
        XCTAssertEqual(FilmStock.stock(named: "LATENT COLOR 400"), .color400)
        XCTAssertEqual(FilmStock.stock(named: "SOMETHING ELSE 800"), .default)
        XCTAssertEqual(FilmRoll(title: "X").stock, .color400)
        XCTAssertTrue(FilmStock.mono400.isMonochrome)
        XCTAssertTrue(FilmStock.all.filter { $0 != .mono400 }.allSatisfy { !$0.isMonochrome })
    }

    func testLegacyManifestFilmResolvesToDefaultStock() async throws {
        let dir = try directory()
        let legacy = Data(#"{"version":2,"rolls":[{"id":"\#(UUID().uuidString)","title":"A","createdAt":0,"film":"LATENT COLOR 400","frames":[],"exposuresUsed":0},{"id":"\#(UUID().uuidString)","title":"B","createdAt":50,"film":"OLD FILM","frames":[],"exposuresUsed":36}]}"#.utf8)
        try legacy.write(to: manifest(dir))
        let rolls = try await RollRepository(directory: dir).load()
        XCTAssertEqual(rolls.map(\.stock), [.color400, .color400])
        XCTAssertEqual(rolls[1].film, "OLD FILM", "Stored name must not be rewritten")
    }

    func testNewRollKeepsChosenStockAcrossRelaunch() async throws {
        let dir = try directory(); let repository = RollRepository(directory: dir); _ = try await repository.load()
        let roll = try await repository.createRoll(title: "Lizbon", stock: .slide100)[0]
        XCTAssertEqual(roll.stock, .slide100); XCTAssertEqual(roll.film, "LATENT SLIDE 100")
        _ = try await repository.append(to: roll.id, orientation: .portrait, files: files)
        let reopened = try await RollRepository(directory: dir).load()
        XCTAssertEqual(reopened[0].stock, .slide100)
        let next = try await repository.createRoll(title: "Roma", stock: .mono400, finishingActive: true)
        XCTAssertEqual(next.map(\.stock), [.mono400, .slide100])
        let plain = try await RollRepository(directory: try directory())
        _ = try await plain.load()
        let defaulted = try await plain.createRoll(title: "Varsayılan")[0]
        XCTAssertEqual(defaulted.stock, .default)
    }
}
