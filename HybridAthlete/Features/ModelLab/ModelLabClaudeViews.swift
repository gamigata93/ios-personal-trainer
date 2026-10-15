#if DEBUG
import SwiftUI
import Domain
import Application

/// The Lab's text fields, for the keyboard's Done button.
enum LabField: Hashable {
    case apiKey, perRun, perMonth
}

/// The cost card at the top of the Lab: what Claude cost in a period (an
/// estimate), per model, with Copy usage JSON and Clear history.
struct CostCard: View {
    @Bindable var claude: ClaudeLabViewModel
    @State private var confirmsClear = false
    @State private var copied = false

    var body: some View {
        LabCard {
            Picker("Period", selection: $claude.period) {
                ForEach(SpendPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("costPeriod")

            VStack(alignment: .leading, spacing: Theme.Spacing.labGroup) {
                Text(claude.totalText)
                    .font(Theme.Typography.labCostTotal)
                    .foregroundStyle(Theme.Palette.text)
                Text(claude.captionText)
                    .font(Theme.Typography.labMeta)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(claude.statsText)
                    .font(Theme.Typography.labMeta)
                    .foregroundStyle(Theme.Palette.softText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(claude.costAccessibilityText)
            .accessibilityValue(claude.totalText)
            .accessibilityIdentifier("costTotal")

            ForEach(claude.overview.rows) { row in
                HStack(spacing: Theme.Spacing.labPills) {
                    Text(row.name)
                        .font(Theme.Typography.labBody)
                        .foregroundStyle(Theme.Palette.text)
                    Spacer(minLength: Theme.Spacing.labPills)
                    Text(claude.rowText(row))
                        .font(Theme.Typography.labRowValue)
                        .foregroundStyle(Theme.Palette.softText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("costModelRow-\(row.modelId)")
            }

            ForEach(footnotes, id: \.self) { line in
                Text(line)
                    .font(Theme.Typography.labMeta)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Theme.Spacing.labPills) {
                Button(copied ? "Copied" : "Copy usage JSON") {
                    Task {
                        if let json = await claude.usageJSON() {
                            Clipboard.copy(json)
                            copied = true
                        }
                    }
                }
                .buttonStyle(OutlineButtonStyle())
                .accessibilityIdentifier("costCopyJSON")
                Button("Clear history") { confirmsClear = true }
                    .buttonStyle(OutlineButtonStyle(textColor: Theme.Palette.statusRed))
                    .accessibilityIdentifier("costClear")
            }
        }
        .confirmationDialog("Clear the usage history?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { Task { await claude.clearHistory() } }
        } message: {
            Text("This deletes the local record of every model call. Anthropic's Console keeps its own.")
        }
    }

    private var footnotes: [String] {
        [
            "Anthropic's Console (Usage page) is the source of truth. This app only counts calls made from this iPhone.",
            claude.staleText,
            claude.priceTableMissingText,
        ].compactMap { $0 }
    }
}

/// The key: saved or not (last 4 characters only), a secure field, Save, Test, Remove.
struct APIKeyCard: View {
    @Bindable var claude: ClaudeLabViewModel
    var focus: FocusState<LabField?>.Binding

    var body: some View {
        LabCard {
            HStack(spacing: Theme.Spacing.labPills) {
                Text("Anthropic API key")
                    .font(Theme.Typography.labPill)
                    .foregroundStyle(Theme.Palette.text)
                Spacer(minLength: Theme.Spacing.labPills)
                Text(claude.keyStatus.text)
                    .font(Theme.Typography.labMeta)
                    .foregroundStyle(Theme.Palette.softText)
                    .accessibilityIdentifier("anthropicKeyStatus")
            }
            SecureField("Paste your API key", text: $claude.keyInput)
                .font(Theme.Typography.labField)
                .foregroundStyle(Theme.Palette.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(focus, equals: .apiKey)
                .submitLabel(.done)
                .padding(.horizontal, Theme.Spacing.labFieldHorizontal)
                .frame(minHeight: Theme.Size.minTouchTarget)
                .background(Theme.Palette.innerCard, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                        .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
                }
                .accessibilityLabel("Anthropic API key")
                .accessibilityIdentifier("anthropicKeyField")
            HStack(spacing: Theme.Spacing.labPills) {
                Button("Save") {
                    focus.wrappedValue = nil
                    Task { await claude.saveKey() }
                }
                .buttonStyle(CompactPrimaryButtonStyle())
                    .accessibilityIdentifier("anthropicKeySave")
                Button(claude.isTestingKey ? "Testing" : "Test") { Task { await claude.testKey() } }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(claude.isTestingKey)
                    .accessibilityIdentifier("anthropicKeyTest")
                Button("Remove") { Task { await claude.removeKey() } }
                    .buttonStyle(OutlineButtonStyle(textColor: Theme.Palette.statusRed))
                    .accessibilityIdentifier("anthropicKeyRemove")
            }
            if let message = claude.keyMessage {
                Text(message)
                    .font(Theme.Typography.labBody)
                    .foregroundStyle(Theme.Palette.softText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("anthropicKeyMessage")
            }
            Text("Use a dedicated API key for this app (Claude Console, API keys) so that key's usage in the Console matches the total below.")
                .font(Theme.Typography.labMeta)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Per-run and monthly caps in dollars, with this month's spend against the monthly cap.
struct SpendGuardCard: View {
    let claude: ClaudeLabViewModel
    var focus: FocusState<LabField?>.Binding

    var body: some View {
        LabCard {
            Text("Spend limits")
                .font(Theme.Typography.labPill)
                .foregroundStyle(Theme.Palette.text)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .bottom, spacing: Theme.Spacing.labPills) {
                capField("Per run", text: claude.perRunText, field: .perRun, identifier: "capPerRun") { text in
                    Task { await claude.updatePerRun(text) }
                }
                capField("Per month", text: claude.perMonthText, field: .perMonth, identifier: "capPerMonth") { text in
                    Task { await claude.updatePerMonth(text) }
                }
                // Number pads have no return key (and a full-screen cover has no keyboard toolbar).
                if focus.wrappedValue == .perRun || focus.wrappedValue == .perMonth {
                    Button("Done") { focus.wrappedValue = nil }
                        .font(Theme.Typography.labPill)
                        .foregroundStyle(Theme.Palette.onAccent)
                        .padding(.horizontal, Theme.Spacing.labPillHorizontal)
                        .frame(minHeight: Theme.Size.minTouchTarget)
                        .background(Theme.Palette.accent, in: Capsule())
                        .accessibilityIdentifier("modelLabKeyboardDone")
                }
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.labGroup) {
                Text(claude.capLine)
                    .font(Theme.Typography.labBody)
                    .foregroundStyle(Theme.Palette.softText)
                CapBar(share: claude.capShare, tone: claude.capTone)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(claude.capAccessibilityText)
            .accessibilityIdentifier("capSummary")
            if let error = claude.capsError {
                Text(error)
                    .font(Theme.Typography.labMeta)
                    .foregroundStyle(Theme.Palette.statusAmber)
            }
            Text("Runs that could exceed a cap are blocked before they are sent.")
                .font(Theme.Typography.labMeta)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            Text(claude.outputCapText)
                .font(Theme.Typography.labMeta)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func capField(
        _ label: String,
        text: String,
        field: LabField,
        identifier: String,
        onChange: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.labGroup) {
            Text(label)
                .font(Theme.Typography.labMeta)
                .foregroundStyle(Theme.Palette.mutedText)
            HStack(spacing: Theme.Spacing.labGroup) {
                Text("$")
                    .font(Theme.Typography.labField)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .accessibilityHidden(true)
                TextField(label, text: Binding(get: { text }, set: onChange))
                    .font(Theme.Typography.labField)
                    .foregroundStyle(Theme.Palette.text)
                    .keyboardType(.decimalPad)
                    .focused(focus, equals: field)
                    .accessibilityLabel("\(label) limit in dollars")
                    .accessibilityIdentifier(identifier)
            }
            .padding(.horizontal, Theme.Spacing.labFieldHorizontal)
            .frame(minHeight: Theme.Size.minTouchTarget)
            .background(Theme.Palette.innerCard, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                    .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A 6 pt bar: accent, amber from 80%, red at 100%.
private struct CapBar: View {
    let share: Double
    let tone: ClaudeLabViewModel.CapTone

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.cardBorder)
                Capsule().fill(color).frame(width: proxy.size.width * share)
            }
        }
        .frame(height: Theme.Size.labCapBar)
    }

    private var color: Color {
        switch tone {
        case .normal: Theme.Palette.accent
        case .warning: Theme.Palette.statusAmber
        case .over: Theme.Palette.statusRed
        }
    }
}

/// "What would this cost?": your own average runs at today's prices, per Claude model.
struct ProjectionCard: View {
    let claude: ClaudeLabViewModel

    var body: some View {
        LabCard {
            Text("What would this cost?")
                .font(Theme.Typography.labPill)
                .foregroundStyle(Theme.Palette.text)
                .accessibilityAddTraits(.isHeader)
            Stepper(
                "Plans a month: \(claude.settings.scenario.plansPerMonth)",
                value: Binding(
                    get: { claude.settings.scenario.plansPerMonth },
                    set: { plans in Task { await claude.setScenario(plans: plans, notes: claude.settings.scenario.notesPerMonth) } }
                ),
                in: 0...20
            )
            .font(Theme.Typography.labBody)
            .foregroundStyle(Theme.Palette.softText)
            .accessibilityIdentifier("projectionPlans")
            Stepper(
                "Notes a month: \(claude.settings.scenario.notesPerMonth)",
                value: Binding(
                    get: { claude.settings.scenario.notesPerMonth },
                    set: { notes in Task { await claude.setScenario(plans: claude.settings.scenario.plansPerMonth, notes: notes) } }
                ),
                in: 0...100,
                step: 5
            )
            .font(Theme.Typography.labBody)
            .foregroundStyle(Theme.Palette.softText)
            .accessibilityIdentifier("projectionNotes")
            if let rows = claude.projection {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: Theme.Spacing.labGroup) {
                        HStack(spacing: Theme.Spacing.labPills) {
                            Text(row.model.displayName)
                                .font(Theme.Typography.labBody)
                                .foregroundStyle(Theme.Palette.text)
                            Spacer(minLength: Theme.Spacing.labPills)
                            Text(claude.monthlyLine(row))
                                .font(Theme.Typography.labRowValue)
                                .foregroundStyle(Theme.Palette.softText)
                        }
                        Text(claude.projectionLine(row))
                            .font(Theme.Typography.labMeta)
                            .foregroundStyle(Theme.Palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("projectionRow-\(row.model.rawValue)")
                }
            } else {
                Text(SpendGate.priceTableText)
                    .font(Theme.Typography.labMeta)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
            Text("Based on your own runs. Assumes no caching.")
                .font(Theme.Typography.labMeta)
                .foregroundStyle(Theme.Palette.mutedText)
        }
    }
}

/// Shown before the first Claude run, until "Allow".
struct ConsentSheet: View {
    let claude: ClaudeLabViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.labBlocks) {
                Text("Send summaries to Anthropic?")
                    .font(Theme.Typography.labTitle)
                    .foregroundStyle(Theme.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    "Running a Claude model sends the prompt text to Anthropic over the internet. The prompt contains workout and "
                        + "recovery summaries only: no routes, no names and no date of birth. Apple's on-device and Private Cloud "
                        + "Compute models are not affected."
                )
                .font(Theme.Typography.labBody)
                .foregroundStyle(Theme.Palette.softText)
                .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: Theme.Spacing.labPills) {
                    Button("Allow") { Task { await claude.allow() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("consentAllow")
                    Button("Not now") { claude.decline() }
                        .buttonStyle(OutlineButtonStyle())
                        .accessibilityIdentifier("consentNotNow")
                }
            }
            .padding(Theme.Spacing.labSide)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}
#endif
