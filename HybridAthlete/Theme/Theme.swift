import SwiftUI

/// Every visual value of the "Volt" design. Views read from here and never
/// hardcode colors, sizes or fonts.
enum Theme {
    enum Palette {
        static let background = Color(hex: 0x0B0C0E)
        static let card = Color(hex: 0x15171A)
        static let innerCard = Color(hex: 0x111316)
        static let cardBorder = Color(hex: 0x22252A)

        static let text = Color(hex: 0xF4F5F6)
        static let mutedText = Color(hex: 0x8B9096)
        static let softText = Color(hex: 0xC7CAD1)

        static let accent = Color(hex: 0xC6FF3D)
        /// Text and icons drawn on top of the accent.
        static let onAccent = Color(hex: 0x0B0C0E)
        static let accentSoft = accent.opacity(0.15)
        static let accentFaint = accent.opacity(0.07)
        static let accentLine = accent.opacity(0.33)

        /// Ratings and deltas only. Never use the accent for a rating.
        static let statusGreen = Color(hex: 0x5BE08C)
        static let statusAmber = Color(hex: 0xFFC640)
        static let statusRed = Color(hex: 0xFF6B5E)

        /// Bell-curve area outside the user's share, and its outline.
        static let curveFill = Color(hex: 0x1E2126)
        static let curveOutline = Color(hex: 0x3A3F46)
        /// Text on light pills such as the "You" marker bubble.
        static let bubble = Color(hex: 0xF4F5F6)
        /// Outline of small icon circles.
        static let iconRing = Color(hex: 0x2A2D33)
        /// Loading placeholders.
        static let skeleton = Color(hex: 0x1E2126)

        /// Home: the header circle and session thumbnails.
        static let thumbnail = Color(hex: 0x1B1E22)
        /// Home: the adherence ring's track.
        static let ringTrack = Color(hex: 0x23262B)
        /// Home: session-type icons for upcoming days.
        static let upcomingIcon = Color(hex: 0x6B7076)
        /// Sleep stages in the stage bar and its legend.
        enum StageColors {
            static let deep = accent
            static let rem = accent.opacity(0.55)
            static let core = Color(hex: 0x4A4F58)
            static let awake = Color(hex: 0xC7CAD1)
        }

        /// Deltas only (the sleep comparison). Never ratings, never the accent.
        static let deltaUp = statusGreen
        static let deltaDown = statusRed
        static let deltaNeutral = mutedText
        /// HRV and resting heart rate outcomes: better, worse, about the same.
        /// Never ratings, never the accent.
        static let outcomeBetter = statusGreen
        static let outcomeWorse = statusRed
        static let outcomeNeutral = mutedText

        /// Calendar: the dashed border of a not-recorded day.
        static let notRecordedBorder = Color(hex: 0x4A4F58)
        /// Calendar: today's cell fill.
        static let todayCell = accent.opacity(0.08)
        /// Session detail: the note text.
        static let noteText = Color(hex: 0xE4E6E8)

        /// Plan edits: a missed session's icon (with a strike).
        static let missedIcon = Color(hex: 0x6B7076)
        /// Plan edits: the "Mark as missed" action icon and the Missed chip.
        static let missedAction = mutedText
        /// Plan edits: the heads-up warning icon (amber, a soft warning, not a rating).
        static let headsUpIcon = statusAmber

        /// The floating tab bar, slightly see-through.
        static let tabBar = card.opacity(Opacity.tabBar)
    }

    enum Radius {
        static let card: CGFloat = 24
        static let largeCard: CGFloat = 26
        static let smallTile: CGFloat = 18
        static let button: CGFloat = 20
        static let logoTile: CGFloat = 20
        static let codeBlock: CGFloat = 20
        static let banner: CGFloat = 20
        static let field: CGFloat = 18
        static let skeletonLine: CGFloat = 6
        static let dayPill: CGFloat = 22
        static let thumbnail: CGFloat = 18
        static let upNext: CGFloat = 20
        static let phasePill: CGFloat = 20
        static let tabBar: CGFloat = 30
        static let tabItem: CGFloat = 24
        static let stageBar: CGFloat = 5
        static let calendarCell: CGFloat = 14
        static let squareButton: CGFloat = 16
        static let statTile: CGFloat = 20
        static let segmentCard: CGFloat = 22
        // Plan edits
        static let actionRow: CGFloat = 20
        static let editBanner: CGFloat = 18
        static let noticeBar: CGFloat = 18
        // Model Lab (DEBUG)
        static let labCard: CGFloat = 24
    }

