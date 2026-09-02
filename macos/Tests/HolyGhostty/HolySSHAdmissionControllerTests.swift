import Foundation
import Testing
@testable import Ghostty

private actor HolySSHConcurrencyProbe {
    private(set) var active = 0
    private(set) var peak = 0
    private(set) var completed = 0

    func enter() {
        active += 1
        peak = max(peak, active)
    }

    func leave() {
        active -= 1
        completed += 1
    }
}

private actor HolySSHTestLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

struct HolySSHAdmissionControllerTests {
    @Test func filesystemSurfaceGateQueuesBeforeExecutingTheNextClient() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-ssh-admission-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let firstStartedURL = rootURL.appendingPathComponent("first-started")
        let releaseFirstURL = rootURL.appendingPathComponent("release-first")
        let plan = HolySSHAdmissionShellPlan(
            slotDirectoryPath: rootURL.appendingPathComponent("slots").path,
            slotIndexes: [0],
            queueMessage: "queued by test"
        )
        let firstClientScript = """
        /usr/bin/touch \(shellQuote(firstStartedURL.path))
        while [[ ! -e \(shellQuote(releaseFirstURL.path)) ]]; do /bin/sleep 0.01; done
        """
        let first = process(for: plan.wrapping(
            clientCommand: "/bin/zsh -c \(shellQuote(firstClientScript))"
        ))
        let second = process(for: plan.wrapping(clientCommand: "/usr/bin/true"))
        defer {
            _ = FileManager.default.createFile(atPath: releaseFirstURL.path, contents: Data())
            if first.isRunning { first.terminate() }
            if second.isRunning { second.terminate() }
        }

