import SwiftUI
import Domain
import Application

/// The Calendar tab: the month grid, the selected day's card with its edit
/// actions (move, swap, mark missed), the edit banner and notice, and a legend of
/// the session-type icons. Every value comes from the view model's
/// `CalendarMonthOverview`; this file only lays it out.
struct CalendarView: View {
    let viewModel: CalendarViewModel
    let onOpenSession: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gridWidth: CGFloat = 0

    var body: some View {
        ScrollView {
            if let month = viewModel.overview {
                VStack(alignment: .leading, spacing: Theme.Spacing.calendarBlocks) {
                    header(month)
                    if let banner = month.banner {
                        EditBannerView(banner: banner) { change { viewModel.cancelEdit() } }
                    }
                    if let locked = month.lockedLine {
                        Text(locked)
                            .font(Theme.Typography.lockedLine)
                            .foregroundStyle(Theme.Palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("calendar.locked")
                    }
                    grid(month)
                    if let failure = viewModel.failureText {
                        NoticeBar(text: failure, headsUp: nil, buttonTitle: "Dismiss", buttonIdentifier: "failureDismiss", identifier: "editFailure") {
                            viewModel.dismissFailure()
                        }
                    } else if let notice = viewModel.notice {
                        NoticeBar(text: notice.text, headsUp: notice.headsUp, buttonTitle: "Undo", buttonIdentifier: "noticeUndo", identifier: "noticeBar") {
                            Task { await viewModel.undo() }
                        }
                    }
                    if let card = month.dayCard {
                        DayCardView(card: card, onOpenSession: onOpenSession)
                    }
                    if !month.actions.isEmpty {
                        VStack(spacing: Theme.Spacing.actionRows) {
                            ForEach(month.actions, id: \.label) { action in
                                ActionRow(action: action) { Task { await viewModel.perform(action) } }
                            }
                        }
                    }
                    CalendarLegend()
                }
                .padding(.horizontal, Theme.Spacing.contentSide)
                .padding(.top, Theme.Spacing.contentTop)
                .padding(.bottom, Theme.Spacing.calendarBottom)
            }
        }
        .refreshable { await viewModel.refresh() }
        .background(Theme.Palette.background.ignoresSafeArea())
        .task { await viewModel.appear() }
        .onDisappear { viewModel.leave() }
        .onChange(of: viewModel.overview?.banner) { _, banner in
            if let banner { AccessibilityNotification.Announcement(banner.text).post() }
        }
        .onChange(of: viewModel.notice) { _, notice in
            if let notice { AccessibilityNotification.Announcement([notice.text, notice.headsUp].compactMap { $0 }.joined(separator: " ")).post() }
        }
    }

    // MARK: Header

    private func header(_ month: CalendarMonthOverview) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.monthButtons) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight / 2) {
                Text("Training calendar")
                    .font(Theme.Typography.calendarCaption)
                    .foregroundStyle(Theme.Palette.mutedText)
                Text(month.title)
                    .font(Theme.Typography.monthTitle)
                    .foregroundStyle(Theme.Palette.text)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("calendar.monthTitle")
            }
            Spacer(minLength: Theme.Spacing.compact)
            SquareChevronButton(direction: .left, label: "Previous month", identifier: "monthPrev", isEnabled: month.canGoBack) {
                change { viewModel.showPreviousMonth() }
            }
            SquareChevronButton(direction: .right, label: "Next month", identifier: "monthNext", isEnabled: month.canGoForward) {
                change { viewModel.showNextMonth() }
            }
        }
    }

    // MARK: Grid

    private func grid(_ month: CalendarMonthOverview) -> some View {
        let gap = gridWidth > 0 && gridWidth < Theme.Size.narrowScreen - 2 * Theme.Spacing.contentSide
            ? Theme.Spacing.calendarGridNarrow
            : Theme.Spacing.calendarGrid
        let columns = Array(repeating: GridItem(.flexible(), spacing: gap), count: 7)
        return VStack(spacing: gap) {
            LazyVGrid(columns: columns, spacing: gap) {
                ForEach(Array(month.weekdayLabels.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(Theme.Typography.weekdayLetter)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                ForEach(0..<month.leadingBlanks, id: \.self) { index in
                    Color.clear.aspectRatio(1, contentMode: .fit).id("lead-\(index)")
                }
                ForEach(month.cells) { cell in
                    CalendarCellView(cell: cell) {
                        if viewModel.mode == nil {
                            change { viewModel.select(cell.date) }
                        } else {
                            Task { await viewModel.tap(cell.date) }
                        }
                    }
                }
                ForEach(0..<month.trailingBlanks, id: \.self) { index in
                    Color.clear.aspectRatio(1, contentMode: .fit).id("trail-\(index)")
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendarGrid")
    }

    private func change(_ update: () -> Void) {
        if reduceMotion {
            update()
        } else {
            withAnimation(.easeOut(duration: Theme.Motion.selection)) { update() }
        }
    }
}

/// One day: the date over its session-type icon (or the race flag).
private struct CalendarCellView: View {
    let cell: CalendarMonthOverview.Cell
    let onTap: () -> Void

    private var hasSession: Bool { cell.sessionType != nil || cell.isRaceDay }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.calendarCell, style: .continuous) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Theme.Spacing.calendarCellNumberToIcon) {
                Text(cell.dayNumber)
                    .font(Theme.Typography.calendarDate)
                    .foregroundStyle(cell.isToday && cell.isSelectable ? Theme.Palette.accent : Theme.Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                icon.frame(width: Theme.Size.calendarIcon, height: Theme.Size.calendarIcon)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(fill, in: shape)
            .overlay { border }
            .overlay {
                if cell.isSelected {
                    shape.strokeBorder(Theme.Palette.accent, lineWidth: Theme.Size.selectedRing)
                } else if cell.editRole == .target {
                    shape.strokeBorder(Theme.Palette.accent, lineWidth: Theme.Size.targetBorder)
                }
            }
            .contentShape(shape)
            .opacity(opacity)
        }
        .buttonStyle(.plain)
        .disabled(!isTappable)
        .accessibilityLabel(cell.accessibilityLabel + (cell.isSelected ? ", selected" : ""))
        .accessibilityAddTraits(cell.isSelected ? .isSelected : [])
        .accessibilityIdentifier("calendarCell-\(cell.id)")
    }

    /// Outside the plan, or not a target while editing: dimmed.
    private var opacity: Double {
        if !cell.isSelectable { return Theme.Opacity.outsidePlan }
        return cell.editRole == .inactive ? Theme.Opacity.inactiveCell : 1
    }

    /// While editing only targets take taps; otherwise any day in the plan.
    private var isTappable: Bool {
        guard let role = cell.editRole else { return cell.isSelectable }
        return role == .target
    }

    private var fill: Color {
        if cell.editRole == .target { return Theme.Palette.accent.opacity(Theme.Opacity.targetFill) }
        if cell.isToday && cell.isSelectable { return Theme.Palette.todayCell }
        return hasSession ? Theme.Palette.card : Theme.Palette.innerCard
    }

    @ViewBuilder
    private var border: some View {
        if cell.isRaceDay {
            shape.strokeBorder(Theme.Palette.accent, lineWidth: Theme.Size.raceBorder)
        } else if cell.status == .notRecorded {
            shape.strokeBorder(
                Theme.Palette.notRecordedBorder,
                style: StrokeStyle(lineWidth: Theme.Size.notRecordedBorder, dash: Theme.Size.notRecordedDash)
            )
        } else if hasSession {
            shape.strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if cell.isRaceDay {
            Image(systemName: "flag.fill")
                .font(Theme.Typography.calendarGlyph)
                .foregroundStyle(Theme.Palette.accent)
                .accessibilityHidden(true)
        } else if let type = cell.sessionType, let status = cell.status {
            SessionTypeIcon(type: type, size: Theme.Size.calendarIcon, color: status.iconColor, isStruck: status.isStruck)
        } else {
            Color.clear
        }
    }
}

// MARK: - Editing

/// "Move session" / "Swap session" with what to tap, and Cancel.
private struct EditBannerView: View {
    let banner: CalendarMonthOverview.EditBanner
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.actionIconToText) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(banner.title)
                    .font(Theme.Typography.bannerTitle)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Palette.accent)
                Text(banner.text)
                    .font(Theme.Typography.bannerText)
                    .foregroundStyle(Theme.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("editBanner")
            Button(action: onCancel) {
                Text("Cancel")
                    .font(Theme.Typography.editButton)
                    .foregroundStyle(Theme.Palette.text)
                    .padding(.horizontal, Theme.Spacing.cancelButtonHorizontal)
                    .frame(minHeight: Theme.Size.minTouchTarget)
                    .overlay { Capsule().strokeBorder(Theme.Palette.iconRing, lineWidth: Theme.Size.borderWidth) }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editCancel")
        }
        .padding(.vertical, Theme.Spacing.editBannerVertical)
        .padding(.horizontal, Theme.Spacing.editBannerHorizontal)
        .background(Theme.Palette.accentFaint, in: RoundedRectangle(cornerRadius: Theme.Radius.editBanner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.editBanner, style: .continuous)
                .strokeBorder(Theme.Palette.accentLine, lineWidth: Theme.Size.borderWidth)
        }
    }
}

/// The notice after an edit (with Undo and an optional heads-up), or the failure bar (with Dismiss).
private struct NoticeBar: View {
    let text: String
    let headsUp: String?
    let buttonTitle: String
    let buttonIdentifier: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.compact) {
            VStack(alignment: .leading, spacing: Theme.Spacing.noticeLines) {
                Text(text)
                    .font(Theme.Typography.noticeText)
                    .foregroundStyle(Theme.Palette.noteText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifier).text")
                if let headsUp {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.tight + 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: Theme.Size.warningIcon))
                            .foregroundStyle(Theme.Palette.headsUpIcon)
                            .accessibilityHidden(true)
                        Text(headsUp)
                            .font(Theme.Typography.headsUpText)
                            .foregroundStyle(Theme.Palette.softText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("noticeHeadsUp")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: action) {
                Text(buttonTitle)
                    .font(Theme.Typography.editButton)
                    .foregroundStyle(Theme.Palette.accent)
                    .padding(.horizontal, Theme.Spacing.undoButtonHorizontal)
                    .frame(minWidth: Theme.Size.minTouchTarget, minHeight: Theme.Size.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(buttonIdentifier)
        }
        .padding(.leading, Theme.Spacing.noticeBarLeading)
        .padding([.top, .bottom, .trailing], Theme.Spacing.noticeBarOther)
        .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.noticeBar, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.noticeBar, style: .continuous)
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// One edit action under the day card: icon, label and hint. Disabled rows are
/// dimmed and not tappable, but still read their hint.
private struct ActionRow: View {
    let action: PlanAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.actionIconToText) {
                ActionIcon(kind: action.kind)
                    .stroke(
                        action.kind == .markMissed ? Theme.Palette.missedAction : Theme.Palette.accent,
                        style: StrokeStyle(lineWidth: Theme.Size.actionIconStroke * Theme.Size.actionIcon / Theme.Size.actionIconGrid, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: Theme.Size.actionIcon, height: Theme.Size.actionIcon)
                    .frame(width: Theme.Size.actionCircle, height: Theme.Size.actionCircle)
                    .overlay { Circle().strokeBorder(Theme.Palette.iconRing, lineWidth: Theme.Size.borderWidth) }
                VStack(alignment: .leading, spacing: Theme.Spacing.tight / 2) {
                    Text(action.label)
                        .font(Theme.Typography.actionLabel)
                        .foregroundStyle(Theme.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(action.hint)
                        .font(Theme.Typography.actionHint)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Theme.Spacing.actionRowVertical)
            .padding(.horizontal, Theme.Spacing.actionRowHorizontal)
            .frame(minHeight: Theme.Size.minTouchTarget)
            .background(Theme.Palette.innerCard, in: RoundedRectangle(cornerRadius: Theme.Radius.actionRow, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.actionRow, style: .continuous)
                    .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.actionRow, style: .continuous))
            .opacity(action.isEnabled ? 1 : Theme.Opacity.disabledAction)
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(action.label)
        .accessibilityHint(action.hint)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }

    private var identifier: String {
        switch action.kind {
        case .moveNextDay: "actionMoveNext"
        case .moveAnotherDay: "actionMoveAnother"
        case .swap: "actionSwap"
        case .markMissed: "actionMissed"
        }
    }
}

/// The action icons, drawn on a 24 x 24 grid.
private struct ActionIcon: Shape {
    let kind: PlanAction.Kind

    func path(in rect: CGRect) -> Path {
        let unit = rect.width / Theme.Size.actionIconGrid
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit) }
        var path = Path()
        func line(_ points: CGPoint...) { path.addLines(points) }
        switch kind {
        case .moveNextDay:
            // M5 12 h14 M13 6 l6 6 -6 6.
            line(p(5, 12), p(19, 12))
            line(p(13, 6), p(19, 12), p(13, 18))
        case .moveAnotherDay:
            // A calendar: the page, the header line and two rings.
            path.addRoundedRect(in: CGRect(x: rect.minX + 4 * unit, y: rect.minY + 5 * unit, width: 16 * unit, height: 15 * unit), cornerSize: CGSize(width: 2 * unit, height: 2 * unit))
            line(p(4, 10), p(20, 10))
            line(p(8, 3), p(8, 7))
            line(p(16, 3), p(16, 7))
        case .swap:
            // M4 8 h15 M15 4 l4 4 -4 4 M20 16 H5 M9 12 l-4 4 4 4.
            line(p(4, 8), p(19, 8))
            line(p(15, 4), p(19, 8), p(15, 12))
            line(p(20, 16), p(5, 16))
            line(p(9, 12), p(5, 16), p(9, 20))
        case .markMissed:
            // M6 6 l12 12 M18 6 L6 18.
            line(p(6, 6), p(18, 18))
            line(p(18, 6), p(6, 18))
        }
        return path
    }
}

