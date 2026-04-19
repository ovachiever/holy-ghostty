import SwiftUI

struct HolySessionTimelineSection: View {
    let sessionID: UUID
    let refreshID: String
    let title: String
    let limit: Int

    @State private var events: [HolySessionTimelineEvent] = []
    @State private var loadErrorMessage: String?

    init(
        sessionID: UUID,
        refreshID: String,
        title: String = "Timeline",
        limit: Int = 8
    ) {
        self.sessionID = sessionID
        self.refreshID = refreshID
        self.title = title
        self.limit = limit
    }

    var body: some View {
        Group {
            if !events.isEmpty || loadErrorMessage != nil {
                VStack(alignment: .leading, spacing: 8) {
                    timelineSectionLabel(title)

                    if let loadErrorMessage {
                        Text(loadErrorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    } else {
                        ForEach(events) { event in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(event.badgeText)
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(tint(for: event))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(tint(for: event).opacity(0.12))
                                        )

                                    Text(event.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(HolyGhosttyTheme.textPrimary)
                                        .lineLimit(2)

                                    Spacer(minLength: 0)

                                    Text(event.occurredAt, format: .dateTime.hour().minute())
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                                }

                                if let detail = event.detail {
                                    Text(detail)
                                        .font(.system(size: 10))
                                        .foregroundStyle(HolyGhosttyTheme.textSecondary)
                                        .lineLimit(3)
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(tint(for: event).opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(tint(for: event).opacity(0.14), lineWidth: 0.5)
                            )
                        }

                        if events.count >= limit {
                            Text("Showing latest \(limit) events.")
                                .font(.system(size: 10))
                                .foregroundStyle(HolyGhosttyTheme.textTertiary)
                        }
                    }
                }
            }
        }
        .task(id: refreshID) {
            await loadEvents()
        }
    }

    private func loadEvents() async {
        do {
            let loadedEvents = try await Task.detached(priority: .userInitiated) {
                try HolySessionEventRepository.recentEvents(for: sessionID, limit: limit)
            }.value

            events = loadedEvents
            loadErrorMessage = nil
        } catch {
            events = []
            loadErrorMessage = "Timeline unavailable: \(error.localizedDescription)"
        }
    }

    private func tint(for event: HolySessionTimelineEvent) -> Color {
        switch event.attention {
        case .failure?:
            return HolyGhosttyTheme.danger
        case .needsInput?:
            return HolyGhosttyTheme.warning
        case .conflict?:
            return HolyGhosttyTheme.danger
        case .done?:
            return HolyGhosttyTheme.success
        case .watch?:
            return HolyGhosttyTheme.accent
        case .none?, nil:
            break
        }

        switch event.eventType {
        case .recovered, .archived:
            return HolyGhosttyTheme.warning
        case .artifactDetected, .runtimeUpdated:
            return HolyGhosttyTheme.accent
        case .created, .restored, .relaunched:
            return HolyGhosttyTheme.success
        case .selected, .imported:
            return HolyGhosttyTheme.textTertiary
        }
    }

    private func timelineSectionLabel(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.1)
            .foregroundStyle(HolyGhosttyTheme.textTertiary)
    }
}
