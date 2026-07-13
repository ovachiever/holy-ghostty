import Foundation
import Testing
@testable import Ghostty

struct HolyTmuxLifecycleIdentityTests {
    private func discovered(
        socketName: String? = "holy",
        sessionName: String,
        title: String? = nil,
        runtime: HolySessionRuntime? = nil,
        workingDirectory: String? = nil,
        objective: String? = nil,
        command: String? = nil
    ) -> HolyDiscoveredTmuxSession {
        .init(
            hostID: UUID(),
            hostLabel: "This Mac",
            hostDestination: "localhost",
            tmuxSocketName: socketName,
            sessionName: sessionName,
            title: title,
            runtimeRawValue: runtime?.rawValue,
            objective: objective,
            workingDirectory: workingDirectory,
            bootstrapCommand: command,
            taskTitle: nil,
            taskSource: nil,
            gitSummary: nil,
            attachedClientCount: 1,
            windowCount: 1,
            discoveredAt: .now
        )
    }

    @Test func creationRealizationProducesStablePersistableIdentity() {
        let draft = HolySessionLaunchSpec.interactiveTmuxShell(title: "Codex")
        let realized = HolyTmuxCommandBuilder.realizedLaunchSpec(draft)

        #expect(draft.tmux?.sessionName == nil)
        #expect(realized.tmux?.socketName == HolySessionTmuxSpec.defaultSocketName)
        #expect(realized.tmux?.sessionName?.isEmpty == false)
        #expect(HolyTmuxCommandBuilder.realizedLaunchSpec(realized) == realized)
    }

    @Test func missingSocketIsRecoveredFromUniqueNamedLiveSession() {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Codex")
        spec.tmux = .init(socketName: nil, sessionName: "holy-codex-12345678", createIfMissing: true)
        let live = discovered(sessionName: "holy-codex-12345678", runtime: .codex)

        #expect(HolyTmuxIdentityResolver.resolve(launchSpec: spec, among: [live]) == .matched(live))
    }

