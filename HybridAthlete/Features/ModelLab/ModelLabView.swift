#if DEBUG
import SwiftUI
import Domain
import Application

/// DEBUG only: the Model Lab. Pick a model (Apple's or Claude) and an experiment,
/// run it, compare the raw answers and what Claude cost. Every value comes from
/// `ModelLabViewModel` and its `ClaudeLabViewModel`.
struct ModelLabView: View {
    let viewModel: ModelLabViewModel
    let onBack: () -> Void

    @FocusState private var focus: LabField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.labBlocks) {
                header
                CostCard(claude: viewModel.claude)
                modelSelector
                if let status = viewModel.status {
                    AvailabilityCard(model: viewModel.selectedModel, status: status, quotaLine: viewModel.quotaLine)
                }
                if viewModel.selectedModel.provider == .anthropic {
                    APIKeyCard(claude: viewModel.claude, focus: $focus)
                    SpendGuardCard(claude: viewModel.claude, focus: $focus)
                }
                experimentPicker
                buttons
                if let running = viewModel.running {
                    RunningCard(model: running.model) { viewModel.cancel() }
                }
                ForEach(viewModel.cards) { card in
                    ResultCard(card: card)
                }
                ProjectionCard(claude: viewModel.claude)
            }
            .padding(.horizontal, Theme.Spacing.labSide)
            .padding(.top, Theme.Spacing.contentTop)
            .padding(.bottom, Theme.Spacing.screenBottom)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .task { await viewModel.appear() }
        .sheet(isPresented: Bindable(viewModel.claude).showsConsent) {
            ConsentSheet(claude: viewModel.claude)
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: Theme.Spacing.detailBackToTitle) {
            SquareChevronButton(direction: .left, label: "Back", identifier: "modelLabBack", action: onBack)
            Text("Model Lab")
                .font(Theme.Typography.labTitle)
                .foregroundStyle(Theme.Palette.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Spacing.compact)
            LabOutlineChip(text: "Debug only")
        }
    }

    private var modelSelector: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.labCardRows) {
            modelGroup("Apple", models: ModelChoice.apple)
            modelGroup("Anthropic", models: ModelChoice.claude)
            if let line = viewModel.claude.priceLine(viewModel.selectedModel) {
                Text(line)
                    .font(Theme.Typography.labMeta)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .accessibilityIdentifier("modelLabPriceLine")
            }
        }
    }

    private func modelGroup(_ title: String, models: [ModelChoice]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.labGroup) {
            LabSectionLabel(text: title)
            FlowLayout(spacing: Theme.Spacing.labPills, lineSpacing: Theme.Spacing.labPills) {
                ForEach(models, id: \.id) { model in
                    LabPill(title: model.displayName, isSelected: viewModel.selectedModel == model, identifier: "modelLabModel-\(model.id)") {
                        viewModel.selectedModel = model
                    }
                }
            }
        }
    }

    private var experimentPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.labCardRows) {
            LabSectionLabel(text: "Experiment")
            HStack(spacing: Theme.Spacing.labPills) {
                ForEach(ModelLabViewModel.Experiment.allCases) { experiment in
                    LabPill(title: experiment.title, isSelected: viewModel.experiment == experiment, identifier: "modelLabExperiment-\(experiment.rawValue)") {
                        viewModel.experiment = experiment
                    }
                }
            }
            if viewModel.experiment == .coachNote {
                FlowLayout(spacing: Theme.Spacing.labPills, lineSpacing: Theme.Spacing.labPills) {
                    ForEach(ModelLabViewModel.CoachInput.allCases) { input in
                        LabPill(title: input.title, isSelected: viewModel.coachInput == input, identifier: "modelLabInput-\(input.rawValue)") {
                            viewModel.coachInput = input
                        }
                    }
                }
                if let text = viewModel.latestUnavailableText, viewModel.coachInput == .latest {
                    Text(text)
                        .font(Theme.Typography.labMeta)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Your stored race setup, or a 10 km race 8 weeks away on Mon, Wed and Fri. Nothing is saved.")
                    .font(Theme.Typography.labMeta)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: Theme.Spacing.labPills) {
            Button("Run") { viewModel.run() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isRunning)
                .accessibilityIdentifier("modelLabRun")
            Button(viewModel.runAllTitle) { viewModel.runAll() }
                .buttonStyle(OutlineButtonStyle())
                .disabled(viewModel.isRunning)
                .accessibilityIdentifier("modelLabRunAll")
        }
    }
}

