import Foundation
import Testing
@testable import Ghostty

struct HolyArchiveRetentionCoverageTests {
    @MainActor
    @Test func offlineHostIsProtectedWithoutBlockingCoveredArchiveCompaction() {
        let now = Date(timeIntervalSince1970: 20_000_000)
        var archives = (0..<300).map { index in
            archive(
                destination: "covered.example",
                socketName: "holy",
                archivedAt: now.addingTimeInterval(-Double(index) * 24 * 60 * 60)
            )
        }
        let coveredOldID = archives[299].id
        let offlineArchive = archive(
            destination: "offline.example",
            socketName: "holy",
            archivedAt: now.addingTimeInterval(-400 * 24 * 60 * 60)
        )
        archives.append(offlineArchive)

        let coveredKey = HolyWorkspaceStore.convergeHostKeyForTesting(
            destination: "covered.example",
            socketName: "holy"
        )
        let reachable: Set<String> = [coveredKey]
        #expect(HolyWorkspaceStore.archiveDiscoveryCoveredForTesting(
            archives[0],
            reachableHostKeys: reachable
        ))
        #expect(!HolyWorkspaceStore.archiveDiscoveryCoveredForTesting(
            offlineArchive,
            reachableHostKeys: reachable
        ))

        let retained = HolyWorkspaceRetentionPolicy.retainedArchivedSessions(
            archives,
            protectedArchiveIDs: [offlineArchive.id],
            now: now
        )

        #expect(retained.contains(where: { $0.id == offlineArchive.id }))
        #expect(!retained.contains(where: { $0.id == coveredOldID }))
        #expect(retained.count <= HolyWorkspaceRetentionPolicy.maximumArchivedSessionCount)
    }

    @MainActor
    @Test func missingSocketRequiresDefaultAndHolyCoverage() {
        let archive = archive(
            destination: "legacy.example",
            socketName: nil,
            archivedAt: .now
        )
        let defaultKey = HolyWorkspaceStore.convergeHostKeyForTesting(
            destination: "legacy.example",
            socketName: nil
        )
        let holyKey = HolyWorkspaceStore.convergeHostKeyForTesting(
            destination: "legacy.example",
            socketName: HolySessionTmuxSpec.defaultSocketName
        )

        #expect(!HolyWorkspaceStore.archiveDiscoveryCoveredForTesting(
            archive,
            reachableHostKeys: [defaultKey]
        ))
        #expect(HolyWorkspaceStore.archiveDiscoveryCoveredForTesting(
            archive,
            reachableHostKeys: [defaultKey, holyKey]
        ))
    }

    private func archive(
        destination: String,
        socketName: String?,
        archivedAt: Date
    ) -> HolyArchivedSession {
        let sessionID = UUID()
        let spec = HolySessionLaunchSpec(
            runtime: .shell,
            title: destination,
            transport: .init(kind: .ssh, hostLabel: destination, sshDestination: destination),
            tmux: .init(socketName: socketName, sessionName: "session-\(sessionID.uuidString)", createIfMissing: false),
            workingDirectory: nil,
            command: nil,
            initialInput: nil,
            waitAfterCommand: false,
            environment: [:]
        )
        let record = HolySessionRecord(
            id: sessionID,
            launchSpec: spec,
            createdAt: archivedAt,
            updatedAt: archivedAt
        )
        return HolyArchivedSession(
            sourceSessionID: sessionID,
            record: record,
            phase: .completed,
            preview: "",
            signals: [],
            commandTelemetry: .empty,
            budgetTelemetry: .empty,
            runtimeTelemetry: .empty,
            gitSnapshot: nil,
            lastKnownWorkingDirectory: nil,
            lastActivityAt: archivedAt,
            archivedAt: archivedAt
        )
    }
}
