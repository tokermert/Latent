import SwiftUI
import os

@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var rolls: [FilmRoll] = []
    @Published private(set) var isLoaded = false
    @Published var errorMessage: String?
    let repository: RollRepository
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Latent", category: "library")
    /// The one roll open for capture (newest unfinished), if any.
    var activeRoll: FilmRoll? { FilmRoll.activeRoll(in: rolls) }

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Latent", isDirectory: true)
        repository = RollRepository(directory: directory)
    }

    func load() async {
        guard !isLoaded else { return }
        // Framed share images from earlier sessions are no longer referenced by any share sheet.
        ShareExports.clear()
        do { rolls = try await repository.load(); isLoaded = true; errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    /// Throws `LibraryError.activeRollExists` while a roll is open. With `finishingActive`, the open
    /// roll is finished and the new one created in one save (after the user confirms).
    func createRoll(title: String, finishingActive: Bool = false) async throws -> FilmRoll {
        rolls = try await repository.createRoll(title: title, finishingActive: finishingActive)
        return rolls[0]
    }

    func save(_ capture: ProcessedCapture, to rollID: UUID) async throws {
        rolls = try await repository.append(to: rollID, orientation: capture.orientation, files: capture.files)
    }

    func finish(_ rollID: UUID) async throws { rolls = try await repository.finish(rollID) }
    func renameRoll(_ rollID: UUID, title: String) async throws { rolls = try await repository.renameRoll(rollID, title: title) }
    func deleteRoll(_ rollID: UUID) async throws { rolls = try await repository.deleteRoll(rollID) }
    /// The deleted frame's exposure stays used; `remaining` does not grow.
    func deleteFrame(_ frameID: UUID, from rollID: UUID) async throws {
        rolls = try await repository.deleteFrame(rollID: rollID, frameID: frameID)
    }
    /// Pass nil to fall back to the first frame.
    func setCover(_ frameID: UUID?, for rollID: UUID) async throws {
        rolls = try await repository.setCover(rollID, frameID: frameID)
    }
    /// Beta counters; failures are logged only and never shown.
    func recordAlbumOpened(_ rollID: UUID) async {
        do { rolls = try await repository.recordAlbumOpened(rollID) }
        catch { log.error("Album-open counter not saved: \(error.localizedDescription, privacy: .public)") }
    }
    func recordShare(_ rollID: UUID) async {
        do { rolls = try await repository.recordShare(rollID) }
        catch { log.error("Share counter not saved: \(error.localizedDescription, privacy: .public)") }
    }
    /// Writes the anonymous roll summary (PRD §12) for the share sheet. Cleared on next launch.
    func feedbackSummaryURL() throws -> URL {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        return try FeedbackSummary(rolls: rolls, appVersion: version).write(in: ShareExports.directory())
    }
    func roll(_ id: UUID) -> FilmRoll? { rolls.first { $0.id == id } }
    func url(_ frame: FilmFrame, variant: ImageVariant = .thumbnail) -> URL {
        repository.imageURL(frameID: frame.id, variant: variant)
    }
}
