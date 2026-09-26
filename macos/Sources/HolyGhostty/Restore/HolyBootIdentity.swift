import Darwin
import Foundation

/// The identity of the kernel boot the app is running under, read from the
/// kernel itself. Two sysctls, two jobs:
///
/// - `kern.bootsessionuuid` is minted once per boot and never changes while
///   the machine is up. It answers "same boot or not" exactly, which is the
///   question freshness asks: a session last seen live under a different
///   boot died with the machine, whatever its archive row says.
/// - `kern.boottime` is the boot instant, the authority for WHEN a panic's
///   reboot happened. Measured 2026-09-26 on the machine that panicked:
///   `kern.boottime: { sec = 1790421415, usec = 985376 } Sat Sep 26 06:16:55`
///   (the same boot the work order cites as epoch 1790421414; the kernel
///   adjusts this value by a second when the clock is stepped, which is why
///   the UUID, not the time, is the identity).
struct HolyBootIdentity: Codable, Equatable, Sendable {
    /// `kern.bootsessionuuid`, or nil when the sysctl could not be read.
    var sessionUUID: String?
    /// `kern.boottime` as a date, or nil when the sysctl could not be read.
    var bootTime: Date?

    var isKnown: Bool { sessionUUID != nil || bootTime != nil }

    /// Reads both sysctls from the running kernel.
    static func current() -> HolyBootIdentity {
        .init(
            sessionUUID: readSysctlString("kern.bootsessionuuid"),
            bootTime: readBootTime()
        )
    }

    /// Exact when both sides carry the boot session UUID. Without it (a
    /// ledger written by a kernel that lacks the sysctl) the boot second is
    /// compared instead; unknown on either side is never "same boot".
    func isSameBoot(as other: HolyBootIdentity) -> Bool {
        if let mine = sessionUUID, let theirs = other.sessionUUID {
            return mine == theirs
        }
        guard let mine = bootTime, let theirs = other.bootTime else { return false }
        return Int(mine.timeIntervalSince1970) == Int(theirs.timeIntervalSince1970)
    }

    private static func readSysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func readBootTime() -> Date? {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &boottime, &size, nil, 0) == 0,
              boottime.tv_sec > 0 else {
            return nil
        }
        return Date(
            timeIntervalSince1970: TimeInterval(boottime.tv_sec)
                + TimeInterval(boottime.tv_usec) / 1_000_000
        )
    }
}
