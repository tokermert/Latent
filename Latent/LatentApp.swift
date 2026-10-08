import SwiftUI

@main
struct LatentApp: App {
    @StateObject private var library = LibraryModel()
    var body: some Scene {
        WindowGroup {
            ArchiveView()
                .environmentObject(library)
                .preferredColorScheme(.light)
                .tint(LatentTheme.orange)
                .task { await library.load() }
        }
    }
}
