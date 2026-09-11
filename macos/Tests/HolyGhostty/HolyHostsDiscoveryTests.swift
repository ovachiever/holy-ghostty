import Foundation
import Testing
@testable import Ghostty

private actor HostsDiscoverySnapshots {
    struct Entry {
        let sessions: [HolyDiscoveredTmuxSession]
        let progress: HolyHostsDiscoveryProgress
    }
    private(set) var entries: [Entry] = []

    func append(_ sessions: [HolyDiscoveredTmuxSession], _ progress: HolyHostsDiscoveryProgress) {
        entries.append(.init(sessions: sessions, progress: progress))
    }
}

struct HolyHostsDiscoveryTests {
    private typealias Reply = HolyRemoteTmuxDiscoveryService.HostsTestReply

    private func row(_ name: String, runtime: String = "", cwd: String = "/Users/erik/Custom-Coding") -> String {
        [name, "0", "1", "", runtime, "", cwd, "", "", ""].joined(separator: "\u{1F}")
    }

    private var studioInventory: String {
        let workers = (1...6).map {
            row("holy-worker-vsi-\($0)", cwd: "/Users/erik/Custom-Coding/versova-supply-intelligence")
        }
        let placeholders = (1...5).map { row("holy-shell-\($0)") }
        let adopted = [row("adopted-research", runtime: "future-runtime")]
        let agents = (1...31).map { index in
            let runtime = index == 31 ? "shell" : (index.isMultiple(of: 2) ? "codex" : "claude")
            return row("holy-worker-agent-\(index)", runtime: runtime)
        }
        return (workers + placeholders + adopted + agents).joined(separator: "\n")
    }

    @Test func all43SessionsRenderIncludingSixUnclassifiedVSIWorkers() async throws {
        let fixture: [String: Reply] = ["holy": .output(studioInventory)]
        let sessions = try await HolyRemoteTmuxDiscoveryService.hostsDiscoveryForTesting(
            host: .init(label: "Studio", sshDestination: "studio", tmuxSocketName: "holy"),
            inventory: fixture,
            details: fixture,
            onProgress: { _, _ in }
        )
        let list = HolyHostsSessionList(sessions)
        #expect(sessions.count == 43)
        #expect(list.count == 43)
        #expect(list.groups.first(where: { $0.runtime == .shell })?.sessions.count == 1)
        #expect(Set(list.sessions.map(\.id)) == Set(sessions.map(\.id)))
        let unknown = try #require(list.groups.first(where: { $0.runtime == nil }))
        #expect(unknown.sessions.count == 12)
        let vsi = unknown.sessions.filter { $0.sessionName.hasPrefix("holy-worker-vsi-") }
        #expect(vsi.count == 6)
        #expect(vsi.allSatisfy { $0.hostsDisplayTitle == $0.sessionName })
        #expect(vsi.allSatisfy { $0.unclassifiedHostsDetail == "/Users/erik/Custom-Coding/versova-supply-intelligence" })
        #expect(unknown.sessions.contains { $0.sessionName == "adopted-research" })
        #expect(sessions.contains { $0.shouldHideFromDiscovery })
    }

    @Test func censusPublishesAllRowsBeforeEnrichmentAndCountsEverySocket() async throws {
        let snapshots = HostsDiscoverySnapshots()
        let output = row("holy-worker-same-name")
        let inventory: [String: Reply] = ["default": .output(output), "holy": .output(output)]
        let details: [String: Reply] = [
            "default": .output(row("holy-worker-same-name", runtime: "claude")),
            "holy": .output(row("holy-worker-same-name", runtime: "codex")),
        ]
        let sessions = try await HolyRemoteTmuxDiscoveryService.hostsDiscoveryForTesting(
            host: .init(sshDestination: "studio"),
            inventory: inventory,
            details: details,
            onProgress: { await snapshots.append($0, $1) }
        )
        let entries = await snapshots.entries
        #expect(entries.map { $0.sessions.count } == [0, 1, 2, 2, 2])
        #expect(!entries[1].progress.inventoryComplete)
        #expect(entries[2].progress.inventoryComplete)
        #expect(entries[2].sessions.allSatisfy { $0.runtime == nil })
        #expect(Set(sessions.map(\.id)).count == 2)
        #expect(Set(sessions.compactMap(\.runtime)) == [.claude, .codex])
        for entry in entries {
            let list = HolyHostsSessionList(entry.sessions)
            #expect(list.count == entry.sessions.count)
            #expect(list.sessions.count == entry.sessions.count)
        }
        let partial = entries[1].progress.summary(sessionCount: 1, isBusy: true, error: nil)
        #expect(partial.contains("Showing 1 of 1 discovered so far"))
        #expect(partial.contains("Inventory incomplete: checked 1 of 2"))
        #expect(entries[2].progress.summary(sessionCount: 2, isBusy: true, error: nil).contains("Reading session details"))
    }

