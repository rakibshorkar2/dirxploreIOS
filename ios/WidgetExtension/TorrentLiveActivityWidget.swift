import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct TorrentLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TorrentActivityAttributes.self) { context in
            TorrentLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: torrentIcon(status: context.state.status,
                                                 completed: context.state.isCompleted))
                        .foregroundColor(torrentColor(status: context.state.status,
                                                      completed: context.state.isCompleted))
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isCompleted {
                        Text("Done")
                            .font(.title2).fontWeight(.bold).foregroundColor(.green)
                    } else {
                        Text("\(Int(context.state.progress * 100))%")
                            .font(.title2).fontWeight(.bold).foregroundColor(.white)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.torrentName)
                        .font(.caption).fontWeight(.medium).lineLimit(1).foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.isCompleted {
                        VStack(spacing: 4) {
                            ProgressView(value: context.state.progress)
                                .tint(.blue)
                            HStack {
                                Label(context.state.downloadSpeed, systemImage: "arrow.down.circle")
                                    .font(.caption2).foregroundColor(.green)
                                Spacer()
                                Text(context.state.eta).font(.caption2).foregroundColor(.secondary)
                                Spacer()
                                Label(context.state.uploadSpeed, systemImage: "arrow.up.circle")
                                    .font(.caption2).foregroundColor(.orange)
                            }
                            Text("\(context.state.downloadedSize) / \(context.state.totalSize)")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    } else {
                        Label("Torrent Complete", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundColor(.green)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isCompleted
                      ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundColor(context.state.isCompleted ? .green : .blue)
            } compactTrailing: {
                if context.state.isCompleted {
                    Text("Done").font(.caption).fontWeight(.medium).foregroundColor(.green)
                } else {
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.caption).fontWeight(.medium).monospacedDigit().foregroundColor(.white)
                        .contentTransition(.numericText())
                }
            } minimal: {
                Image(systemName: context.state.isCompleted
                      ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundColor(context.state.isCompleted ? .green : .blue)
            }
        }
    }

    private func torrentIcon(status: String, completed: Bool) -> String {
        if completed { return "checkmark.circle.fill" }
        switch status.lowercased() {
        case "downloading": return "arrow.down.circle.fill"
        case "paused": return "pause.circle.fill"
        case "seeding": return "arrow.up.circle.fill"
        case "error", "failed": return "exclamationmark.circle.fill"
        case "checking": return "magnifyingglass.circle.fill"
        default: return "arrow.down.circle"
        }
    }

    private func torrentColor(status: String, completed: Bool) -> Color {
        if completed { return .green }
        switch status.lowercased() {
        case "downloading": return .blue
        case "paused": return .orange
        case "seeding": return .teal
        case "error", "failed": return .red
        case "checking": return .gray
        default: return .blue
        }
    }
}

@available(iOS 16.1, *)
private struct TorrentLockScreenView: View {
    let context: ActivityViewContext<TorrentActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: torrentIcon())
                        .foregroundColor(torrentColor())
                    Text(context.state.torrentName)
                        .font(.headline).lineLimit(1)
                }
                if context.state.isCompleted {
                    Label("Download Complete", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundColor(.green)
                } else {
                    HStack(spacing: 8) {
                        Label(context.state.downloadSpeed, systemImage: "arrow.down.circle")
                            .font(.caption).foregroundColor(.green)
                        Text("\u{2022}").foregroundColor(.secondary)
                        Label(context.state.uploadSpeed, systemImage: "arrow.up.circle")
                            .font(.caption).foregroundColor(.orange)
                        Text("\u{2022}").foregroundColor(.secondary)
                        Text(context.state.status).font(.caption).foregroundColor(.secondary)
                    }
                    HStack(spacing: 8) {
                        Label("\(context.state.seeds)", systemImage: "arrow.up.to.line")
                            .font(.caption2).foregroundColor(.green)
                        Label("\(context.state.peers)", systemImage: "arrow.down.to.line")
                            .font(.caption2).foregroundColor(.secondary)
                        Text(context.state.eta).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(context.state.isCompleted ? "Done" : "\(Int(context.state.progress * 100))%")
                    .font(.title2).fontWeight(.bold)
                Text("\(context.state.downloadedSize) / \(context.state.totalSize)")
                    .font(.caption2).foregroundColor(.secondary)
                if !context.state.isCompleted {
                    ProgressView(value: context.state.progress)
                        .tint(.blue)
                        .frame(width: 80)
                }
            }
        }
        .padding()
        .activityBackgroundTint(.black.opacity(0.2))
        .activitySystemActionForegroundColor(.blue)
    }

    private func torrentIcon() -> String {
        if context.state.isCompleted { return "checkmark.circle.fill" }
        switch context.state.status.lowercased() {
        case "downloading": return "arrow.down.circle.fill"
        case "paused": return "pause.circle.fill"
        case "seeding": return "arrow.up.circle.fill"
        case "error", "failed": return "exclamationmark.circle.fill"
        case "checking": return "magnifyingglass.circle.fill"
        default: return "arrow.down.circle"
        }
    }

    private func torrentColor() -> Color {
        if context.state.isCompleted { return .green }
        switch context.state.status.lowercased() {
        case "downloading": return .blue
        case "paused": return .orange
        case "seeding": return .teal
        case "error", "failed": return .red
        case "checking": return .gray
        default: return .blue
        }
    }
}