    enum Spacing {
        static let screenSide: CGFloat = 24
        static let buttonVertical: CGFloat = 17
        static let logoToTitle: CGFloat = 20
        static let titleToSubtitle: CGFloat = 6
        static let screenTop: CGFloat = 48
        static let screenBottom: CGFloat = 32
        static let betweenBlocks: CGFloat = 24
        static let cardHorizontal: CGFloat = 20
        static let rowVertical: CGFloat = 16
        static let rowIconToLabel: CGFloat = 14
        static let cardPadding: CGFloat = 18
        static let codePadding: CGFloat = 16
        static let titleToCaption: CGFloat = 4
        static let betweenButtons: CGFloat = 12
        static let cardInner: CGFloat = 20
        static let cardStack: CGFloat = 16
        static let sectionTop: CGFloat = 12
        static let chipHorizontal: CGFloat = 10
        static let chipVertical: CGFloat = 5
        static let bubbleHorizontal: CGFloat = 10
        static let bottomBarTop: CGFloat = 14
        static let bottomBarBottom: CGFloat = 8
        static let compact: CGFloat = 8
        static let tight: CGFloat = 4
        static let connectBlocks: CGFloat = 28
        static let fieldVertical: CGFloat = 16
        static let fieldHorizontal: CGFloat = 18
        static let labelToField: CGFloat = 8
        static let formRows: CGFloat = 22
        static let dayPills: CGFloat = 6
        static let connectRowVertical: CGFloat = 14
        static let bannerVertical: CGFloat = 14
        static let bannerHorizontal: CGFloat = 16
        static let homeSide: CGFloat = 20
        static let homeBlocks: CGFloat = 28
        static let homeTop: CGFloat = 12
        static let headerGap: CGFloat = 14
        static let planCardPadding: CGFloat = 20
        static let planCardGap: CGFloat = 20
        static let pillToCaption: CGFloat = 8
        static let weekTitleToStrip: CGFloat = 14
        static let dayPillVertical: CGFloat = 12
        static let dayPillLines: CGFloat = 6
        static let selectedCardPadding: CGFloat = 14
        static let selectedCardGap: CGFloat = 14
        static let selectedToUpNext: CGFloat = 12
        static let upNextVertical: CGFloat = 12
        static let upNextHorizontal: CGFloat = 14
        static let phasePillVertical: CGFloat = 5
        static let phasePillHorizontal: CGFloat = 11
        static let statusChipVertical: CGFloat = 4
        static let statusChipHorizontal: CGFloat = 9
        static let tabBarSide: CGFloat = 16
        static let tabBarMinBottom: CGFloat = 16
        static let tabBarPadding: CGFloat = 6
        static let tabItemVertical: CGFloat = 13
        static let tabIconToLabel: CGFloat = 8
        /// Room under the scrolling content so the floating tab bar never covers it.
        static let tabBarClearance: CGFloat = 110
        static let recoveryTitleToCard: CGFloat = 14
        static let sleepCardPadding: CGFloat = 18
        static let sleepCardRows: CGFloat = 14
        static let sleepRowGap: CGFloat = 10
        static let stageGap: CGFloat = 2
        static let legendItems: CGFloat = 14
        static let legendLines: CGFloat = 8
        static let legendDotToText: CGFloat = 6
        static let recoveryCardsGap: CGFloat = 12
        static let compactCardPadding: CGFloat = 16
        static let compactCardRows: CGFloat = 14
        // Calendar and Session detail
        static let contentSide: CGFloat = 20
        static let contentTop: CGFloat = 28
        /// Room under the calendar so the floating tab bar never covers it (at least 120).
        static let calendarBottom: CGFloat = 120
        static let calendarBlocks: CGFloat = 20
        static let calendarGrid: CGFloat = 5
        /// Below `Size.narrowScreen` wide, so cells stay at least 44 pt.
        static let calendarGridNarrow: CGFloat = 4
        static let calendarCellNumberToIcon: CGFloat = 3
        static let monthButtons: CGFloat = 10
        static let legendItemsGap: CGFloat = 16
        static let legendIconToName: CGFloat = 6
        static let detailBlocks: CGFloat = 24
        static let detailBackToTitle: CGFloat = 14
        static let chipRow: CGFloat = 8
        static let detailChipHorizontal: CGFloat = 10
        static let detailChipVertical: CGFloat = 6
        static let statTiles: CGFloat = 8
        static let statTilePadding: CGFloat = 14
        static let resultPadding: CGFloat = 18
        static let segmentPadding: CGFloat = 14
        static let segmentGap: CGFloat = 12
        static let segmentCards: CGFloat = 10
        static let notePadding: CGFloat = 18
        // Plan edits
        static let actionRows: CGFloat = 8
        static let actionRowVertical: CGFloat = 12
        static let actionRowHorizontal: CGFloat = 14
        static let actionIconToText: CGFloat = 12
        static let editBannerVertical: CGFloat = 14
        static let editBannerHorizontal: CGFloat = 16
        static let noticeBarLeading: CGFloat = 16
        static let noticeBarOther: CGFloat = 8
        static let noticeLines: CGFloat = 6
        static let cancelButtonHorizontal: CGFloat = 16
        static let undoButtonHorizontal: CGFloat = 14
        // Model Lab (DEBUG)
        static let labSide: CGFloat = 20
        static let labBlocks: CGFloat = 24
        static let labCardPadding: CGFloat = 18
        static let labCardRows: CGFloat = 10
        static let labPillHorizontal: CGFloat = 16
        static let labPills: CGFloat = 8
        static let labChipHorizontal: CGFloat = 10
        static let labChipVertical: CGFloat = 5
        static let labFieldHorizontal: CGFloat = 14
        static let labGroup: CGFloat = 6
    }

