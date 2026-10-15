import SwiftUI

/// Shows the launch route, then whatever the user navigates to.
struct RootView: View {
    let viewModel: RootViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .preferredColorScheme(.dark)
            .task { await viewModel.start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await viewModel.appBecameActive() }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.route {
        case .connectHealth:
            if let connectHealth = viewModel.connectHealth {
                ConnectHealthView(viewModel: connectHealth)
            }
        case .startingPoint:
            if let startingPoint = viewModel.startingPoint {
                StartingPointView(viewModel: startingPoint)
                    .id(ObjectIdentifier(startingPoint))
            }
        case .raceSetup:
            if let raceSetup = viewModel.raceSetup {
                RaceSetupView(viewModel: raceSetup)
            }
        case .generating:
            if let generating = viewModel.generating {
                GeneratingView(viewModel: generating)
                    .id(ObjectIdentifier(generating))
            }
        case .home:
            if let home = viewModel.home {
                MainTabView(screens: home)
                    .id(ObjectIdentifier(home))
            }
        case nil:
            Theme.Palette.background.ignoresSafeArea()
        }
    }
}