    @Test func missingSocketWithSameNameOnTwoServersIsAmbiguous() {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Codex")
        spec.tmux = .init(socketName: nil, sessionName: "shared-name", createIfMissing: true)
        let onDefault = discovered(socketName: nil, sessionName: "shared-name")
        let onHoly = discovered(socketName: "holy", sessionName: "shared-name")

        #expect(
            HolyTmuxIdentityResolver.resolve(launchSpec: spec, among: [onDefault, onHoly])
                == .ambiguous
        )
    }

    @Test func missingNameRequiresStrongMetadataEvidence() {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Versova")
        spec.runtime = .codex
        spec.workingDirectory = "/tmp/versova"
        spec.tmux?.sessionName = nil
        let live = discovered(
            sessionName: "holy-versova-codex-12345678",
            title: "Versova",
            runtime: .codex,
            workingDirectory: "/tmp/versova"
        )

        #expect(HolyTmuxIdentityResolver.resolve(launchSpec: spec, among: [live]) == .matched(live))
    }

    @Test func missingNameNormalizesInventoryControlBytesBeforeMatching() {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Versova")
        spec.objective = "first line\nsecond\rpart\u{1F}final"
        spec.tmux?.sessionName = nil
        let live = discovered(
            sessionName: "holy-versova-shell-12345678",
            title: "Versova",
            objective: "first line second part final"
        )

        #expect(HolyTmuxIdentityResolver.resolve(launchSpec: spec, among: [live]) == .matched(live))
    }

    @Test func titleOnlyEvidenceCannotAuthorizeDestructiveTarget() {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Versova")
        spec.tmux?.sessionName = nil
        let live = discovered(sessionName: "unrelated", title: "Versova")

        #expect(HolyTmuxIdentityResolver.resolve(launchSpec: spec, among: [live]) == .notFound)
        #expect(spec.tmux?.sessionName == nil)
    }

    @Test func workingDirectoryAloneCannotAuthorizeDestructiveTarget() {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell()
        spec.workingDirectory = "/tmp/versova"
        spec.tmux?.sessionName = nil
        let live = discovered(sessionName: "unrelated", workingDirectory: "/tmp/versova")

        #expect(HolyTmuxIdentityResolver.resolve(launchSpec: spec, among: [live]) == .notFound)
    }

    @Test func contradictoryMetadataRejectsOtherwiseStrongCandidate() {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Versova")
        spec.runtime = .codex
        spec.workingDirectory = "/tmp/versova"
        spec.tmux?.sessionName = nil
        let live = discovered(
            sessionName: "unrelated",
            title: "Different Project",
            runtime: .codex,
            workingDirectory: "/tmp/versova"
        )

        #expect(HolyTmuxIdentityResolver.resolve(launchSpec: spec, among: [live]) == .notFound)
    }

    @Test func equallyStrongLegacyMatchesAreAmbiguous() {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Versova")
        spec.runtime = .codex
        spec.workingDirectory = "/tmp/versova"
        spec.tmux?.sessionName = nil
        let first = discovered(
            sessionName: "first",
            title: "Versova",
            runtime: .codex,
            workingDirectory: "/tmp/versova"
        )
        let second = discovered(
            sessionName: "second",
            title: "Versova",
            runtime: .codex,
            workingDirectory: "/tmp/versova"
        )

        #expect(HolyTmuxIdentityResolver.resolve(launchSpec: spec, among: [first, second]) == .ambiguous)
    }

    @Test func twoRecordsCannotClaimOneLiveIdentity() {
        var firstSpec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Versova")
        firstSpec.runtime = .codex
        firstSpec.workingDirectory = "/tmp/versova"
        firstSpec.tmux?.sessionName = nil
        let secondSpec = firstSpec
        let firstID = UUID()
        let secondID = UUID()
        let live = discovered(
            sessionName: "holy-versova-codex-12345678",
            title: "Versova",
            runtime: .codex,
            workingDirectory: "/tmp/versova"
        )

        let matches = HolyTmuxIdentityResolver.resolveOneToOne(
            launchSpecsByID: [firstID: firstSpec, secondID: secondSpec],
            among: [live]
        )
        #expect(matches.isEmpty)
    }

    @Test func socketNamespacesRemainCaseSensitive() {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Codex")
        spec.tmux = .init(socketName: "holy", sessionName: "demo", createIfMissing: true)
        let live = discovered(socketName: "HOLY", sessionName: "demo")

        #expect(HolyTmuxIdentityResolver.resolve(launchSpec: spec, among: [live]) == .notFound)
    }

    @Test func restoreRepairsDiscoverableMissingNameBeforeSurfaceCreation() throws {
        let sessionID = UUID()
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Versova")
        spec.runtime = .codex
        spec.workingDirectory = "/tmp/versova"
        spec.tmux = .init(socketName: "holy", sessionName: nil, createIfMissing: true)
        let record = HolySessionRecord(id: sessionID, launchSpec: spec)
        let live = discovered(
            sessionName: "holy-versova-codex-12345678",
            title: "Versova",
            runtime: .codex,
            workingDirectory: "/tmp/versova"
        )

        let restored = try #require(HolySessionSupervisor.preflightRestoredRecordForTesting(
            record,
            discoveredLocalSessions: [live]
        ))

        #expect(restored.id == sessionID)
        #expect(restored.launchSpec.tmux?.sessionName == live.sessionName)
        #expect(restored.launchSpec.tmux?.socketName == "holy")
        #expect(restored.launchSpec.tmux?.createIfMissing == false)
    }

    @Test func restoreQuarantinesMissingSocketDespiteHolyOnlyObservation() {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Versova")
        spec.tmux = .init(socketName: nil, sessionName: "known-name", createIfMissing: true)
        let record = HolySessionRecord(launchSpec: spec)
        let live = discovered(socketName: "holy", sessionName: "known-name")

        let restored = HolySessionSupervisor.preflightRestoredRecordForTesting(
            record,
            discoveredLocalSessions: [live]
        )

        #expect(restored == nil)
        #expect(record.launchSpec.tmux?.sessionName == "known-name")
        #expect(record.launchSpec.tmux?.socketName == nil)
    }

    @Test func unresolvedIncompleteLocalRestoreNeverCrossesSurfaceBoundary() {
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Shell")
        spec.tmux = .init(socketName: "holy", sessionName: nil, createIfMissing: true)
        let record = HolySessionRecord(
            launchSpec: spec,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        let restored = HolySessionSupervisor.preflightRestoredRecordForTesting(
            record,
            discoveredLocalSessions: []
        )

        #expect(restored == nil)
        #expect(record.launchSpec.tmux?.sessionName == nil)

        let quarantine = HolySessionSupervisor.quarantinedRestoreRecordForTesting(record)
        #expect(quarantine.archivedSession.sourceSessionID == record.id)
        #expect(quarantine.archivedSession.record == record)
        #expect(quarantine.archivedSession.record.createdAt == createdAt)
        #expect(quarantine.archivedSession.record.updatedAt == updatedAt)
        #expect(quarantine.pendingEvent.sessionID == record.id)
        #expect(quarantine.pendingEvent.eventType == .recovered)
        #expect(!HolySessionSupervisor.shouldSeedDefaultSessionForTesting(
            seedEnabled: true,
            deferredTmuxIdentityRecordIDs: [record.id]
        ))
    }

    @Test func incompleteRemoteRestoreWaitsForAsyncDiscovery() {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Remote")
        spec.transport = .init(kind: .ssh, hostLabel: "Studio", sshDestination: "studio")
        spec.tmux = .init(socketName: nil, sessionName: "known-name", createIfMissing: true)
        let record = HolySessionRecord(launchSpec: spec)

        #expect(HolySessionSupervisor.preflightRestoredRecordForTesting(
            record,
            discoveredLocalSessions: []
        ) == nil)

        let quarantine = HolySessionSupervisor.quarantinedRestoreRecordForTesting(record)
        #expect(quarantine.archivedSession.sourceSessionID == record.id)
        #expect(quarantine.archivedSession.record == record)
        #expect(quarantine.pendingEvent.eventType == .recovered)
    }

    @Test func restorePreflightPartitionsEveryRecordWithoutLossOrSynthesis() throws {
        let completeID = UUID()
        let missingNameID = UUID()
        let missingSocketID = UUID()
        let completeCreatedAt = Date(timeIntervalSince1970: 100)
        let missingNameCreatedAt = Date(timeIntervalSince1970: 200)
        let missingSocketCreatedAt = Date(timeIntervalSince1970: 300)

        var completeSpec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Complete")
        completeSpec.tmux = .init(
            socketName: "holy",
            sessionName: "holy-complete-12345678",
            createIfMissing: false
        )
        let complete = HolySessionRecord(
            id: completeID,
            launchSpec: completeSpec,
            createdAt: completeCreatedAt,
            updatedAt: completeCreatedAt
        )

        var missingNameSpec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Missing Name")
        missingNameSpec.tmux = .init(socketName: "holy", sessionName: nil, createIfMissing: true)
        let missingName = HolySessionRecord(
            id: missingNameID,
            launchSpec: missingNameSpec,
            createdAt: missingNameCreatedAt,
            updatedAt: missingNameCreatedAt
        )

        var missingSocketSpec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Missing Socket")
        missingSocketSpec.tmux = .init(
            socketName: nil,
            sessionName: "known-name",
            createIfMissing: true
        )
        let missingSocket = HolySessionRecord(
            id: missingSocketID,
            launchSpec: missingSocketSpec,
            createdAt: missingSocketCreatedAt,
            updatedAt: missingSocketCreatedAt
        )

        let input = [complete, missingName, missingSocket]
        let result = HolySessionSupervisor.restorePreflightPartitionForTesting(
            input,
            discoveredLocalSessions: [discovered(socketName: "holy", sessionName: "known-name")]
        )
        let outputIDs = Set(result.restorableRecords.map(\.id))
            .union(result.archivedSessions.map(\.sourceSessionID))

        #expect(outputIDs == Set(input.map(\.id)))
        #expect(result.restorableRecords == [complete])
        #expect(result.archivedSessions.count == 2)
        #expect(result.pendingEvents.count == 2)
        #expect(result.deferredTmuxIdentityRecordIDs == [missingNameID, missingSocketID])
        #expect(Set(result.pendingEvents.map(\.sessionID)) == [missingNameID, missingSocketID])
        #expect(result.pendingEvents.allSatisfy { $0.eventType == .recovered })
        #expect(!HolySessionSupervisor.shouldSeedDefaultSessionForTesting(
            seedEnabled: true,
            deferredTmuxIdentityRecordIDs: result.deferredTmuxIdentityRecordIDs
        ))

        let archivedBySourceID = Dictionary(
            uniqueKeysWithValues: result.archivedSessions.map { ($0.sourceSessionID, $0) }
        )
        let archivedMissingName = try #require(archivedBySourceID[missingNameID])
        let archivedMissingSocket = try #require(archivedBySourceID[missingSocketID])
        #expect(archivedMissingName.record == missingName)
        #expect(archivedMissingName.record.launchSpec.tmux?.sessionName == nil)
        #expect(archivedMissingName.record.createdAt == missingNameCreatedAt)
        #expect(archivedMissingSocket.record == missingSocket)
        #expect(archivedMissingSocket.record.launchSpec.tmux?.socketName == nil)
        #expect(archivedMissingSocket.record.createdAt == missingSocketCreatedAt)
    }

    @Test func archivedReadoptionPreservesOriginalSessionIdentity() {
        let sourceID = UUID()
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)
        var archivedSpec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Versova")
        archivedSpec.tmux = .init(socketName: "holy", sessionName: nil, createIfMissing: true)
        let record = HolySessionRecord(
            id: sourceID,
            launchSpec: archivedSpec,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let archived = HolyArchivedSession(
            sourceSessionID: sourceID,
            record: record,
            phase: .completed,
            preview: "",
            signals: [],
            commandTelemetry: .empty,
            budgetTelemetry: .empty,
            runtimeTelemetry: .empty,
            gitSnapshot: nil,
            lastKnownWorkingDirectory: nil,
            lastActivityAt: createdAt,
            archivedAt: createdAt
        )
        var liveSpec = archivedSpec
        liveSpec.tmux = .init(socketName: "holy", sessionName: "holy-versova-12345678", createIfMissing: false)

        let readopted = HolySessionSupervisor.readoptedRecordForTesting(
            archived,
            launchSpec: liveSpec,
            updatedAt: updatedAt
        )

        #expect(readopted.id == sourceID)
        #expect(readopted.createdAt == createdAt)
        #expect(readopted.updatedAt == updatedAt)
        #expect(readopted.launchSpec == liveSpec)
    }
}