    enum Size {
        static let minTouchTarget: CGFloat = 44
        /// The Lab's monthly spend bar.
        static let labCapBar: CGFloat = 6
        static let logoTile: CGFloat = 60
        static let headerIcon: CGFloat = 24
        static let borderWidth: CGFloat = 1
        static let statusIcon: CGFloat = 30
        static let statusIconGlyph: CGFloat = 13
        static let spinnerStroke: CGFloat = 3
        /// Fraction of the circle the spinner arc covers.
        static let spinnerArc: CGFloat = 0.3
        static let codeBlockMaxHeight: CGFloat = 420
        static let selectedBorderWidth: CGFloat = 1.5
        static let cardIcon: CGFloat = 34
        static let cardIconGlyph: CGFloat = 14
        static let distanceTile: CGFloat = 46
        static let planBadge: CGFloat = 52
        static let checkRing: CGFloat = 26
        static let curveHeight: CGFloat = 120
        static let curveStroke: CGFloat = 2
        static let curvePeakInset: CGFloat = 14
        /// The curve spans plus and minus this many standard deviations.
        static let curveSigmaRange: Double = 3
        /// The marker never goes further out than this many standard deviations.
        static let markerSigmaLimit: Double = 2.7
        static let markerDot: CGFloat = 10
        static let markerHalo: CGFloat = 24
        static let segmentMarker: CGFloat = 16
        static let markerDash: [CGFloat] = [3, 3]
        static let segmentHeight: CGFloat = 10
        static let segmentGap: CGFloat = 5
        static let segmentCount = 5
        static let bubbleHeight: CGFloat = 26
        static let bubbleGap: CGFloat = 8
        static let bottomBarBorder: CGFloat = 1
        static let connectRowIcon: CGFloat = 40
        static let dayPillHeight: CGFloat = 52
        static let buildingSpinner: CGFloat = 76
        static let buildingSpinnerStroke: CGFloat = 7
        static let inlineSpinner: CGFloat = 16
        static let inlineSpinnerStroke: CGFloat = 2
        static let headerAvatar: CGFloat = 46
        static let headerAvatarGlyph: CGFloat = 20
        static let ring: CGFloat = 112
        static let ringStroke: CGFloat = 10
        static let dayIcon: CGFloat = 14
        static let thumbnail: CGFloat = 60
        static let thumbnailIcon: CGFloat = 24
        static let upNextThumbnail: CGFloat = 44
        static let upNextIcon: CGFloat = 20
        static let arrowButton: CGFloat = 46
        static let arrowGlyph: CGFloat = 16
        static let tabGlyph: CGFloat = 18
        /// Session-type icons are drawn on a 16 x 16 grid with this stroke.
        static let iconGrid: CGFloat = 16
        static let iconStroke: CGFloat = 1.8
        static let iconDot: CGFloat = 1.4
        static let sleepIcon: CGFloat = 32
        static let sleepIconGlyph: CGFloat = 16
        static let trendGlyph: CGFloat = 16
        static let stageBar: CGFloat = 10
        static let minStageWidth: CGFloat = 3
        static let legendDot: CGFloat = 8
        static let sleepEmptyTile: CGFloat = 60
        /// The HRV pulse line's stroke at 16 pt.
        static let pulseStroke: CGFloat = 1.5
        // Calendar and Session detail
        static let squareButton: CGFloat = 46
        static let chevron: CGFloat = 18
        static let chevronStroke: CGFloat = 2.2
        static let calendarIcon: CGFloat = 14
        static let notRecordedBorder: CGFloat = 1.5
        static let notRecordedDash: [CGFloat] = [3, 3]
        static let raceBorder: CGFloat = 1.5
        static let selectedRing: CGFloat = 2
        static let narrowScreen: CGFloat = 380
        static let segmentNumber: CGFloat = 40
        static let chipIcon: CGFloat = 12
        // Plan edits
        static let actionCircle: CGFloat = 36
        static let actionIcon: CGFloat = 16
        static let actionIconStroke: CGFloat = 2
        /// The action icons' path grid (24 x 24).
        static let actionIconGrid: CGFloat = 24
        static let targetBorder: CGFloat = 1.5
        static let warningIcon: CGFloat = 14