    @Test func detailTimeoutPreservesThe43RowInventoryAndReportsIncomplete() async throws {
        let snapshots = HostsDiscoverySnapshots()
        var failure: String?
        do {
            _ = try await HolyRemoteTmuxDiscoveryService.hostsDiscoveryForTesting(
                host: .init(label: "Studio", sshDestination: "studio", tmuxSocketName: "holy"),
                inventory: ["holy": .output(studioInventory)],
                details: ["holy": .timeout],
                onProgress: { await snapshots.append($0, $1) }
            )
            Issue.record("A timed-out sweep must not succeed")
        } catch { failure = error.localizedDescription }
        let latest = try #require(await snapshots.entries.last)
        #expect(latest.sessions.count == 43)
        let message = latest.progress.summary(sessionCount: 43, isBusy: false, error: failure)
        #expect(message.contains("Discovery incomplete"))
        #expect(message.contains("timed out after 30 seconds"))
    }

    @Test func secondSocketFailureRetainsPartialInventoryAndTypedDiagnosis() async throws {
        let snapshots = HostsDiscoverySnapshots()
        var failure: String?
        do {
            _ = try await HolyRemoteTmuxDiscoveryService.hostsDiscoveryForTesting(
                host: .init(sshDestination: "studio"),
                inventory: [
                    "default": .output(row("adopted")),
                    "holy": .failure(255, "kex_exchange_identification: read: Connection reset by peer"),
                ],
                details: [:],
                onProgress: { await snapshots.append($0, $1) }
            )
            Issue.record("A partial inventory must not succeed")
        } catch { failure = error.localizedDescription }
        let latest = try #require(await snapshots.entries.last)
        #expect(latest.sessions.map(\.sessionName) == ["adopted"])
        #expect(!latest.progress.inventoryComplete)
        #expect(failure?.contains("server instance limit is saturated") == true)
    }

    @Test(arguments: ["malformed row", ""])
    func malformedOrMissingDetailsCannotSilentlyDropInventoriedSessions(details: String) async throws {
        let snapshots = HostsDiscoverySnapshots()
        var failure: String?
        do {
            _ = try await HolyRemoteTmuxDiscoveryService.hostsDiscoveryForTesting(
                host: .init(sshDestination: "studio", tmuxSocketName: "holy"),
                inventory: ["holy": .output(row("holy-shell-unclassified"))],
                details: ["holy": .output(details)],
                onProgress: { await snapshots.append($0, $1) }
            )
            Issue.record("Incomplete details must not succeed")
        } catch { failure = error.localizedDescription }
        #expect(failure?.contains("incomplete") == true)
        #expect(await snapshots.entries.last?.sessions.count == 1)
    }

    @Test func emptyInventoryCompletesWithoutAClassifierProbe() async throws {
        let sessions = try await HolyRemoteTmuxDiscoveryService.hostsDiscoveryForTesting(
            host: .init(sshDestination: "studio"),
            inventory: ["default": .output(""), "holy": .output("")],
            details: [:],
            onProgress: { _, _ in }
        )
        #expect(sessions.isEmpty)
    }

    @Test func deadlineIncludesQueuedSSHAdmissionWithoutLaunchingAProcess() async throws {
        let destination = "holy-hosts-test-\(UUID().uuidString.lowercased())"
        let admission = HolySSHAdmissionController.shared
        let lease = try await admission.acquireControl(for: destination, operation: .discovery)
        let start = ContinuousClock.now
        var failure: String?
        do {
            _ = try await HolyRemoteTmuxDiscoveryService.shared.discoverHostsSessions(
                for: .init(sshDestination: destination),
                usesSSH: true,
                timeout: 0.05,
                onProgress: { _, _ in Issue.record("Queued discovery must not reach a process") }
            )
            Issue.record("Queued admission must obey the deadline")
        } catch { failure = error.localizedDescription }
        let snapshot = await admission.snapshot(for: destination)
        await admission.release(lease)
        #expect(start.duration(to: .now) < .seconds(2))
        #expect(failure?.contains("timed out") == true)
        #expect(snapshot.queuedControlOperations == 0)
        #expect(snapshot.activeDiscoveryOperations == 1)
    }
}
