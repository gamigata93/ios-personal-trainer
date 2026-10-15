/// The top-level screen the app shows.
enum AppRoute: Equatable {
    /// First launch only: Health access has never been requested.
    case connectHealth
    /// Onboarding: the dashboard and plan suggestions, loading in the background.
    case startingPoint
    case raceSetup
    /// The plan is being built.
    case generating
    /// The main app: Home and Calendar.
    case home
}
