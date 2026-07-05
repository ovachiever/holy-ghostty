import Foundation
import IOKit.pwr_mgt

/// Holds a single PreventUserIdleSystemSleep assertion while remote sessions
/// are attached: the display may sleep, the system may not, so SSH stays up.
/// Injectable create/release keep the IOPM calls out of unit tests.
@MainActor
final class HolyPowerAssertionManager {
    private let create: (String) -> UInt32?
    private let release: (UInt32) -> Void
    private var activeAssertionID: UInt32?

    init(
        create: @escaping (String) -> UInt32? = HolyPowerAssertionManager.systemCreate,
        release: @escaping (UInt32) -> Void = HolyPowerAssertionManager.systemRelease
    ) {
        self.create = create
        self.release = release
    }

    func setActive(_ active: Bool) {
        if active {
            guard activeAssertionID == nil else { return }
            activeAssertionID = create("Holy Ghostty is keeping remote SSH sessions attached")
        } else if let id = activeAssertionID {
            release(id)
            activeAssertionID = nil
        }
    }

    private nonisolated static func systemCreate(reason: String) -> UInt32? {
        var assertionID = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        return status == kIOReturnSuccess ? assertionID : nil
    }

    private nonisolated static func systemRelease(assertionID: UInt32) {
        IOPMAssertionRelease(assertionID)
    }
}
