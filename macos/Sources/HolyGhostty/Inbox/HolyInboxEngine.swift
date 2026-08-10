import Foundation
#if os(macOS)
import AppKit
#endif

/// The pane's metronome. Polls every registered source on a cadence — 75s
/// while the panel is visible, 5min hidden so the unread badge cannot lie —
/// plus immediately on panel open, app foreground, and manual refresh.
///
/// Each source refreshes INDEPENDENTLY: a 30-second GitHub sweep must never
/// hold local manna rows hostage (mn-b2e2e9 — Erik watched the panel sit
/// empty for a minute after a session switch). Sections always render in
/// source REGISTRATION order regardless of completion order, and per-source
/// refreshes stay serialized: a request that lands while that source is in
/// flight coalesces into exactly one follow-up.
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
    private var pollTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?

    /// Per-source state, indexed by registration order — which is also the
    /// panel's section order. A slot stays nil until its source completes
    /// its first refresh; the panel simply doesn't show that source yet.
    private var snapshotsBySourceIndex: [HolyInboxSourceSnapshot?]
    private var runningSourceIndices: Set<Int> = []
    private var pendingSourceIndices: Set<Int> = []

    /// `autostart: false` keeps tests in control of every poll; production
    /// starts polling at init so the badge is honest soon after launch.
    init(
        sources: [any HolyInboxRowSource],
        focusedRepoSlugProvider: @escaping @Sendable () async -> String? = { nil },
        autostart: Bool = true
    ) {
        self.sources = sources
        self.focusedRepoSlugProvider = focusedRepoSlugProvider
        self.snapshotsBySourceIndex = Array(repeating: nil, count: sources.count)

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

    /// Refresh every source. Each proceeds independently; see
    /// `refreshSource(at:)` for the per-source serialization rule.
    func requestRefresh() {
        for index in sources.indices {
            refreshSource(at: index)
        }
    }

    /// Refresh exactly one source — the session-switch path: focus changed,
    /// so the manna board scope changed, and re-reading local files must not
    /// wait on (or trigger) a GitHub sweep.
    func requestRefresh(sourceID: String) {
        guard let index = sources.firstIndex(where: { $0.sourceID == sourceID }) else { return }
        refreshSource(at: index)
    }

    /// Routes a row's acknowledge affordance to the source that owns its
    /// section, then re-polls THAT source so the row's disappearance is
    /// truth, not hope — without dragging every other source along.
    func acknowledge(rowID: String, inSectionID sectionID: String) async {
        guard let section = sections.first(where: { $0.id == sectionID }),
              let source = sources.first(where: { $0.sourceID == section.sourceID }) else {
            return
        }
        await source.acknowledge(rowID: rowID)
        requestRefresh(sourceID: source.sourceID)
    }

    // MARK: - Internals

    private func refreshSource(at index: Int) {
        if runningSourceIndices.contains(index) {
            pendingSourceIndices.insert(index)
            return
        }
        runningSourceIndices.insert(index)
        isRefreshing = true

        let source = sources[index]
        Task { [weak self] in
            guard let self else { return }
            let context = HolyInboxRefreshContext(
                focusedRepoSlug: await self.focusedRepoSlugProvider()
            )
            let snapshot = await source.refresh(context: context)
            self.apply(snapshot, at: index)
            self.runningSourceIndices.remove(index)
            if self.pendingSourceIndices.remove(index) != nil {
                self.refreshSource(at: index)
            } else if self.runningSourceIndices.isEmpty {
                self.isRefreshing = false
            }
        }
    }

    private func apply(_ snapshot: HolyInboxSourceSnapshot, at index: Int) {
        snapshotsBySourceIndex[index] = snapshot
        let landed = snapshotsBySourceIndex.compactMap { $0 }
        sections = landed.flatMap(\.sections)
        footnotes = landed.compactMap(\.footnote)
        badgeCount = Self.badgeCount(for: sections)
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
