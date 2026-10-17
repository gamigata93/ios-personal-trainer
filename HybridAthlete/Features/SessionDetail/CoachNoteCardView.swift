import SwiftUI
import Domain
import Application

/// The coach's note on a completed session: the note in four labeled parts with
/// its source, or what is happening instead (writing, waiting for an unlock,
/// the write button for an older session, or a failure with Try again).
struct CoachNoteCardView: View {
    let viewModel: SessionDetailViewModel

    @State private var confirmsRegenerate = false
    #if DEBUG
    /// The facts shown in the DEBUG sheet.
    @State private var shownFacts: String?
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.coachNoteGap) {
            HStack {
                Text("Coach's note")
                    .font(Theme.Typography.coachCaption)
                    .tracking(Theme.Typography.captionTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Palette.accent)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                overflow
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.coachNotePadding)
        .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coachNoteCard")
        .confirmationDialog("Replace this note?", isPresented: $confirmsRegenerate, titleVisibility: .visible) {
            Button("Regenerate", role: .destructive) { viewModel.regenerate() }
                .accessibilityIdentifier("coachNoteRegenerateConfirm")
            Button("Cancel", role: .cancel) {}
        }
        #if DEBUG
        .sheet(item: Binding(get: { shownFacts.map(FactsText.init) }, set: { shownFacts = $0?.text })) { facts in
            ScrollView {
                Text(facts.text)
                    .font(Theme.Typography.code)
                    .foregroundStyle(Theme.Palette.softText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.coachNotePadding)
                    .accessibilityIdentifier("coachNoteFactsText")
            }
            .background(Theme.Palette.background.ignoresSafeArea())
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.coachCard {
        case .hidden:
            EmptyView()
        case .generating:
            VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                SkeletonBlock(height: Theme.Size.Skeleton.coachHeadline)
                    .containerRelativeFrame(.horizontal) { width, _ in width * 0.6 }
                    .frame(maxWidth: .infinity, alignment: .leading)
                SkeletonBlock(height: Theme.Size.Skeleton.textLine)
                SkeletonBlock(height: Theme.Size.Skeleton.textLine)
                Text("Writing your note…")
                    .font(Theme.Typography.coachFooter)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .accessibilityIdentifier("coachNoteWriting")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
            .accessibilityIdentifier("coachNoteLoading")
        case .waitingForUnlock:
            Text("Unlock your phone to analyze this run.")
                .font(Theme.Typography.coachNext)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("coachNoteWaiting")
        case .write:
            Button("Write coach note") { viewModel.write() }
                .buttonStyle(OutlineButtonStyle(textColor: Theme.Palette.accent))
                .accessibilityIdentifier("coachNoteWrite")
        case .failed:
            VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                Text("Couldn't write the note.")
                    .font(Theme.Typography.coachNext)
                    .foregroundStyle(Theme.Palette.softText)
                    .accessibilityIdentifier("coachNoteFailed")
                Button("Try again") { viewModel.write() }
                    .buttonStyle(OutlineButtonStyle())
                    .accessibilityIdentifier("coachNoteTryAgain")
            }
        case .ready(let ready):
            ReadyNoteView(ready: ready) { viewModel.regenerate() }
        }
    }

    /// "⋯": Regenerate (with a confirmation), Copy note, and DEBUG copies.
    @ViewBuilder
    private var overflow: some View {
        if case .ready = viewModel.coachCard {
            Menu {
                Button("Regenerate", systemImage: "arrow.clockwise") { confirmsRegenerate = true }
                    .accessibilityIdentifier("coachNoteRegenerate")
                if let text = viewModel.noteText {
                    Button("Copy note", systemImage: "doc.on.doc") { Clipboard.copy(text) }
                }
                #if DEBUG
                debugItems
                #endif
            } label: {
                Image(systemName: "ellipsis")
                    .font(Theme.Typography.cardIconGlyph)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .frame(width: Theme.Size.minTouchTarget, height: Theme.Size.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Note options")
            .accessibilityIdentifier("coachNoteMenu")
        } else {
            #if DEBUG
            Menu { debugItems } label: {
                Image(systemName: "ladybug")
                    .font(Theme.Typography.cardIconGlyph)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .frame(width: Theme.Size.minTouchTarget, height: Theme.Size.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Debug menu")
            .accessibilityIdentifier("coachNoteMenu")
            #endif
        }
    }

    #if DEBUG
    @ViewBuilder
    private var debugItems: some View {
        if let facts = viewModel.factsText {
            Button("Copy facts", systemImage: "list.bullet.rectangle") { Clipboard.copy(facts) }
                .accessibilityIdentifier("coachNoteCopyFacts")
            Button("Show facts", systemImage: "text.alignleft") { shownFacts = facts }
                .accessibilityIdentifier("coachNoteShowFacts")
        }
        if let json = viewModel.analysisJSON {
            Button("Copy analysis JSON", systemImage: "chart.bar") { Clipboard.copy(json) }
        }
        if let json = viewModel.noteJSON {
            Button("Copy note JSON", systemImage: "curlybraces") { Clipboard.copy(json) }
        }
    }
    #endif
}

private struct ReadyNoteView: View {
    let ready: SessionDetailViewModel.ReadyNote
    let onUpdate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.coachNoteGap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.coachNoteGap) {
                Text(ready.note.headline)
                    .font(Theme.Typography.coachHeadline)
                    .foregroundStyle(Theme.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("coachNoteHeadline")
                section("How it went", ready.note.howItWent)
                section("Versus the plan", ready.note.versusPlan)
                section("The program", ready.note.programStatus)
                section("Next", ready.note.nextStep)
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(ready.footer)
                    if let fallback = ready.fallbackText { Text(fallback) }
                }
                .font(Theme.Typography.coachFooter)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("coachNoteFooter")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ready.spoken)
            .accessibilityIdentifier("coachNoteBody")
            if ready.isStale {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Button("Update note", action: onUpdate)
                        .buttonStyle(OutlineButtonStyle())
                        .accessibilityIdentifier("coachNoteUpdate")
                    Text("This run changed since the note was written.")
                        .font(Theme.Typography.coachFooter)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func section(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.coachSectionGap) {
            Text(label)
                .font(Theme.Typography.coachSectionLabel)
                .tracking(Theme.Typography.captionTracking)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.mutedText)
            Text(text)
                .font(Theme.Typography.coachBody)
                .lineSpacing(Theme.Typography.coachBodyLineSpacing)
                .foregroundStyle(Theme.Palette.noteText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("coachNoteSection-\(label)")
    }
}

#if DEBUG
/// The DEBUG facts sheet's item.
private struct FactsText: Identifiable {
    let text: String
    var id: String { text }
}
#endif
