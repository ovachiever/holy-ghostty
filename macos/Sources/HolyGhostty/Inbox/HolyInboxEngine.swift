import Foundation
#if os(macOS)
import AppKit
#endif

/// The pane's metronome. Polls every registered source on a cadence — 75s
/// while the panel is visible, 5min hidden so the unread badge cannot lie —
/// plus immediately on panel open, app foreground, and manual refresh. Polls
/// are serialized: a poll in flight absorbs every request that arrives during
/// it into exactly one follow-up.
@MainActor
final class HolyInboxEngine: ObservableObject {
    @Published private(set) var sections: [HolyInboxSection] = []
    @Published private(set) var footnotes: [String] = []
    @Published private(set) var badgeCount: Int = 0
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshedAt: Date?

    static let visiblePollInterval: TimeInterval = 75
    static let hiddenPollInterval: TimeInterval = 300

    private let sources: [any HolyInboxRowSource]
    private let focusedRepoSlugProvider: @Sendable () async -> String?
    private var panelVisible = false
    private var refreshTask: Task<Void, Never>?
    private var pendingRefreshRequested = false
    private var pollTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?

    /// `autostart: false` keeps tests in control of every poll; production
    /// starts polling at init so the badge is honest soon after launch.
    init(
        sources: [any HolyInboxRowSource],
        focusedRepoSlugProvider: @escaping @Sendable () async -> String? = { nil },
        autostart: Bool = true
    ) {
        self.sources = sources
        self.focusedRepoSlugProvider = focusedRepoSlugProvider

        if autostart {
            requestRefresh()
            schedulePoll()
            #if os(macOS)
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.requestRefresh()
                }
            }
            #endif
        }
    }

    deinit {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    nonisolated static func pollInterval(panelVisible: Bool) -> TimeInterval {
        panelVisible ? visiblePollInterval : hiddenPollInterval
    }

    nonisolated static func badgeCount(for sections: [HolyInboxSection]) -> Int {
        sections
            .filter(\.countsTowardBadge)
            .reduce(0) { total, section in
                total + section.rows.filter { !$0.isDegraded }.count
            }
    }

    func setPanelVisible(_ visible: Bool) {
        guard panelVisible != visible else { return }
        panelVisible = visible
        if visible {
            requestRefresh()
        }
        if pollTask != nil {
            schedulePoll()
        }
    }

    /// Serialized: at most one poll runs; requests during it coalesce into
    /// one follow-up poll.
    func requestRefresh() {
        guard refreshTask == nil else {
            pendingRefreshRequested = true
            return
        }

        isRefreshing = true
        refreshTask = Task { [weak self] in
            await self?.runRefresh()
            guard let self else { return }
            self.refreshTask = nil
            if self.pendingRefreshRequested {
                self.pendingRefreshRequested = false
                self.requestRefresh()
            } else {
                self.isRefreshing = false
            }
        }
    }

    /// Routes a row's acknowledge affordance to the source that owns its
    /// section, then re-polls so the row's disappearance is truth, not hope.
    func acknowledge(rowID: String, inSectionID sectionID: String) async {
        guard let section = sections.first(where: { $0.id == sectionID }),
              let source = sources.first(where: { $0.sourceID == section.sourceID }) else {
            return
        }
        await source.acknowledge(rowID: rowID)
        requestRefresh()
    }

    // MARK: - Internals

    private func runRefresh() async {
        let context = HolyInboxRefreshContext(
            focusedRepoSlug: await focusedRepoSlugProvider()
        )

        var assembled: [HolyInboxSection] = []
        var notes: [String] = []
        for source in sources {
            let snapshot = await source.refresh(context: context)
            assembled.append(contentsOf: snapshot.sections)
            if let footnote = snapshot.footnote {
                notes.append(footnote)
            }
        }

        sections = assembled
        footnotes = notes
        badgeCount = Self.badgeCount(for: assembled)
        lastRefreshedAt = .now
    }

    private func schedulePoll() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while true {
                guard let self, !Task.isCancelled else { return }
                let interval = Self.pollInterval(panelVisible: self.panelVisible)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                self.requestRefresh()
            }
        }
    }
}
