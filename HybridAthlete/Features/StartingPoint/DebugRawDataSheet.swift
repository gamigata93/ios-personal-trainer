#if DEBUG
import SwiftUI
import Domain
import Application

/// DEBUG only: the last live read as JSON, with copy and share. Not in release builds.
struct DebugRawDataSheet: View {
    let snapshot: HealthSnapshot?
    @Environment(\.dismiss) private var dismiss
    @State private var showsCopied = false

    private var json: String? {
        snapshot.map(HealthSnapshotJSON.string(from:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.cardStack) {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.titleToCaption) {
                    Text("Raw data")
                        .font(Theme.Typography.blockTitle)
                        .foregroundStyle(Theme.Palette.text)
                    Text("Exactly what the last read returned. Debug builds only.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.mutedText)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(TextButtonStyle())
            }

            if let json {
                ScrollView([.vertical, .horizontal]) {
                    Text(json)
                        .font(Theme.Typography.code)
                        .foregroundStyle(Theme.Palette.softText)
                        .textSelection(.enabled)
                        .fixedSize()
                        .padding(Theme.Spacing.codePadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.Palette.innerCard, in: RoundedRectangle(cornerRadius: Theme.Radius.codeBlock, style: .continuous))
                .accessibilityIdentifier("debug.json")

                HStack(spacing: Theme.Spacing.betweenButtons) {
                    Button(showsCopied ? "Copied" : "Copy JSON") {
                        Clipboard.copy(json)
                        showsCopied = true
                        Task {
                            try? await Task.sleep(for: Theme.Motion.copiedConfirmation)
                            showsCopied = false
                        }
                    }
                    .buttonStyle(OutlineButtonStyle())
                    ShareLink(item: json) { Text("Share") }
                        .buttonStyle(OutlineButtonStyle())
                }
            } else {
                Text("No live read has finished yet. Pull down on the dashboard to refresh.")
                    .font(Theme.Typography.noticeBody)
                    .foregroundStyle(Theme.Palette.mutedText)
                Spacer()
            }
        }
        .padding(Theme.Spacing.screenSide)
        .background(Theme.Palette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
#endif
