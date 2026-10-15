import SwiftUI
import Domain

/// Onboarding step 2: where the user stands today and which plans fit. Draws
/// the cache first; each card then follows its own section as the refresh lands.
struct StartingPointView: View {
    let viewModel: StartingPointViewModel
    @State private var sourcesSheet: ScaleText.Kind?
    #if DEBUG
    @State private var showsRawData = false
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.cardStack) {
                header
                if let banner = viewModel.lockedBannerText {
                    LockedBanner(text: banner)
                }
                vo2Card
                restingCard
                recordsSection
                plansSection
            }
            .padding(.horizontal, Theme.Spacing.screenSide)
            .padding(.top, Theme.Spacing.screenTop)
            .padding(.bottom, Theme.Spacing.screenBottom)
        }
        .refreshable { await viewModel.refresh() }
        .background(Theme.Palette.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(item: $sourcesSheet) { kind in
            SourcesSheet(kind: kind, source: source(for: kind))
        }
        #if DEBUG
        .sheet(isPresented: $showsRawData) {
            DebugRawDataSheet(snapshot: viewModel.lastLiveRead)
        }
        #endif
        .task { await viewModel.load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.titleToSubtitle) {
            captionText
            Text(viewModel.title)
                .font(Theme.Typography.compactScreenTitle)
                .foregroundStyle(Theme.Palette.text)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Theme.Spacing.compact) {
                if viewModel.subtitle.showsSpinner {
                    InlineSpinner()
                }
                Text(viewModel.subtitle.text)
                    .font(Theme.Typography.subtitle)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("startingPoint.subtitle")
        }
        .padding(.bottom, Theme.Spacing.compact)
    }

    @ViewBuilder
    private var captionText: some View {
        let caption = Text(viewModel.caption)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.mutedText)
        #if DEBUG
        // DEBUG only: long-press the caption for the raw data that was read.
        caption
            .onLongPressGesture { showsRawData = true }
            .accessibilityAction(named: "Show raw data") { showsRawData = true }
            .accessibilityIdentifier("startingPoint.caption")
        #else
        caption
        #endif
    }

    // MARK: VO2 max

    @ViewBuilder
    private var vo2Card: some View {
        switch viewModel.vo2MaxCard {
        case .loading:
            ScaleCardSkeleton(number: Theme.Size.Skeleton.vo2Number, chip: Theme.Size.Skeleton.vo2Chip, scaleHeight: Theme.Size.Skeleton.curveHeight, showsStatRow: false)
                .accessibilityIdentifier("skeleton.vo2Max")
        case .scale(let card):
            VStack(alignment: .leading, spacing: Theme.Spacing.cardStack) {
                cardHeader(icon: "waveform.path.ecg", title: "Aerobic fitness (VO2 max)", kind: .vo2Max, hasSource: card.source != nil)
                valueRow(card)
                if let betterThan = card.betterThan {
                    BellCurveScale(betterThan: betterThan, bubble: ScaleText.bubble(card))
                        .accessibilityHidden(true)
                }
                cardFooter(card, kind: .vo2Max)
            }
            .voltCard()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("startingPoint.vo2Max")
        case .message(let message):
            messageCard(icon: "waveform.path.ecg", title: "Aerobic fitness (VO2 max)", message: message, identifier: "startingPoint.vo2Max")
        }
    }

    // MARK: Resting heart rate

    @ViewBuilder
    private var restingCard: some View {
        switch viewModel.restingHeartRateCard {
        case .loading:
            ScaleCardSkeleton(number: Theme.Size.Skeleton.restingNumber, chip: Theme.Size.Skeleton.restingChip, scaleHeight: Theme.Size.Skeleton.scaleHeight, showsStatRow: true)
                .accessibilityIdentifier("skeleton.restingHeartRate")
        case .scale(let card):
            VStack(alignment: .leading, spacing: Theme.Spacing.cardStack) {
                cardHeader(icon: "heart", title: "Resting heart rate", kind: .restingHeartRate, hasSource: card.source != nil)
                valueRow(card)
                if let betterThan = card.betterThan {
                    SegmentScale(betterThan: betterThan, bubble: ScaleText.bubble(card))
                        .accessibilityHidden(true)
                }
                cardFooter(card, kind: .restingHeartRate)
                runHeartRateRow
            }
            .voltCard()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("startingPoint.restingHeartRate")
        case .message(let message):
            messageCard(icon: "heart", title: "Resting heart rate", message: message, identifier: "startingPoint.restingHeartRate")
        }
    }

    @ViewBuilder
    private var runHeartRateRow: some View {
        switch viewModel.runHeartRate {
        case .loading:
            SkeletonBlock(height: Theme.Size.Skeleton.statRow, radius: Theme.Radius.smallTile)
        case .value(let value):
            HStack {
                Text("Average during runs")
                    .font(Theme.Typography.statLabel)
                    .foregroundStyle(Theme.Palette.mutedText)
                Spacer()
                Text(value)
                    .font(Theme.Typography.statValue)
                    .foregroundStyle(Theme.Palette.text)
            }
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .frame(minHeight: Theme.Size.Skeleton.statRow)
            .background(Theme.Palette.innerCard, in: RoundedRectangle(cornerRadius: Theme.Radius.smallTile, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.smallTile, style: .continuous)
                    .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
            }
            .accessibilityElement(children: .combine)
        case .hidden:
            EmptyView()
        }
    }

    // MARK: Card parts

    private func cardHeader(icon: String, title: String, kind: ScaleText.Kind, hasSource: Bool) -> some View {
        HStack(spacing: Theme.Spacing.compact) {
            Circle()
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
                .frame(width: Theme.Size.cardIcon, height: Theme.Size.cardIcon)
                .overlay {
                    Image(systemName: icon)
                        .font(Theme.Typography.cardIconGlyph)
                        .foregroundStyle(Theme.Palette.softText)
                }
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.softText)
            Spacer(minLength: Theme.Spacing.compact)
            if hasSource {
                Button {
                    sourcesSheet = kind
                } label: {
                    Image(systemName: "info.circle")
                        .font(Theme.Typography.cardIconGlyph)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .frame(width: Theme.Size.minTouchTarget, height: Theme.Size.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About this comparison")
                .accessibilityIdentifier(kind == .vo2Max ? "startingPoint.vo2Max.info" : "startingPoint.restingHeartRate.info")
            }
        }
    }

    /// Value and unit, with the band chip beside them when it fits and below when not.
    private func valueRow(_ card: StartingPointViewModel.ScaleCard) -> some View {
        let value = HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.compact) {
            Text(card.value)
                .font(Theme.Typography.bigValue)
                .foregroundStyle(Theme.Palette.text)
            Text(card.unit)
                .font(Theme.Typography.unit)
                .foregroundStyle(Theme.Palette.mutedText)
        }
        .fixedSize()
        let chip = card.band.map { Chip(text: ScaleText.bandName($0), color: Self.bandColor($0)) }

        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Theme.Spacing.compact) {
                value
                Spacer(minLength: Theme.Spacing.compact)
                chip
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                value
                chip
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.band.map { "\(card.accessibilityLabel). \(ScaleText.bandName($0))" } ?? card.accessibilityLabel)
    }

    @ViewBuilder
    private func cardFooter(_ card: StartingPointViewModel.ScaleCard, kind: ScaleText.Kind) -> some View {
        if let statement = card.statement {
            Text(statement)
                .font(Theme.Typography.noticeBody)
                .foregroundStyle(Theme.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let note = card.note {
            Text(note)
                .font(Theme.Typography.noticeBody)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        if card.betterThan != nil || card.measured != nil {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                if card.betterThan != nil {
                    Text(ScaleText.footnote(kind))
                }
                if let measured = card.measured {
                    Text(measured)
                }
            }
            .font(Theme.Typography.caption12)
            .foregroundStyle(Theme.Palette.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A card that has no data: what is missing, and what the user can do.
    private func messageCard(icon: String, title: String, message: StartingPointViewModel.Message, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.cardStack) {
            cardHeader(icon: icon, title: title, kind: .vo2Max, hasSource: false)
            messageBody(message)
        }
        .voltCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func messageBody(_ message: StartingPointViewModel.Message) -> some View {
        Text(message.text)
            .font(Theme.Typography.noticeBody)
            .foregroundStyle(Theme.Palette.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        if message.showsSettingsHint {
            Text(StartingPointViewModel.settingsHint)
                .font(Theme.Typography.caption12)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        if message.showsRetry {
            Button("Try again") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(OutlineButtonStyle())
            .accessibilityIdentifier("startingPoint.retry")
        }
    }

    private func source(for kind: ScaleText.Kind) -> String {
        let display = kind == .vo2Max ? viewModel.vo2MaxCard : viewModel.restingHeartRateCard
        if case .scale(let card) = display { return card.source ?? "" }
        return ""
    }

    static func bandColor(_ band: FitnessBand) -> Color {
        switch band {
        case .excellent, .aboveAverage: Theme.Palette.statusGreen
        case .average: Theme.Palette.softText
        case .belowAverage: Theme.Palette.statusAmber
        case .low: Theme.Palette.statusRed
        }
    }

    // MARK: Records

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent PRs")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Estimated from your Health workouts")
                    .font(Theme.Typography.caption12)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
            .padding(.top, Theme.Spacing.sectionTop)

            VStack(alignment: .leading, spacing: 0) {
                switch viewModel.records {
                case .loading:
                    ForEach(0..<Theme.Size.Skeleton.recordRows, id: \.self) { index in
                        if index > 0 { divider }
                        RecordRowSkeleton()
                    }
                case .rows(let rows):
                    ForEach(Array(rows.enumerated()), id: \.element.distance) { index, row in
                        if index > 0 { divider }
                        recordRow(row)
                    }
                case .message(let message):
                    VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                        messageBody(message)
                    }
                    .padding(.vertical, Theme.Spacing.cardInner)
                }
            }
            .padding(.horizontal, Theme.Spacing.cardInner)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.Palette.cardBorder).frame(height: Theme.Size.borderWidth)
    }

    private func recordRow(_ row: StartingPointViewModel.RecordRow) -> some View {
        HStack(spacing: Theme.Spacing.rowIconToLabel) {
            Text(row.distance.rawValue)
                .font(Theme.Typography.chip)
                .foregroundStyle(Theme.Palette.text)
                .frame(width: Theme.Size.distanceTile, height: Theme.Size.distanceTile)
                .background(Theme.Palette.innerCard, in: RoundedRectangle(cornerRadius: Theme.Radius.smallTile, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.smallTile, style: .continuous)
                        .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
                }

            if let time = row.time, let detail = row.detail {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    HStack(spacing: Theme.Spacing.compact) {
                        Text(time)
                            .font(Theme.Typography.recordTime)
                            .foregroundStyle(Theme.Palette.text)
                        if row.isEstimated {
                            Chip(text: "est.", color: Theme.Palette.mutedText)
                        }
                    }
                    Text(detail)
                        .font(Theme.Typography.caption12)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if row.isNew {
                    Chip(text: "NEW PR", color: Theme.Palette.accent)
                } else if row.isOlder {
                    Chip(text: "Older", color: Theme.Palette.mutedText)
                }
            } else {
                Text("No run found near this distance yet.")
                    .font(Theme.Typography.noticeBody)
                    .foregroundStyle(Theme.Palette.mutedText)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, Theme.Spacing.rowVertical)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("startingPoint.record.\(row.distance.rawValue)")
    }

    // MARK: Plans

    private var plansSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text("Plans that fit you")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Pick one to start, or build your own race.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
            .padding(.top, Theme.Spacing.sectionTop)

            switch viewModel.plans {
            case .loading:
                ForEach(0..<Theme.Size.Skeleton.planCards, id: \.self) { _ in
                    PlanCardSkeleton()
                }
            case .plans(let suggestions):
                ForEach(suggestions, id: \.plan) { suggestion in
                    PlanCard(suggestion: suggestion, isSelected: viewModel.selectedPlan == suggestion.plan) {
                        viewModel.select(suggestion.plan)
                    }
                }
            case .message(let message):
                VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                    messageBody(message)
                }
                .voltCard()
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.betweenButtons) {
            Button(viewModel.primaryTitle) { viewModel.continueWithSelectedPlan() }
                .buttonStyle(PrimaryButtonStyle())
                .opacity(viewModel.isPrimaryEnabled ? 1 : Theme.Opacity.disabledButton)
                .disabled(!viewModel.isPrimaryEnabled)
                .accessibilityIdentifier("startingPoint.continue")
            Button("Custom race") { viewModel.chooseCustomRace() }
                .buttonStyle(OutlineButtonStyle())
                .disabled(!viewModel.isCustomRaceEnabled)
                .accessibilityIdentifier("startingPoint.customRace")
        }
        .padding(.horizontal, Theme.Spacing.screenSide)
        .padding(.top, Theme.Spacing.bottomBarTop)
        .padding(.bottom, Theme.Spacing.bottomBarBottom)
        .background {
            Theme.Palette.background
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.Palette.cardBorder).frame(height: Theme.Size.bottomBarBorder)
                }
        }
    }
}