        /// Loading placeholders, matching the footprint of the real content.
        enum Skeleton {
            static let vo2Number = CGSize(width: 130, height: 54)
            static let vo2Chip = CGSize(width: 104, height: 28)
            static let curveHeight: CGFloat = 130
            static let restingNumber = CGSize(width: 110, height: 54)
            static let restingChip = CGSize(width: 84, height: 28)
            static let scaleHeight: CGFloat = 12
            static let textLine: CGFloat = 14
            static let statRow: CGFloat = 50
            static let recordTimeWidth: CGFloat = 96
            static let recordTime: CGFloat = 22
            static let recordDetailWidth: CGFloat = 170
            static let planTitleWidth: CGFloat = 120
            static let planTitle: CGFloat = 18
            static let planDetailWidth: CGFloat = 150
            static let planReason: CGFloat = 28
            static let recordRows = 3
            static let planCards = 3
            static let sleepNumber = CGSize(width: 140, height: 36)
            static let sleepLineWidth: CGFloat = 120
            static let legendLine = CGSize(width: 180, height: 12)
            static let legendShortLine = CGSize(width: 130, height: 12)
            static let compactValue = CGSize(width: 80, height: 28)
            static let compactLine: CGFloat = 12
            static let compactLineWidth: CGFloat = 100
            static let compactShortLineWidth: CGFloat = 70
        }
    }

    enum Opacity {
        /// The bell-curve area left of the marker.
        static let curveAccent = 0.32
        /// Tinted chip backgrounds.
        static let chipTint = 0.15
        static let markerHalo = 0.28
        /// The locked banner: amber fill at 0x18 and border at 0x55.
        static let lockedBannerFill = 24.0 / 255
        static let lockedBannerBorder = 85.0 / 255
        static let disabledButton = 0.4
        static let skeletonLow = 0.5
        static let skeletonHigh = 1.0
        /// Placeholders hold still at this opacity when Reduce Motion is on.
        static let skeletonStill = 0.75
        static let pressedPrimary = 0.85
        static let pressedSecondary = 0.7
        static let pressedText = 0.6
        /// Status chips: the text color at this opacity behind it.
        static let statusChipFill = 0.13
        static let tabBar = 0.95
        static let disabledChevron = 0.3
        /// Calendar days before the plan or after the race.
        static let outsidePlan = 0.35
        /// Disabled month arrows.
        static let disabledMonthButton = 0.4
        /// Plan edits: disabled action rows.
        static let disabledAction = 0.4
        /// Plan edits: cells that are not a target while moving or swapping.
        static let inactiveCell = 0.35
        /// Plan edits: a valid target's fill (accent at 15%).
        static let targetFill = 0.15
    }

