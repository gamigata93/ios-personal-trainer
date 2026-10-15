import SwiftUI
import Domain

/// Race day, distance, climbing and training days. Nothing is chosen for the user.
struct RaceSetupView: View {
    @Bindable var viewModel: RaceSetupViewModel
    @State private var showsDatePicker = false
    @State private var pickedDate = Date(timeIntervalSinceReferenceDate: 0)
    @FocusState private var focus: RaceSetupField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.formRows) {
                header
                raceDayField
                HStack(alignment: .top, spacing: Theme.Spacing.betweenButtons) {
                    numberField("Distance (km)", text: $viewModel.distanceText, prompt: viewModel.distancePlaceholder, field: .distance, decimal: true)
                    numberField("Elevation gain (m)", text: $viewModel.elevationText, prompt: "0", field: .elevation, decimal: false)
                }
                days
                buildButton
            }
            .padding(.horizontal, Theme.Spacing.screenSide)
            .padding(.top, Theme.Spacing.compact)
            .padding(.bottom, Theme.Spacing.screenBottom)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.Palette.background.ignoresSafeArea())
        .onChange(of: focus) { previous, _ in
            if let previous { viewModel.markTouched(previous) }
        }
        .sheet(isPresented: $showsDatePicker) { datePicker }
        .toolbar {
            // Number pads have no return key.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
                    .accessibilityIdentifier("raceSetup.keyboardDone")
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.titleToSubtitle) {
            Button {
                viewModel.back()
            } label: {
                Image(systemName: "chevron.left")
                    .font(Theme.Typography.cardIconGlyph)
                    .foregroundStyle(Theme.Palette.text)
                    .frame(width: Theme.Size.minTouchTarget, height: Theme.Size.minTouchTarget)
                    .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.smallTile, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("raceSetup.back")
            .padding(.bottom, Theme.Spacing.compact)

            if let plan = viewModel.prefilledFrom {
                HStack(spacing: Theme.Spacing.tight) {
                    Text(plan).font(Theme.Typography.chip).foregroundStyle(Theme.Palette.accent)
                    Text("Prefilled from your plan").font(Theme.Typography.chip).foregroundStyle(Theme.Palette.softText)
                }
                .padding(.horizontal, Theme.Spacing.chipHorizontal)
                .padding(.vertical, Theme.Spacing.chipVertical)
                .background(Theme.Palette.accentSoft, in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("raceSetup.prefilled")
            }

            Text(viewModel.title)
                .font(Theme.Typography.compactScreenTitle)
                .foregroundStyle(Theme.Palette.text)
                .accessibilityAddTraits(.isHeader)
            Text(viewModel.subtitle)
                .font(Theme.Typography.subtitle)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Fields

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.fieldLabel)
            .foregroundStyle(Theme.Palette.mutedText)
            .accessibilityHidden(true)
    }

    private func fieldBackground(isProblem: Bool) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
            .fill(Theme.Palette.card)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                    .strokeBorder(isProblem ? Theme.Palette.statusRed : Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
            }
    }

    private func showsProblem(_ field: RaceSetupField) -> Bool {
        guard let message = viewModel.visibleProblem else { return false }
        return viewModel.problems.first { $0.message == message }?.field == field
    }

    private var raceDayField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.labelToField) {
            label("Race day")
            Button {
                pickedDate = viewModel.pickerDate
                showsDatePicker = true
            } label: {
                HStack {
                    Text(viewModel.raceDayText)
                        .font(Theme.Typography.fieldText)
                        .foregroundStyle(viewModel.hasRaceDay ? Theme.Palette.text : Theme.Palette.mutedText)
                    Spacer()
                    Image(systemName: "calendar")
                        .foregroundStyle(Theme.Palette.softText)
                }
                .padding(.vertical, Theme.Spacing.fieldVertical)
                .padding(.horizontal, Theme.Spacing.fieldHorizontal)
                .frame(minHeight: Theme.Size.minTouchTarget)
                .background(fieldBackground(isProblem: showsProblem(.raceDay)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Race day")
            .accessibilityValue(viewModel.raceDayText)
            .accessibilityIdentifier("raceSetup.raceDay")
        }
    }

    private func numberField(
        _ title: String,
        text: Binding<String>,
        prompt: String,
        field: RaceSetupField,
        decimal: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.labelToField) {
            label(title)
            TextField(title, text: text, prompt: Text(prompt).foregroundStyle(Theme.Palette.mutedText))
                .font(Theme.Typography.fieldText)
                .foregroundStyle(Theme.Palette.text)
                .tint(Theme.Palette.accent)
                #if os(iOS)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                #endif
                .focused($focus, equals: field)
                .padding(.vertical, Theme.Spacing.fieldVertical)
                .padding(.horizontal, Theme.Spacing.fieldHorizontal)
                .frame(minHeight: Theme.Size.minTouchTarget)
                .background(fieldBackground(isProblem: showsProblem(field)))
                .accessibilityLabel(title)
                .accessibilityIdentifier(field == .distance ? "raceSetup.distance" : "raceSetup.elevation")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Days

    private var days: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.labelToField) {
            HStack {
                label("Which days can you train?")
                Spacer()
                Text(viewModel.dayCountText)
                    .font(Theme.Typography.fieldLabel)
                    .foregroundStyle(viewModel.hasEnoughDays ? Theme.Palette.accent : Theme.Palette.mutedText)
                    .accessibilityIdentifier("raceSetup.dayCount")
            }
            HStack(spacing: Theme.Spacing.dayPills) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    dayPill(day)
                }
            }
            if let hint = viewModel.runsHint {
                Text(hint)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.softText)
                    .accessibilityIdentifier("raceSetup.runsHint")
            }
        }
    }

    private func dayPill(_ day: Weekday) -> some View {
        let selected = viewModel.isSelected(day)
        return Button {
            focus = nil
            viewModel.toggle(day)
        } label: {
            Text(day.letter)
                .font(Theme.Typography.dayLetter)
                .foregroundStyle(selected ? Theme.Palette.onAccent : Theme.Palette.mutedText)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.dayPillHeight)
                .background(selected ? Theme.Palette.accent : Theme.Palette.card, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(selected ? .clear : Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? "\(day.name), selected" : day.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("raceSetup.day.\(day.rawValue)")
    }

    // MARK: Build

    private var buildButton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            if let problem = viewModel.visibleProblem {
                Text(problem)
                    .font(Theme.Typography.fieldIssue)
                    .foregroundStyle(Theme.Palette.statusRed)
                    .accessibilityIdentifier("raceSetup.problem")
            }
            // Stays tappable while invalid so a tap can reveal what is missing.
            Button("Build my plan") {
                focus = nil
                viewModel.build()
            }
            .buttonStyle(PrimaryButtonStyle())
            .opacity(viewModel.canBuild ? 1 : Theme.Opacity.disabledButton)
            .accessibilityHint(viewModel.canBuild ? "" : "Some details are still missing")
            .accessibilityIdentifier("raceSetup.build")
        }
        .padding(.top, Theme.Spacing.compact)
    }

    // MARK: Date picker

    private var datePicker: some View {
        VStack(spacing: Theme.Spacing.cardStack) {
            HStack {
                Text("Race day")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.Palette.text)
                Spacer()
                Button("Done") {
                    viewModel.setRaceDay(pickedDate)
                    showsDatePicker = false
                }
                .buttonStyle(TextButtonStyle())
                .accessibilityIdentifier("raceSetup.datePickerDone")
            }
            DatePicker("Race day", selection: $pickedDate, in: viewModel.pickerRange, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Theme.Palette.accent)
                .labelsHidden()
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.screenSide)
        .background(Theme.Palette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

#if DEBUG
#Preview("Custom") {
    RaceSetupView(viewModel: CompositionRoot.previewRaceSetupViewModel())
}
#endif