/// Shown while a section is locked: amber, with when the shown data was read.
private struct LockedBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.compact) {
            Image(systemName: "lock.fill")
                .font(Theme.Typography.cardIconGlyph)
                .foregroundStyle(Theme.Palette.statusAmber)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text("Your phone is locked")
                    .font(Theme.Typography.noticeTitle)
                    .foregroundStyle(Theme.Palette.text)
                Text(text)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.softText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.bannerVertical)
        .padding(.horizontal, Theme.Spacing.bannerHorizontal)
        .background(
            Theme.Palette.statusAmber.opacity(Theme.Opacity.lockedBannerFill),
            in: RoundedRectangle(cornerRadius: Theme.Radius.banner, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.banner, style: .continuous)
                .strokeBorder(Theme.Palette.statusAmber.opacity(Theme.Opacity.lockedBannerBorder), lineWidth: Theme.Size.borderWidth)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("startingPoint.lockedBanner")
    }
}

/// A 16 pt accent arc turning on a faint track.
private struct InlineSpinner: View {
    @State private var isSpinning = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.Palette.cardBorder, lineWidth: Theme.Size.inlineSpinnerStroke)
            Circle()
                .trim(from: 0, to: Theme.Size.spinnerArc)
                .stroke(Theme.Palette.accent, style: StrokeStyle(lineWidth: Theme.Size.inlineSpinnerStroke, lineCap: .round))
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .animation(.linear(duration: Theme.Motion.spinnerRevolution).repeatForever(autoreverses: false), value: isSpinning)
        }
        .frame(width: Theme.Size.inlineSpinner, height: Theme.Size.inlineSpinner)
        .onAppear { isSpinning = true }
        .accessibilityHidden(true)
    }
}