        try first.run()
        #expect(await waitUntil {
            FileManager.default.fileExists(atPath: firstStartedURL.path)
        })
        try second.run()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(second.isRunning, "The second client ran instead of waiting for the occupied slot")

        _ = FileManager.default.createFile(atPath: releaseFirstURL.path, contents: Data())
        first.waitUntilExit()
        second.waitUntilExit()
        #expect(first.terminationStatus == 0)
        #expect(second.terminationStatus == 0)
    }

    @Test func controlShellPlanReservesItsLastSlotsForLifecycle() {
        let limits = HolySSHAdmissionLimits(
            surfaceChannelsPerHost: 4,
            controlOperationsPerHost: 4,
            reservedLifecycleOperationsPerHost: 2,
            discoveryOperationsGlobally: 2,
            discoveryOperationsPerHost: 1
        )
        let discovery = HolySSHAdmissionShellPlan.control(
            controlPath: "/safe/control.sock",
            destination: "studio",
            operation: .discovery,
            limits: limits
        )
        let lifecycle = HolySSHAdmissionShellPlan.control(
            controlPath: "/safe/control.sock",
            destination: "studio",
            operation: .lifecycle,
            limits: limits
        )
        let lifecycleDiscovery = HolySSHAdmissionShellPlan.control(
            controlPath: "/safe/control.sock",
            destination: "studio",
            operation: .lifecycleDiscovery,
            limits: limits
        )

        #expect(discovery.slotIndexes == [0, 1])
        #expect(lifecycle.slotIndexes == [2, 3, 0, 1])
        #expect(lifecycleDiscovery.slotIndexes == lifecycle.slotIndexes)
    }

    @Test func saturatedSurfaceBudgetQueuesThenAdmitsInFIFOOrder() async throws {
        let controller = HolySSHAdmissionController(limits: .init(
            surfaceChannelsPerHost: 2,
            controlOperationsPerHost: 4,
            reservedLifecycleOperationsPerHost: 1,
            discoveryOperationsGlobally: 2,
            discoveryOperationsPerHost: 1
        ))
        let first = try await controller.acquireSurface(for: "erik@Studio.local")
        let second = try await controller.acquireSurface(for: "erik@studio.local")
        let thirdTask = Task {
            try await controller.acquireSurface(for: "erik@STUDIO.LOCAL")
        }

        #expect(await waitUntil {
            await controller.snapshot(for: "erik@studio.local").queuedSurfaceChannels == 1
        })

        await controller.release(first)
        let third = try await thirdTask.value
        let admitted = await controller.snapshot(for: "erik@studio.local")
        #expect(admitted.activeSurfaceChannels == 2)
        #expect(admitted.queuedSurfaceChannels == 0)

        await controller.release(second)
        await controller.release(third)
    }

    @Test func discoveryIsSerializedPerHostAndBoundedAcrossHosts() async throws {
        let controller = HolySSHAdmissionController(limits: .init(
            surfaceChannelsPerHost: 2,
            controlOperationsPerHost: 4,
            reservedLifecycleOperationsPerHost: 1,
            discoveryOperationsGlobally: 2,
            discoveryOperationsPerHost: 1
        ))
        let studio = try await controller.acquireControl(for: "studio", operation: .discovery)
        let macbook = try await controller.acquireControl(for: "macbook", operation: .discovery)
        let secondStudioTask = Task {
            try await controller.acquireControl(for: "studio", operation: .discovery)
        }
        let miniTask = Task {
            try await controller.acquireControl(for: "mini", operation: .discovery)
        }

        #expect(await waitUntil {
            let studioSnapshot = await controller.snapshot(for: "studio")
            let miniSnapshot = await controller.snapshot(for: "mini")
            return studioSnapshot.queuedControlOperations == 1
                && miniSnapshot.queuedControlOperations == 1
        })

        await controller.release(studio)
        let secondStudio = try await secondStudioTask.value
        let studioAfterRelease = await controller.snapshot(for: "studio")
        #expect(studioAfterRelease.activeDiscoveryOperations == 1)

        await controller.release(macbook)
        let mini = try await miniTask.value
        #expect(await controller.snapshot(for: "mini").activeDiscoveryOperations == 1)

        await controller.release(secondStudio)
        await controller.release(mini)
    }

    @Test func lifecycleUsesCapacityReservedFromDiscoveryAndRunsFirst() async throws {
        let controller = HolySSHAdmissionController(limits: .init(
            surfaceChannelsPerHost: 2,
            controlOperationsPerHost: 3,
            reservedLifecycleOperationsPerHost: 1,
            discoveryOperationsGlobally: 4,
            discoveryOperationsPerHost: 2
        ))
        let discovery = try await controller.acquireControl(for: "studio", operation: .discovery)
        let metadata = try await controller.acquireControl(for: "studio", operation: .metadata)
        let queuedMetadataTask = Task {
            try await controller.acquireControl(for: "studio", operation: .metadata)
        }

        #expect(await waitUntil {
            await controller.snapshot(for: "studio").queuedControlOperations == 1
        })

        let lifecycle = try await controller.acquireControl(for: "studio", operation: .lifecycle)
        let saturated = await controller.snapshot(for: "studio")
        #expect(saturated.activeLifecycleOperations == 1)
        #expect(saturated.queuedControlOperations == 1)

        await controller.release(metadata)
        let queuedMetadata = try await queuedMetadataTask.value
        await controller.release(discovery)
        await controller.release(lifecycle)
        await controller.release(queuedMetadata)
    }

    @Test func fortyHostDiscoveryStormNeverExceedsGlobalBound() async throws {
        let controller = HolySSHAdmissionController(limits: .init(
            surfaceChannelsPerHost: 2,
            controlOperationsPerHost: 4,
            reservedLifecycleOperationsPerHost: 1,
            discoveryOperationsGlobally: 4,
            discoveryOperationsPerHost: 1
        ))
        let probe = HolySSHConcurrencyProbe()
        let latch = HolySSHTestLatch()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    try await controller.withControlPermit(
                        for: "host-\(index)",
                        operation: index.isMultiple(of: 2) ? .discovery : .lifecycleDiscovery
                    ) {
                        await probe.enter()
                        await latch.wait()
                        await probe.leave()
                    }
                }
            }

            #expect(await waitUntil(timeout: 5) { await probe.active == 4 })
            #expect(await probe.peak == 4)
            await latch.open()
            try await group.waitForAll()
        }

        #expect(await probe.peak == 4)
        #expect(await probe.completed == 40)
    }

    @Test func cancellingQueuedLaunchRemovesItWithoutConsumingCapacity() async throws {
        let controller = HolySSHAdmissionController(limits: .init(
            surfaceChannelsPerHost: 1,
            controlOperationsPerHost: 2,
            reservedLifecycleOperationsPerHost: 1,
            discoveryOperationsGlobally: 1,
            discoveryOperationsPerHost: 1
        ))
        let active = try await controller.acquireSurface(for: "studio")
        let queuedTask = Task {
            try await controller.acquireSurface(for: "studio")
        }

        #expect(await waitUntil {
            await controller.snapshot(for: "studio").queuedSurfaceChannels == 1
        })
        queuedTask.cancel()

        do {
            _ = try await queuedTask.value
            Issue.record("A cancelled queued launch was admitted")
        } catch is CancellationError {
            // Expected: cancellation removes the waiter without a phantom slot.
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }

        let snapshot = await controller.snapshot(for: "studio")
        #expect(snapshot.activeSurfaceChannels == 1)
        #expect(snapshot.queuedSurfaceChannels == 0)
        await controller.release(active)
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await condition()
    }

    private func process(for script: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        return process
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