// MARK: - Pieces

struct LabSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typography.labSection)
            .foregroundStyle(Theme.Palette.mutedText)
            .accessibilityAddTraits(.isHeader)
    }
}

struct LabPill: View {
    let title: String
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.labPill)
                .foregroundStyle(isSelected ? Theme.Palette.onAccent : Theme.Palette.mutedText)
                .padding(.horizontal, Theme.Spacing.labPillHorizontal)
                .frame(minHeight: Theme.Size.minTouchTarget)
                .background(isSelected ? Theme.Palette.accent : Theme.Palette.card, in: Capsule())
                .overlay {
                    if !isSelected { Capsule().strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

struct LabOutlineChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typography.labChip)
            .foregroundStyle(Theme.Palette.softText)
            .padding(.horizontal, Theme.Spacing.labChipHorizontal)
            .padding(.vertical, Theme.Spacing.labChipVertical)
            .overlay { Capsule().strokeBorder(Theme.Palette.iconRing, lineWidth: Theme.Size.borderWidth) }
    }
}

/// Accent text on an accent tint, or soft text on a soft tint, or amber for issues.
struct LabFilledChip: View {
    enum Tone { case accent, neutral, warning }
    let text: String
    let tone: Tone

    var body: some View {
        let color: Color = switch tone {
        case .accent: Theme.Palette.accent
        case .neutral: Theme.Palette.softText
        case .warning: Theme.Palette.statusAmber
        }
        Text(text)
            .font(Theme.Typography.labChip)
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Spacing.labChipHorizontal)
            .padding(.vertical, Theme.Spacing.labChipVertical)
            .background(color.opacity(Theme.Opacity.statusChipFill), in: Capsule())
    }
}

struct LabCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.labCardRows) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.labCardPadding)
            .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.labCard, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.labCard, style: .continuous)
                    .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
            }
    }
}

private struct AvailabilityCard: View {
    let model: ModelChoice
    let status: ModelStatus
    let quotaLine: (QuotaStatus) -> String

    private var lines: [String] {
        // The Claude package exposes no context size.
        var lines = model.provider == .anthropic ? [] : ["Context size: " + (status.contextSize.map { "\($0) tokens" } ?? "unknown")]
        if let quota = status.quota { lines.append("Quota: " + quotaLine(quota)) }
        if !status.availability.isAvailable { lines.append(status.availability.message) }
        return lines
    }

    var body: some View {
        LabCard {
            HStack(spacing: Theme.Spacing.labPills) {
                Text(model.displayName).font(Theme.Typography.labPill).foregroundStyle(Theme.Palette.text)
                LabFilledChip(text: status.availability.chipText, tone: status.availability.isAvailable ? .accent : .neutral)
            }
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(Theme.Typography.labBody)
                    .foregroundStyle(Theme.Palette.softText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.displayName), \(status.availability.chipText). " + lines.joined(separator: ". "))
        .accessibilityIdentifier("modelLabAvailability")
    }
}

private struct RunningCard: View {
    let model: ModelChoice
    let onCancel: () -> Void

    var body: some View {
        LabCard {
            HStack(spacing: Theme.Spacing.labPills) {
                ProgressView().tint(Theme.Palette.accent)
                Text("Running on \(model.displayName)\u{2026}")
                    .font(Theme.Typography.labBody)
                    .foregroundStyle(Theme.Palette.softText)
                Spacer(minLength: Theme.Spacing.compact)
                Button("Cancel", action: onCancel)
                    .font(Theme.Typography.labPill)
                    .foregroundStyle(Theme.Palette.text)
                    .padding(.horizontal, Theme.Spacing.labPillHorizontal)
                    .frame(minHeight: Theme.Size.minTouchTarget)
                    .overlay { Capsule().strokeBorder(Theme.Palette.iconRing, lineWidth: Theme.Size.borderWidth) }
                    .accessibilityIdentifier("modelLabCancel")
            }
        }
    }
}

private struct ResultCard: View {
    let card: ModelLabViewModel.Card
    @State private var copied = false

