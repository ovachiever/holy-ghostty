import Foundation
import Testing
@testable import Ghostty

@MainActor
struct HolyPowerAssertionManagerTests {
    private final class Recorder {
        var created = 0
        var released: [UInt32] = []
        var failCreate = false
    }

    private func makeManager(_ recorder: Recorder) -> HolyPowerAssertionManager {
        HolyPowerAssertionManager(
            create: { _ in
                if recorder.failCreate { return nil }
                recorder.created += 1
                return UInt32(recorder.created)
            },
            release: { recorder.released.append($0) }
        )
    }

    @Test func activateCreatesExactlyOneAssertion() {
        let recorder = Recorder()
        let manager = makeManager(recorder)
        manager.setActive(true)
        manager.setActive(true)
        #expect(recorder.created == 1)
    }

    @Test func deactivateReleasesTheAssertion() {
        let recorder = Recorder()
        let manager = makeManager(recorder)
        manager.setActive(true)
        manager.setActive(false)
        #expect(recorder.released == [1])
        manager.setActive(false)
        #expect(recorder.released == [1])
    }

    @Test func reactivateCreatesANewAssertion() {
        let recorder = Recorder()
        let manager = makeManager(recorder)
        manager.setActive(true)
        manager.setActive(false)
        manager.setActive(true)
        #expect(recorder.created == 2)
        #expect(recorder.released == [1])
    }

    @Test func failedCreateRetriesOnNextActivate() {
        let recorder = Recorder()
        recorder.failCreate = true
        let manager = makeManager(recorder)
        manager.setActive(true)
        #expect(recorder.created == 0)
        recorder.failCreate = false
        manager.setActive(true)
        #expect(recorder.created == 1)
    }
}