/// The five session-type icons with their names. A design addition: the
/// mockup has no legend, but the icons alone are hard to learn.
private struct CalendarLegend: View {
    private static let items: [(SessionType, String)] = [
        (.easy, "circle"), (.tempo, "arrow"), (.threshold, "step"), (.intervals, "zigzag"), (.long, "line with dots"),
    ]

    var body: some View {
        FlowLayout(spacing: Theme.Spacing.legendItemsGap, lineSpacing: Theme.Spacing.legendLines) {
            ForEach(Self.items, id: \.0) { type, _ in
                HStack(spacing: Theme.Spacing.legendIconToName) {
                    SessionTypeIcon(type: type, size: Theme.Size.calendarIcon, color: Theme.Palette.text)
                    Text(SessionFormat.sessionTypeName(type))
                        .font(Theme.Typography.legendLabel)
                        .foregroundStyle(Theme.Palette.mutedText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Legend: " + Self.items.map { "\(SessionFormat.sessionTypeName($0.0)) \($0.1)" }.joined(separator: ", "))
        .accessibilityIdentifier("calendarLegend")
    }
}

#if DEBUG
#Preview("October") {
    MainTabView(screens: CompositionRoot.previewMainScreens(today: "2026-10-28", startTab: .calendar))
        .preferredColorScheme(.dark)
}
#endif
