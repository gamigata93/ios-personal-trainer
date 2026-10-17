import Foundation
import Domain
import Application

/// The main app's view models, built once per plan by the composition root and
/// sharing one `ActivePlanStore` and one `CompletedRunsStore`, so Home, Calendar
/// and Session detail always agree.
@MainActor
final class MainScreens {
    enum Tab: Hashable {
        case home, calendar
    }

    let plans: ActivePlanStore
    let runs: CompletedRunsStore
    let home: HomeViewModel
    let calendar: CalendarViewModel
    /// The shared coach notes; nil in tests that do not need them.
    let notes: CoachNoteStore?
    /// DEBUG `-startTab`; Home otherwise.
    let startTab: Tab
    private let makeSessionDetailViewModel: @MainActor (String) -> SessionDetailViewModel

    init(
        plans: ActivePlanStore,
        runs: CompletedRunsStore,
        home: HomeViewModel,
        calendar: CalendarViewModel,
        startTab: Tab = .home,
        notes: CoachNoteStore? = nil,
        makeSessionDetail: @escaping @MainActor (String) -> SessionDetailViewModel
    ) {
        self.notes = notes
        self.plans = plans
        self.runs = runs
        self.home = home
        self.calendar = calendar
        self.startTab = startTab
        self.makeSessionDetailViewModel = makeSessionDetail
    }

    func makeSessionDetail(_ sessionId: String) -> SessionDetailViewModel {
        makeSessionDetailViewModel(sessionId)
    }

    /// Back in the foreground: Home's refresh also refreshes the shared runs for Calendar.
    func refreshIfStale() async {
        await home.refreshIfStale()
    }
}
