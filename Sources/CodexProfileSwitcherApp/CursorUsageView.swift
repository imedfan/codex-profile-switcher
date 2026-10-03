import SwiftUI

struct CursorUsageView: View {
    let snapshot: CursorUsageSnapshot?
    let teamName: String?
    let error: CursorUsageError?
    let isRefreshing: Bool
    let displayMode: LimitDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Cursor").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(teamName ?? "Current account")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let snapshot {
                usage(snapshot)
            } else if error == nil {
                Text(isRefreshing ? "Loading usage…" : "No usage data yet")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if let error {
                Text((snapshot == nil ? "" : "Last known usage · ") + (error.errorDescription ?? "Usage unavailable"))
                    .font(.system(size: 10))
                    .foregroundStyle(snapshot == nil ? .secondary : Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(width: 290, alignment: .leading)
    }

    private func usage(_ snapshot: CursorUsageSnapshot) -> some View {
        VStack(spacing: 2) {
            UsageRow(
                label: "Cm", percent: snapshot.cursorModelsUsedPercent,
                resetAt: snapshot.periodEnd, isHighlighted: true, displayMode: displayMode)
                .help("Cursor Models")
            UsageRow(
                label: "Om", percent: snapshot.otherModelsUsedPercent,
                resetAt: nil, isHighlighted: true, displayMode: displayMode)
                .help("Other Models")
            if let grokBotUsage = snapshot.grokBotUsage {
                UsageRow(
                    label: "Gb", percent: grokBotUsage.usedPercent,
                    resetAt: grokBotUsage.periodEnd, isHighlighted: true, displayMode: displayMode)
                    .help("Grok Bot weekly usage")
            }
        }
    }
}
