import SwiftUI
import Domain
import Application

/// The after-workout check: "Anything bothering you?" No saves at once; Yes asks
/// for areas, and for each one the side, ache or pain, and the level. Every answer
/// is a tap; the note is optional. Skip closes without asking again.
struct FeedbackSheetView: View {
    let prompt: FeedbackPrompt
    let existing: WorkoutFeedback?
    let onSubmit: (WorkoutFeedback.Status, [AreaReport], String?) -> Void
    let onSkip: () -> Void

    private struct Draft: Equatable {
        var side: BodySide?
        var kind: DiscomfortKind?
        var level: DiscomfortLevel?
    }

    @State private var hasIssue: Bool?
    @State private var areas: [BodyArea] = []
    @State private var drafts: [BodyArea: Draft] = [:]
    @State private var otherName = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.detailBlocks) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                        Text(prompt.title)
                            .font(Theme.Typography.detailCaption)
                            .foregroundStyle(Theme.Palette.mutedText)
                        Text(prompt.detail)
                            .font(Theme.Typography.sessionMeta)
                            .foregroundStyle(Theme.Palette.softText)
                    }
                    .accessibilityElement(children: .combine)
                    question("Anything bothering you?")
                    HStack(spacing: Theme.Spacing.chipRow) {
                        choice("No, all good", isOn: hasIssue == false, identifier: "feedbackNo") {
                            hasIssue = false
                        }
                        choice("Yes", isOn: hasIssue == true, identifier: "feedbackYes") { hasIssue = true }
                    }
                    if hasIssue == true {
                        question("Where?")
                        FlowLayout(spacing: Theme.Spacing.chipRow, lineSpacing: Theme.Spacing.chipRow) {
                            ForEach(BodyArea.allCases, id: \.self) { area in
                                choice(area.title, isOn: areas.contains(area), identifier: "feedbackArea-\(area.rawValue)") { toggle(area) }
                            }
                        }
                        ForEach(areas, id: \.self) { area in
                            areaCard(area)
                        }
                    }
                    if hasIssue != nil {
                        question("Note (optional)")
                        TextField("Anything else, in a few words", text: $note, axis: .vertical)
                            .lineLimit(1...3)
                            .font(Theme.Typography.sessionMeta)
                            .foregroundStyle(Theme.Palette.text)
                            .padding(Theme.Spacing.selectedCardPadding)
                            .background(Theme.Palette.innerCard, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
                            .onChange(of: note) { _, value in
                                if value.count > FeedbackRules.noteMaxLength { note = String(value.prefix(FeedbackRules.noteMaxLength)) }
                            }
                            .accessibilityIdentifier("feedbackNote")
                        if showsSevere {
                            Text(FeedbackRules.severePainMessage)
                                .font(Theme.Typography.sessionMeta)
                                .foregroundStyle(Theme.Palette.statusAmber)
                                .accessibilityIdentifier("feedbackSevere")
                        }
                        Button("Save") { submit() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!canSave)
                            .accessibilityIdentifier("feedbackSave")
                    }
                }
                .padding(.horizontal, Theme.Spacing.contentSide)
                .padding(.vertical, Theme.Spacing.contentTop)
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle("How did it feel?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", action: onSkip).accessibilityIdentifier("feedbackSkip")
                }
            }
        }
        .accessibilityIdentifier("feedbackSheet")
        .onAppear(perform: prefill)
        .interactiveDismissDisabled()
    }

    // MARK: Parts

    private func question(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.sessionName)
            .foregroundStyle(Theme.Palette.text)
            .accessibilityAddTraits(.isHeader)
    }

    private func areaCard(_ area: BodyArea) -> some View {
        let draft = drafts[area] ?? Draft()
        return VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            Text(area.title)
                .font(Theme.Typography.sessionName)
                .foregroundStyle(Theme.Palette.text)
            if area == .other {
                TextField("Which area?", text: $otherName)
                    .font(Theme.Typography.sessionMeta)
                    .padding(Theme.Spacing.compact)
                    .background(Theme.Palette.innerCard, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
                    .onChange(of: otherName) { _, value in
                        if value.count > FeedbackRules.otherNameMaxLength { otherName = String(value.prefix(FeedbackRules.otherNameMaxLength)) }
                    }
                    .accessibilityIdentifier("feedbackOtherName")
            }
            if area != .lowerBack {
                row(BodySide.allCases, selected: draft.side, title: \.title, id: { "feedbackSide-\(area.rawValue)-\($0.rawValue)" }) {
                    drafts[area, default: Draft()].side = $0
                }
            }
            row(DiscomfortKind.allCases, selected: draft.kind, title: \.title, id: { "feedbackKind-\(area.rawValue)-\($0.rawValue)" }) {
                drafts[area, default: Draft()].kind = $0
            }
            if let kind = draft.kind {
                Text(kind.explanation)
                    .font(Theme.Typography.sessionMeta)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            row(DiscomfortLevel.allCases, selected: draft.level, title: \.title, id: { "feedbackLevel-\(area.rawValue)-\($0.rawValue)" }) {
                drafts[area, default: Draft()].level = $0
            }
            if let level = draft.level {
                Text(level.explanation)
                    .font(Theme.Typography.sessionMeta)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.selectedCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
        }
    }

    private func row<Value: Hashable>(
        _ values: [Value], selected: Value?, title: KeyPath<Value, String>, id: @escaping (Value) -> String, onPick: @escaping (Value) -> Void
    ) -> some View {
        FlowLayout(spacing: Theme.Spacing.chipRow, lineSpacing: Theme.Spacing.chipRow) {
            ForEach(values, id: \.self) { value in
                choice(value[keyPath: title], isOn: selected == value, identifier: id(value)) { onPick(value) }
            }
        }
    }

    private func choice(_ title: String, isOn: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.sessionMeta)
                .foregroundStyle(isOn ? Theme.Palette.onAccent : Theme.Palette.text)
                .padding(.horizontal, Theme.Spacing.selectedCardPadding)
                .frame(minHeight: Theme.Size.minTouchTarget)
                .background(isOn ? Theme.Palette.accent : Theme.Palette.innerCard, in: Capsule())
                .overlay { Capsule().strokeBorder(isOn ? Theme.Palette.accent : Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    // MARK: State

    private func toggle(_ area: BodyArea) {
        if let index = areas.firstIndex(of: area) {
            areas.remove(at: index)
            drafts[area] = nil
        } else {
            areas.append(area)
        }
    }

    /// Every area has a kind and a level, and a side (the lower back has none).
    private var reports: [AreaReport]? {
        var result: [AreaReport] = []
        for area in areas {
            let draft = drafts[area] ?? Draft()
            guard let kind = draft.kind, let level = draft.level else { return nil }
            let side = area == .lowerBack ? BodySide.both : draft.side
            guard let side else { return nil }
            result.append(AreaReport(area: area, otherName: area == .other ? otherName : nil, side: side, kind: kind, level: level))
        }
        return result
    }

    private var canSave: Bool {
        if hasIssue == false { return true }
        guard let reports else { return false }
        return !reports.isEmpty
    }

    private var showsSevere: Bool {
        areas.contains { drafts[$0]?.kind == .pain && drafts[$0]?.level == .severe }
    }

    private func submit() {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasIssue == true, let reports {
            onSubmit(.reported, reports, text.isEmpty ? nil : text)
        } else {
            onSubmit(.noIssues, [], text.isEmpty ? nil : text)
        }
    }

    private func prefill() {
        guard let existing, existing.status != .skipped else { return }
        note = existing.note ?? ""
        hasIssue = existing.status == .reported
        areas = existing.areas.map(\.area)
        for report in existing.areas {
            drafts[report.area] = Draft(side: report.side, kind: report.kind, level: report.level)
            if report.area == .other { otherName = report.otherName ?? "" }
        }
    }
}
