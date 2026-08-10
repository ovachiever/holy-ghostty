import Foundation
import Testing
@testable import Ghostty

// The engine is the pane's metronome: it serializes polls (a poll in flight
// absorbs every request that arrives during it), assembles sections in source
// registration order, and computes the unread badge that must not lie —
// degraded rows and secondary sections never count.
struct HolyInboxEngineTests {
    // MARK: - Fakes

    /// Returns a fixed snapshot; counts refreshes.
    private final class StaticSource: HolyInboxRowSource, @unchecked Sendable {
        let sourceID: String
        private let snapshot: HolyInboxSourceSnapshot
        private let lock = NSLock()
        private var _refreshCount = 0
        private var _acknowledgedRowIDs: [String] = []

        var refreshCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return _refreshCount
        }

        var acknowledgedRowIDs: [String] {
            lock.lock()
            defer { lock.unlock() }
            return _acknowledgedRowIDs
        }

        init(sourceID: String, snapshot: HolyInboxSourceSnapshot) {
            self.sourceID = sourceID
            self.snapshot = snapshot
        }

        func refresh(context: HolyInboxRefreshContext) async -> HolyInboxSourceSnapshot {
            lock.lock()
            _refreshCount += 1
            lock.unlock()
            return snapshot
        }

        func acknowledge(rowID: String) async {
            lock.lock()
            _acknowledgedRowIDs.append(rowID)
            lock.unlock()
        }
    }

    /// Blocks inside refresh until the test releases the gate.
    private final class GatedSource: HolyInboxRowSource, @unchecked Sendable {
        let sourceID = "gated"
        private let snapshot: HolyInboxSourceSnapshot
        private let lock = NSLock()
        private var _refreshCount = 0
        private var continuations: [CheckedContinuation<Void, Never>] = []

        init(snapshot: HolyInboxSourceSnapshot = .empty) {
            self.snapshot = snapshot
        }

        var refreshCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return _refreshCount
        }

        func refresh(context: HolyInboxRefreshContext) async -> HolyInboxSourceSnapshot {
            lock.lock()
            _refreshCount += 1
            lock.unlock()
            await withCheckedContinuation { continuation in
                lock.lock()
                continuations.append(continuation)
                lock.unlock()
            }
            return snapshot
        }

        func release() {
            lock.lock()
            let waiting = continuations
            continuations = []
            lock.unlock()
            waiting.forEach { $0.resume() }
        }
    }

    private func section(
        id: String,
        sourceID: String,
        rows: [HolyInboxRow],
        countsTowardBadge: Bool = false
    ) -> HolyInboxSection {
        HolyInboxSection(
            id: id,
            sourceID: sourceID,
            title: id,
            rows: rows,
            countsTowardBadge: countsTowardBadge
        )
    }

    private func row(_ id: String, isDegraded: Bool = false) -> HolyInboxRow {
        HolyInboxRow(id: id, title: id, isDegraded: isDegraded)
    }

    @discardableResult
    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    // MARK: - Cadence

    @Test func pollCadenceIs75VisibleAnd300Hidden() {
        #expect(HolyInboxEngine.pollInterval(panelVisible: true) == 75)
        #expect(HolyInboxEngine.pollInterval(panelVisible: false) == 300)
    }

    // MARK: - Serialization

    @Test @MainActor func aPollInFlightAbsorbsEveryRequestIntoOneFollowUp() async {
        let source = GatedSource()
        let engine = HolyInboxEngine(sources: [source], autostart: false)

        engine.requestRefresh()
        #expect(await waitUntil { source.refreshCount == 1 })

        // Three requests land while the poll is in flight.
        engine.requestRefresh()
        engine.requestRefresh()
        engine.requestRefresh()

        source.release()
        // Exactly one absorbed follow-up begins.
        #expect(await waitUntil { source.refreshCount == 2 })
        source.release()
        #expect(await waitUntil { !engine.isRefreshing })

        // Nothing further was queued.
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(source.refreshCount == 2)
    }

    // MARK: - Assembly and badge

    @Test @MainActor func sectionsAssembleInSourceRegistrationOrder() async {
        let alerts = StaticSource(
            sourceID: "alerts",
            snapshot: HolyInboxSourceSnapshot(sections: [
                section(id: "alerts", sourceID: "alerts", rows: [row("alerts:1")], countsTowardBadge: true),
            ])
        )
        let github = StaticSource(
            sourceID: "gh",
            snapshot: HolyInboxSourceSnapshot(
                sections: [
                    section(id: "gh.review", sourceID: "gh", rows: [row("gh:a"), row("gh:b")], countsTowardBadge: true),
                    section(id: "gh.authored", sourceID: "gh", rows: [row("gh:c")]),
                ],
                footnote: "this session: 2 lessons"
            )
        )

        let engine = HolyInboxEngine(sources: [alerts, github], autostart: false)
        engine.requestRefresh()
        #expect(await waitUntil { !engine.isRefreshing && engine.lastRefreshedAt != nil })

        #expect(engine.sections.map(\.id) == ["alerts", "gh.review", "gh.authored"])
        #expect(engine.footnotes == ["this session: 2 lessons"])
        // Badge: 1 alert + 2 review rows; authored section never counts.
        #expect(engine.badgeCount == 3)
    }

    @Test func badgeCountsOnlyBadgeSectionsAndNeverDegradedRows() {
        let sections = [
            section(id: "alerts", sourceID: "alerts", rows: [row("alerts:1"), row("alerts:2")], countsTowardBadge: true),
            section(
                id: "gh.review",
                sourceID: "gh",
                rows: [row("gh:a"), row("gh:degraded", isDegraded: true)],
                countsTowardBadge: true
            ),
            section(id: "gh.authored", sourceID: "gh", rows: [row("gh:c")]),
        ]
        #expect(HolyInboxEngine.badgeCount(for: sections) == 3)
    }

    // MARK: - Per-source independence (mn-b2e2e9)

    @Test @MainActor func aSlowSourceNeverDelaysAFastOnesSections() async {
        let slow = GatedSource(snapshot: HolyInboxSourceSnapshot(sections: [
            section(id: "gh.review", sourceID: "gated", rows: [row("gh:a")], countsTowardBadge: true),
        ]))
        let fast = StaticSource(
            sourceID: "manna",
            snapshot: HolyInboxSourceSnapshot(sections: [
                section(id: "manna", sourceID: "manna", rows: [row("mn:1")], countsTowardBadge: true),
            ])
        )
        let engine = HolyInboxEngine(sources: [slow, fast], autostart: false)
        engine.requestRefresh()

        // The fast source's rows land while the slow one is still in flight.
        #expect(await waitUntil { engine.sections.map(\.id) == ["manna"] })
        #expect(engine.isRefreshing)
        #expect(engine.badgeCount == 1)

        slow.release()
        // The slow source's sections take their REGISTERED slot, first in
        // the panel, despite finishing last.
        #expect(await waitUntil { engine.sections.map(\.id) == ["gh.review", "manna"] })
        #expect(await waitUntil { !engine.isRefreshing })
        #expect(engine.badgeCount == 2)
    }

    @Test @MainActor func targetedRefreshTouchesOnlyThatSource() async {
        let github = StaticSource(sourceID: "gh", snapshot: .empty)
        let manna = StaticSource(
            sourceID: "manna",
            snapshot: HolyInboxSourceSnapshot(sections: [
                section(id: "manna", sourceID: "manna", rows: [row("mn:1")]),
            ])
        )
        let engine = HolyInboxEngine(sources: [github, manna], autostart: false)

        engine.requestRefresh(sourceID: "manna")
        #expect(await waitUntil { manna.refreshCount == 1 && engine.sections.map(\.id) == ["manna"] })

        // The other source was never touched — a session switch must not
        // fire a 30-second GitHub sweep.
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(github.refreshCount == 0)
    }

    // MARK: - Acknowledge routing

    @Test @MainActor func acknowledgeRoutesToTheOwningSourceAndRefreshes() async {
        let alerts = StaticSource(
            sourceID: "alerts",
            snapshot: HolyInboxSourceSnapshot(sections: [
                section(id: "alerts", sourceID: "alerts", rows: [row("alerts:7")], countsTowardBadge: true),
            ])
        )
        let github = StaticSource(sourceID: "gh", snapshot: .empty)

        let engine = HolyInboxEngine(sources: [alerts, github], autostart: false)
        engine.requestRefresh()
        #expect(await waitUntil { engine.lastRefreshedAt != nil })

        await engine.acknowledge(rowID: "alerts:7", inSectionID: "alerts")
        #expect(alerts.acknowledgedRowIDs == ["alerts:7"])
        #expect(github.acknowledgedRowIDs.isEmpty)

        // Acknowledge re-polls so the row's disappearance is truth, not hope.
        #expect(await waitUntil { alerts.refreshCount >= 2 })
    }

    // MARK: - Visibility

    @Test @MainActor func panelBecomingVisibleTriggersImmediateRefresh() async {
        let source = StaticSource(sourceID: "gh", snapshot: .empty)
        let engine = HolyInboxEngine(sources: [source], autostart: false)
        #expect(source.refreshCount == 0)

        engine.setPanelVisible(true)
        #expect(await waitUntil { source.refreshCount == 1 })

        // Hiding does not poll; the next cadence tick handles it.
        engine.setPanelVisible(false)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(source.refreshCount == 1)
    }
}