extension ScaleText.Kind: Identifiable {
    var id: Self { self }
}

// MARK: - Components

/// A small rounded label tinted with its color.
private struct Chip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(Theme.Typography.chip)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Theme.Spacing.chipHorizontal)
            .padding(.vertical, Theme.Spacing.chipVertical)
            .background(color.opacity(Theme.Opacity.chipTint), in: Capsule())
    }
}

/// A selectable plan suggestion.
private struct PlanCard: View {
    let suggestion: PlanSuggestion
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Theme.Spacing.betweenButtons) {
                HStack(spacing: Theme.Spacing.rowIconToLabel) {
                    Text(StartingPointViewModel.badge(suggestion.plan))
                        .font(Theme.Typography.badge)
                        .foregroundStyle(isSelected ? Theme.Palette.onAccent : Theme.Palette.text)
                        .frame(width: Theme.Size.planBadge, height: Theme.Size.planBadge)
                        .background(
                            isSelected ? Theme.Palette.accent : Theme.Palette.innerCard,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.smallTile, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.smallTile, style: .continuous)
                                .strokeBorder(isSelected ? .clear : Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
                        }
                    VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                        Text(StartingPointViewModel.title(suggestion.plan))
                            .font(Theme.Typography.planTitle)
                            .foregroundStyle(Theme.Palette.text)
                        Text(StartingPointViewModel.schedule(suggestion))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.mutedText)
                    }
                    Spacer(minLength: 0)
                    checkRing
                }
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.compact) {
                    Chip(text: StartingPointViewModel.label(suggestion.label), color: Self.color(suggestion.label))
                    Text(suggestion.reason)
                        .font(Theme.Typography.noticeBody)
                        .foregroundStyle(Theme.Palette.softText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Theme.Palette.accentFaint : Theme.Palette.card,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.Palette.accent : Theme.Palette.cardBorder,
                        lineWidth: isSelected ? Theme.Size.selectedBorderWidth : Theme.Size.borderWidth
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("plan.\(suggestion.plan.rawValue)")
    }

    private var checkRing: some View {
        Group {
            if isSelected {
                Circle()
                    .fill(Theme.Palette.accent)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(Theme.Typography.statusGlyph)
                            .foregroundStyle(Theme.Palette.onAccent)
                    }
            } else {
                Circle()
                    .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.selectedBorderWidth)
            }
        }
        .frame(width: Theme.Size.checkRing, height: Theme.Size.checkRing)
        .accessibilityHidden(true)
    }

    /// Best fit uses the accent; the others use status colors.
    static func color(_ label: FitLabel) -> Color {
        switch label {
        case .bestFit: Theme.Palette.accent
        case .greatFit: Theme.Palette.statusGreen
        case .stretch: Theme.Palette.statusAmber
        case .later: Theme.Palette.mutedText
        }
    }
}

