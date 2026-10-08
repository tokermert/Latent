import SwiftUI

@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var rolls: [FilmRoll] = []
    @Published private(set) var isLoaded = false
    @Published var errorMessage: String?
    let repository: RollRepository

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Latent", isDirectory: true)
        repository = RollRepository(directory: directory)
    }

    func load() async {
        guard !isLoaded else { return }
        do { rolls = try await repository.load(); isLoaded = true; errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func createRoll(title: String) async throws -> FilmRoll {
        rolls = try await repository.createRoll(title: title)
        return rolls[0]
    }

    func save(_ capture: ProcessedCapture, to rollID: UUID) async throws {
        rolls = try await repository.append(to: rollID, orientation: capture.orientation, files: capture.files)
    }

    func finish(_ rollID: UUID) async throws { rolls = try await repository.finish(rollID) }
    func roll(_ id: UUID) -> FilmRoll? { rolls.first { $0.id == id } }
    func url(_ frame: FilmFrame, variant: ImageVariant = .thumbnail) -> URL {
        repository.imageURL(frameID: frame.id, variant: variant)
    }
}