    private var result: ExperimentResult { card.result }

    var body: some View {
        LabCard {
            summary
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary)
                .accessibilityIdentifier("modelLabResult-\(card.id)")
            DisclosureGroup("Prompt") {
                Text(result.promptText)
                    .font(Theme.Typography.labPrompt)
                    .foregroundStyle(Theme.Palette.softText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(Theme.Typography.labPill)
            .tint(Theme.Palette.softText)
            .foregroundStyle(Theme.Palette.text)
            if let json = card.json {
                Button(copied ? "Copied" : "Copy result JSON") {
                    Clipboard.copy(json)
                    copied = true
                }
                .buttonStyle(OutlineButtonStyle())
                .accessibilityIdentifier("modelLabCopy")
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.labCardRows) {
            FlowLayout(spacing: Theme.Spacing.labPills, lineSpacing: Theme.Spacing.labPills) {
                LabOutlineChip(text: result.model.displayName)
                if let usage = result.usage {
                    Text(usage.latencyText).font(Theme.Typography.labMeta).foregroundStyle(Theme.Palette.softText)
                }
                if let cost = result.usage?.costMicros {
                    LabFilledChip(text: CostFormatter.text(micros: cost), tone: .neutral)
                        .accessibilityIdentifier("modelLabCost-\(card.id)")
                }
                if let validity = result.validityText {
                    LabFilledChip(text: validity, tone: validity == "Valid" ? .accent : .warning)
                }
            }
            if let line = result.usage?.line, !line.isEmpty {
                Text(line).font(Theme.Typography.labMeta).foregroundStyle(Theme.Palette.mutedText)
            }
            if let cost = result.usage?.costMicros {
                Text(CostFormatter.perThousandRunsText(micros: cost)).font(Theme.Typography.labMeta).foregroundStyle(Theme.Palette.mutedText)
            }
            if let cache = result.usage?.cacheLine {
                Text(cache).font(Theme.Typography.labMeta).foregroundStyle(Theme.Palette.mutedText)
            }
            switch result.output {
            case .coachNote(let note):
                Text(note.headline).font(Theme.Typography.labNoteHeadline).foregroundStyle(Theme.Palette.text)
                Text(note.observation).font(Theme.Typography.labBody).foregroundStyle(Theme.Palette.softText)
                Text(note.nextStep).font(Theme.Typography.labBody).foregroundStyle(Theme.Palette.text)
            case .planDraft(let table):
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    Text(row).font(Theme.Typography.labMeta).foregroundStyle(Theme.Palette.softText)
                }
                if let line = table.comparisonLine {
                    Text(line).font(Theme.Typography.labMeta).foregroundStyle(Theme.Palette.mutedText)
                }
            case nil:
                EmptyView()
            }
            ForEach(result.violations + result.softFlags, id: \.self) { issue in
                Text(issue).font(Theme.Typography.labMeta).foregroundStyle(Theme.Palette.statusAmber)
            }
            if let error = card.errorText {
                Text(error).font(Theme.Typography.labBody).foregroundStyle(Theme.Palette.softText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "On-device, 1.2 s, in 312 · out 64, Valid. Coach note: …".
    private var accessibilitySummary: String {
        var parts = [result.model.displayName]
        if let usage = result.usage {
            parts.append(usage.latencyText)
            if let cost = usage.costMicros { parts.append("cost \(CostFormatter.text(micros: cost))") }
            if !usage.line.isEmpty { parts.append(usage.line) }
        }
        if let validity = result.validityText { parts.append(validity) }
        var text = parts.joined(separator: ", ") + "."
        switch result.output {
        case .coachNote(let note): text += " Coach note: \(note.headline). \(note.observation) \(note.nextStep)"
        case .planDraft(let table): text += " Plan draft with \(table.rows.count) weeks. " + table.rows.joined(separator: ". ")
        case nil: break
        }
        let issues = result.violations + result.softFlags
        if !issues.isEmpty { text += " Issues: " + issues.joined(separator: ". ") }
        if let error = card.errorText { text += " \(error)" }
        return text
    }
}
#endif