/// Where the source and caveats of a comparison are explained.
private struct SourcesSheet: View {
    let kind: ScaleText.Kind
    let source: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.cardStack) {
                HStack {
                    Text("About this comparison")
                        .font(Theme.Typography.sectionTitle)
                        .foregroundStyle(Theme.Palette.text)
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(TextButtonStyle())
                        .accessibilityIdentifier("sources.done")
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text("Source")
                        .font(Theme.Typography.fieldLabel)
                        .foregroundStyle(Theme.Palette.mutedText)
                    Text(source)
                        .font(Theme.Typography.noticeBody)
                        .foregroundStyle(Theme.Palette.softText)
                        .textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                    Text("Keep in mind")
                        .font(Theme.Typography.fieldLabel)
                        .foregroundStyle(Theme.Palette.mutedText)
                    ForEach(ScaleText.caveats(kind), id: \.self) { caveat in
                        Text(caveat)
                            .font(Theme.Typography.noticeBody)
                            .foregroundStyle(Theme.Palette.softText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(Theme.Spacing.screenSide)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

private extension View {
    /// The standard Volt card: card fill, border, large radius, inner padding.
    func voltCard() -> some View {
        padding(Theme.Spacing.cardInner)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous)
                    .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
            }
    }
}

#if DEBUG
#Preview("Casual") {
    StartingPointView(viewModel: CompositionRoot.previewStartingPointViewModel(persona: "casual"))
}

#Preview("Loading") {
    StartingPointView(viewModel: CompositionRoot.previewStartingPointViewModel(persona: "casual", slow: true))
}
#endif
