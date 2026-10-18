import SwiftUI
import Domain
import Application

/// The main app once a plan exists: Home and Calendar behind a floating pill tab
/// bar, inside one NavigationStack. Session detail is pushed over either tab and
/// hides the tab bar; Back returns to the same tab with its state intact.
struct MainTabView: View {
    let screens: MainScreens
    @State private var tab: MainScreens.Tab
    @State private var path: [SessionDetailRoute] = []

    init(screens: MainScreens) {
        self.screens = screens
        _tab = State(initialValue: screens.startTab)
    }

    var body: some View {
        GeometryReader { proxy in
            content(bottomInset: proxy.safeAreaInsets.bottom)
        }
    }

    /// The bar sits max(16, safe area) above the bottom edge.
    private func content(bottomInset: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            NavigationStack(path: $path) {
                Group {
                    switch tab {
                    case .home:
                        HomeView(viewModel: screens.home, onOpenSession: open)
                    case .calendar:
                        CalendarView(viewModel: screens.calendar, onOpenSession: open)
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: SessionDetailRoute.self) { route in
                    if StrengthSession.isStrengthId(route.sessionId), let make = screens.makeStrengthDetail {
                        StrengthDetailView(viewModel: make(route.sessionId)) {
                            if !path.isEmpty { path.removeLast() }
                        }
                    } else {
                        SessionDetailView(viewModel: screens.makeSessionDetail(route.sessionId)) {
                            if !path.isEmpty { path.removeLast() }
                        }
                    }
                }
            }
            if path.isEmpty {
                FloatingTabBar(selection: $tab)
                    .padding(.bottom, max(Theme.Spacing.tabBarMinBottom, bottomInset))
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .sheet(item: Binding(get: { screens.feedback?.current }, set: { _ in })) { prompt in
            if let feedback = screens.feedback {
                FeedbackSheetView(
                    prompt: prompt,
                    existing: feedback.editing,
                    onSubmit: { status, areas, note in Task { await feedback.submit(status: status, areas: areas, note: note) } },
                    onSkip: { Task { await feedback.skip() } }
                )
            }
        }
    }

    private func open(_ sessionId: String) {
        path.append(SessionDetailRoute(sessionId: sessionId))
    }
}

/// Pushes the session detail; the id is the session's "YYYY-MM-DD".
struct SessionDetailRoute: Hashable {
    let sessionId: String
}

private struct FloatingTabBar: View {
    @Binding var selection: MainScreens.Tab

    var body: some View {
        HStack(spacing: 0) {
            item(.home, title: "Home", symbol: "house", identifier: "tab.home")
            item(.calendar, title: "Calendar", symbol: "calendar", identifier: "tab.calendar")
        }
        .padding(Theme.Spacing.tabBarPadding)
        .background(Theme.Palette.tabBar, in: RoundedRectangle(cornerRadius: Theme.Radius.tabBar, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.tabBar, style: .continuous)
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
        }
        .padding(.horizontal, Theme.Spacing.tabBarSide)
    }

    private func item(_ tab: MainScreens.Tab, title: String, symbol: String, identifier: String) -> some View {
        let isActive = selection == tab
        return Button {
            selection = tab
        } label: {
            HStack(spacing: Theme.Spacing.tabIconToLabel) {
                Image(systemName: symbol).font(Theme.Typography.tabGlyph)
                Text(title).font(Theme.Typography.tabLabel)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(isActive ? Theme.Palette.onAccent : Theme.Palette.mutedText)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.minTouchTarget)
            .padding(.vertical, Theme.Spacing.tabItemVertical)
            .background(
                isActive ? Theme.Palette.accent : Color.clear,
                in: RoundedRectangle(cornerRadius: Theme.Radius.tabItem, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tabItem, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