    enum Motion {
        static let spinnerRevolution: Double = 0.9
        static let copiedConfirmation: Duration = .seconds(1.5)
        /// One pulse of a loading placeholder, from low to high opacity.
        static let skeletonPulse: Double = 1.4
        /// Home: changing the selected day or week.
        static let selection: Double = 0.2
    }

    /// Sora for headings and big numbers, DM Sans for body text. Both are
    /// bundled variable fonts (SIL OFL 1.1, licenses next to the font files)
    /// and registered through UIAppFonts in Info.plist.
    ///
    /// Each weight is addressed by its named instance's PostScript name.
    /// `.weight()` on a custom family name does not work for these files:
    /// SwiftUI logs "Unable to update Font Descriptor's weight" and falls back
    /// to the default weight.
    enum Typography {
        enum HeadingWeight: String {
            case semibold = "Sora-Regular_SemiBold"
            case bold = "Sora-Regular_Bold"
        }

        enum BodyWeight: String {
            case regular = "DMSans-9ptRegular"
            case medium = "DMSans-9ptRegular_Medium"
            case semibold = "DMSans-9ptRegular_SemiBold"
            case bold = "DMSans-9ptRegular_Bold"
        }

        static func heading(_ size: CGFloat, weight: HeadingWeight = .semibold) -> Font {
            .custom(weight.rawValue, size: size)
        }

        static func body(_ size: CGFloat, weight: BodyWeight = .regular) -> Font {
            .custom(weight.rawValue, size: size)
        }

        static let compactScreenTitle = heading(28)
        static let blockTitle = heading(18)
        static let subtitle = body(15)
        static let rowLabel = body(15, weight: .semibold)
        static let rowValue = body(14)
        static let caption = body(13)
        static let noticeTitle = body(14, weight: .bold)
        static let noticeBody = body(14)
        static let secondaryButton = body(15, weight: .semibold)
        static let textButton = body(14, weight: .semibold)
        static let statusGlyph = Font.system(size: Size.statusIconGlyph, weight: .bold)
        static let fieldText = body(16)
        static let dayLetter = body(15, weight: .bold)
        static let fieldIssue = body(13, weight: .medium)
        static let headerGlyph = Font.system(size: Size.headerIcon, weight: .semibold)
        static let caption12 = body(12)
        static let cardTitle = body(14, weight: .medium)
        static let bigValue = heading(54)
        static let unit = body(15)
        static let sectionTitle = heading(20)
        static let recordTime = heading(20)
        static let planTitle = heading(17)
        static let badge = heading(15, weight: .bold)
        static let chip = body(12, weight: .bold)
        static let bubble = body(13, weight: .bold)
        static let axisLabel = body(11)
        static let statLabel = body(14)
        static let statValue = heading(17)
        static let cardIconGlyph = Font.system(size: Size.cardIconGlyph, weight: .semibold)
        /// System monospaced, for raw data.
        static let code = Font.system(size: 12, design: .monospaced)
        static let fieldLabel = body(13, weight: .semibold)
        static let primaryButton = body(16, weight: .bold)
        static let placeholderScreen = body(17, weight: .medium)

        // Home
        static let homeDate = body(13)
        static let greeting = heading(22)
        static let ringValue = heading(24)
        static let ringCaption = body(12)
        static let raceTitle = body(13)
        static let countdown = heading(46)
        static let countdownWords = heading(28)
        static let countdownUnit = body(14)
        static let phasePill = body(11, weight: .bold)
        /// 0.05 em at 11 pt.
        static let phasePillTracking: CGFloat = 0.55
        static let weekCaption = body(12)
        static let weekTitle = heading(18)
        static let weekRange = body(13)
        static let dayWeekday = body(12, weight: .medium)
        static let dayNumber = heading(18)
        static let sessionName = heading(16)
        static let sessionMeta = body(13)
        static let statusChip = body(11, weight: .bold)
        static let upNextCaption = body(12)
        static let upNextName = heading(15)
        static let upNextMeta = body(12)
        static let lockedLine = body(12)
        static let tabLabel = body(15, weight: .semibold)
        static let headerAvatarGlyph = Font.system(size: Size.headerAvatarGlyph, weight: .semibold)
        static let arrowGlyph = Font.system(size: Size.arrowGlyph, weight: .semibold)
        static let tabGlyph = Font.system(size: Size.tabGlyph, weight: .semibold)
        static let thumbnailGlyph = Font.system(size: Size.thumbnailIcon, weight: .semibold)
        static let dayGlyph = Font.system(size: Size.dayIcon, weight: .semibold)

