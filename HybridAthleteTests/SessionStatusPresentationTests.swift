import SwiftUI
import Testing
import Domain
@testable import HybridAthlete

struct SessionStatusPresentationTests {
    private typealias Look = SessionStatusPresentation

    @Test func completedTokenIsPeriwinkle() {
        #expect(Theme.Palette.completed == Color(hex: 0x7C9CFF))
        #expect(Theme.Palette.completedSoft == Color(hex: 0x7C9CFF).opacity(0.15))
    }

    @Test func completed() {
        let look = Look.presentation(.completed)
        #expect(look.iconColor == Color(hex: 0x7C9CFF))
        #expect(look.iconDecoration == .none)
        #expect(look.cellBorder == .solid)
        #expect(look.showsCheckBadge)
        #expect(look.chipText == "Completed")
        #expect(look.chipColor == Color(hex: 0x7C9CFF))
        #expect(look.chipFill == Color(hex: 0x7C9CFF).opacity(0.15))
    }

    @Test func today() {
        let look = Look.presentation(.today)
        #expect(look.iconColor == Color(hex: 0xC6FF3D))
        #expect(look.iconDecoration == .none)
        #expect(look.cellBorder == .solid)
        #expect(!look.showsCheckBadge)
        #expect(look.chipText == "Today")
        #expect(look.chipColor == Color(hex: 0xF4F5F6))
        #expect(look.chipFill == Color(hex: 0xF4F5F6).opacity(0.13))
    }

    @Test func upcoming() {
        let look = Look.presentation(.upcoming)
        #expect(look.iconColor == Color(hex: 0x6B7076))
        #expect(look.iconDecoration == .none)
        #expect(look.cellBorder == .solid)
        #expect(!look.showsCheckBadge)
        #expect(look.chipText == "Upcoming")
        #expect(look.chipColor == Color(hex: 0xC7CAD1))
    }

    @Test func notRecorded() {
        let look = Look.presentation(.notRecorded)
        #expect(look.iconColor == Color(hex: 0x8B9096))
        #expect(look.iconDecoration == .none)
        #expect(look.cellBorder == .dashed)
        #expect(!look.showsCheckBadge)
        #expect(look.chipText == "Not recorded")
        #expect(look.chipColor == Color(hex: 0xC7CAD1))
    }

    @Test func missed() {
        let look = Look.presentation(.missed)
        #expect(look.iconColor == Color(hex: 0x6B7076))
        #expect(look.iconDecoration == .strike)
        #expect(look.cellBorder == .solid)
        #expect(!look.showsCheckBadge)
        #expect(look.chipText == "Missed")
        #expect(look.chipColor == Color(hex: 0x8B9096))
    }

    @Test(arguments: [(Rating.green, 0x5BE08C), (.amber, 0xFFC640), (.red, 0xFF6B5E)] as [(Rating, UInt32)])
    func aRatingRecolorsOnlyTheCompletedIcon(rating: Rating, hex: UInt32) {
        let look = Look.presentation(.completed, rating: rating)
        #expect(look.iconColor == Color(hex: hex))
        #expect(look.showsCheckBadge)
        #expect(look.chipColor == Color(hex: 0x7C9CFF))
    }

    @Test(arguments: [SessionStatus.today, .upcoming, .notRecorded, .missed])
    func otherStatusesIgnoreTheRating(status: SessionStatus) {
        for rating in Rating.allCases {
            #expect(Look.presentation(status, rating: rating) == Look.presentation(status))
        }
    }

    // MARK: Labels

    @Test(arguments: [
        (SessionStatus.completed, "Monday 12 October, Tempo run, completed"),
        (.notRecorded, "Monday 12 October, Tempo run, not recorded"),
        (.missed, "Monday 12 October, Tempo run, missed"),
        (.today, "Monday 12 October, Tempo run, today"),
        (.upcoming, "Monday 12 October, Tempo run, upcoming"),
    ])
    func cellLabelEndsWithTheStatusWord(status: SessionStatus, label: String) {
        let text = HomeFormat.dayAccessibilityLabel(
            date: LocalDate(year: 2026, month: 10, day: 12), sessionName: "Tempo run", isRaceDay: false, status: status, isToday: status == .today
        )
        #expect(text == label)
    }

    @Test func restDayLabel() {
        let text = HomeFormat.dayAccessibilityLabel(
            date: LocalDate(year: 2026, month: 10, day: 13), sessionName: nil, isRaceDay: false, status: nil, isToday: false
        )
        #expect(text == "Tuesday 13 October, Rest day")
    }

    @Test func legendIsOneSpokenSentence() {
        #expect(CalendarLegend.accessibilityText == "Legend. Types: easy circle, tempo arrow, threshold plateau, intervals zigzag, long run bar, strength dumbbell. "
            + "Status: completed is blue with a check, today is lime, upcoming is gray, not recorded has a dashed border, missed is struck through.")
    }
}
