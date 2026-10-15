import SwiftUI

@main
struct HybridAthleteApp: App {
    @State private var root = CompositionRoot.makeRootViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: root)
        }
    }
}