        // Recovery: Sleep card
        static let recoveryTitle = heading(18)
        static let recoveryUpdated = body(13)
        static let sleepLabel = body(14)
        static let sleepNightLabel = body(13)
        static let sleepDuration = heading(36)
        static let sleepWindow = body(13)
        static let sleepDelta = body(14, weight: .bold)
        static let sleepCaption = body(12)
        static let legendName = body(12)
        static let legendValue = body(12)
        static let stageNote = body(11)
        static let sleepNote = body(12)
        static let sleepEmptyTitle = heading(16)
        static let sleepEmptyText = body(13)
        static let sleepIconGlyph = Font.system(size: Size.sleepIconGlyph, weight: .regular)
        static let trendGlyph = Font.system(size: Size.trendGlyph, weight: .semibold)

        // Recovery: section notices and the compact HRV and resting HR cards
        static let recoveryNotice = body(12)
        static let compactTitle = body(14)
        static let compactValue = heading(28)
        static let compactUnit = body(13)
        static let compactLabel = body(12)
        static let compactDelta = body(14, weight: .bold)
        static let compactCaption = body(12)
        static let compactEmptyTitle = body(13, weight: .semibold)
        static let compactEmptyText = body(12)

        // Calendar
        static let calendarCaption = body(13)
        static let monthTitle = heading(24)
        static let weekdayLetter = body(12, weight: .semibold)
        static let calendarDate = heading(13)
        static let calendarGlyph = Font.system(size: Size.calendarIcon, weight: .semibold)
        static let legendLabel = body(12)

        // Session detail
        static let detailCaption = body(13)
        static let detailDate = body(15, weight: .semibold)
        static let detailTitle = heading(28)
        static let detailTitleLineSpacing: CGFloat = 28 * 0.15
        static let typeChip = body(12, weight: .semibold)
        static let weekPhaseLine = body(13)
        static let tileLabel = body(12)
        static let tileValue = heading(19)
        static let tileEffort = heading(15)
        static let resultCaption = body(12, weight: .bold)
        /// 0.05 em at 12 pt.
        static let captionTracking: CGFloat = 0.6
        static let resultValue = heading(18)
        static let resultLine = body(13)
        static let resultEmptyTitle = heading(16)
        static let structureTitle = heading(18)
        static let segmentNumber = heading(15, weight: .bold)
        static let segmentLabel = heading(15)
        static let segmentDetail = body(13)
        static let segmentDetailLineSpacing: CGFloat = 13 * 0.4
        static let segmentChip = body(12, weight: .bold)
        static let noteCaption = body(12, weight: .bold)
        static let noteText = body(15)
        static let noteLineSpacing: CGFloat = 15 * 0.55
        // Plan edits
        static let actionLabel = body(14, weight: .bold)
        static let actionHint = body(12)
        static let bannerTitle = body(12, weight: .bold)
        static let bannerText = body(14)
        static let editButton = body(14, weight: .bold)
        static let noticeText = body(13)
        static let headsUpText = body(13)
        static let movedChip = body(11, weight: .bold)
        // Model Lab (DEBUG)
        static let labTitle = heading(24)
        static let labSection = body(13, weight: .semibold)
        static let labPill = body(14, weight: .semibold)
        static let labChip = body(12, weight: .bold)
        static let labBody = body(14)
        static let labMeta = body(12)
        static let labNoteHeadline = heading(16)
        static let labPrompt = Font.system(size: 12, design: .monospaced)
        static let labCostTotal = heading(34)
        static let labRowValue = body(14, weight: .semibold)
        static let labField = body(16)
    }
}

extension Color {
    /// Builds an opaque color from a 0xRRGGBB literal.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
