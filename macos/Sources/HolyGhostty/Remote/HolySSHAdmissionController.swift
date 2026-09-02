import Foundation

/// Logical SSH channel budgets owned by Holy. The transport layer may
/// multiplex these channels over a much smaller number of TCP connections,
/// but multiplexing does not make channel capacity infinite.
struct HolySSHAdmissionLimits: Sendable, Equatable {
    /// OpenSSH defaults MaxSessions to 10 per multiplexed connection. Two
    /// interactive masters therefore admit nine surfaces each and retain one
    /// slot of headroom per lane. Hosts with a larger local override remain
    /// safe; Holy does not assume that every destination shares that override.
    var surfaceChannelsPerHost = 18

    /// The reserved control master is shared by discovery, metadata, and
    /// lifecycle commands. Lifecycle keeps the final slots so a saturated
    /// discovery sweep cannot prevent a kill or liveness probe.
    var controlOperationsPerHost = 8
    var reservedLifecycleOperationsPerHost = 2

    /// Until every call uses a ControlMaster, this also bounds the number of
    /// simultaneous raw discovery handshakes process-wide. Per-host
    /// serialization avoids duplicate sweeps competing for one destination.
    var discoveryOperationsGlobally = 4
    var discoveryOperationsPerHost = 1

    static let production = Self()

    var normalized: Self {
        var limits = self
        limits.surfaceChannelsPerHost = max(1, surfaceChannelsPerHost)
        limits.controlOperationsPerHost = max(1, controlOperationsPerHost)
        limits.reservedLifecycleOperationsPerHost = min(
            max(0, reservedLifecycleOperationsPerHost),
            max(0, limits.controlOperationsPerHost - 1)
        )
        limits.discoveryOperationsGlobally = max(1, discoveryOperationsGlobally)
        limits.discoveryOperationsPerHost = max(1, discoveryOperationsPerHost)
        return limits
    }
}

/// Filesystem-backed admission for commands whose launch configuration must be
/// rendered synchronously. `zsystem flock -e` keeps the selected slot locked
/// across `exec`; the kernel releases it when the SSH client exits, including
/// crashes and SIGKILL. This is the production surface gate. The actor below
/// supplies the same policy to async discovery and lifecycle callers.
struct HolySSHAdmissionShellPlan: Sendable, Equatable {
    let slotDirectoryPath: String
    let slotIndexes: [Int]
    let queueMessage: String

    static func surface(
        controlPath: String,
        destination: String,
        interactiveLaneCount: Int,
        limits: HolySSHAdmissionLimits = .production
    ) -> Self {
        let normalized = limits.normalized
        let laneCount = max(1, interactiveLaneCount)
        let slotsPerLane = max(1, normalized.surfaceChannelsPerHost / laneCount)
        return .init(
            slotDirectoryPath: controlPath + ".surface-slots",
            slotIndexes: Array(0 ..< slotsPerLane),
            queueMessage: "Holy is waiting for SSH surface capacity on \(destination) (\(slotsPerLane) active in this transport lane)."
        )
    }

    static func control(
        controlPath: String,
        destination: String,
        operation: HolySSHControlOperation,
        limits: HolySSHAdmissionLimits = .production
    ) -> Self {
        let normalized = limits.normalized
        let sharedCapacity = normalized.controlOperationsPerHost
            - normalized.reservedLifecycleOperationsPerHost
        let sharedSlots = Array(0 ..< sharedCapacity)
        let reservedSlots = Array(sharedCapacity ..< normalized.controlOperationsPerHost)
        let slots = operation.reservesLifecycleCapacity
            ? reservedSlots + sharedSlots
            : sharedSlots
        return .init(
            slotDirectoryPath: controlPath + ".control-slots",
            slotIndexes: slots,
            queueMessage: "Holy is waiting for SSH \(operation.rawValue) capacity on \(destination). Lifecycle capacity remains reserved."
        )
    }

    func wrapping(clientCommand: String) -> String {
        guard !slotIndexes.isEmpty else {
            return "printf '%s\\n' \(Self.posixQuote(queueMessage)) >&2; exit 255"
        }

        let indexes = slotIndexes.map(String.init).joined(separator: " ")
        return """
        holy_admission_dir=\(Self.posixQuote(slotDirectoryPath))
        if [[ -L "$holy_admission_dir" ]]; then
          printf '%s\n' 'Holy SSH admission directory is a symbolic link; refusing to connect.' >&2
          exit 255
        fi
        /bin/mkdir -p -- "$holy_admission_dir" || exit 255
        /bin/chmod 700 "$holy_admission_dir" || exit 255
        if ! zmodload zsh/system 2>/dev/null; then
          printf '%s\n' 'Holy could not load the supported SSH admission lock.' >&2
          exit 255
        fi
        for holy_slot_index in \(indexes); do
          holy_slot_path="$holy_admission_dir/slot-$holy_slot_index.lock"
          if [[ -L "$holy_slot_path" ]]; then
            printf '%s\n' 'Holy found an unsafe SSH admission slot; refusing to connect.' >&2
            exit 255
          fi
          if [[ ! -e "$holy_slot_path" ]]; then
            (umask 077; : > "$holy_slot_path") || exit 255
          fi
        done
        holy_admission_announced=0
        while true; do
          for holy_slot_index in \(indexes); do
            holy_slot_path="$holy_admission_dir/slot-$holy_slot_index.lock"
            if zsystem flock -e -t 0 -f holy_admission_fd "$holy_slot_path" 2>/dev/null; then
              export holy_admission_fd
              exec \(clientCommand)
            fi
          done
          if (( ! holy_admission_announced )); then
            printf '%s\n' \(Self.posixQuote(queueMessage)) >&2
            holy_admission_announced=1
          fi
          /bin/sleep 0.05
        done
        """
    }

    private static func posixQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

enum HolySSHControlOperation: String, Sendable, Equatable, Hashable {
    case lifecycle
    case lifecycleDiscovery = "lifecycle-discovery"
    case discovery
    case metadata

    var reservesLifecycleCapacity: Bool {
        self == .lifecycle || self == .lifecycleDiscovery
    }

    var isDiscovery: Bool {
        self == .discovery || self == .lifecycleDiscovery
    }
}

struct HolySSHAdmissionLease: Sendable, Hashable {
    fileprivate enum Kind: Sendable, Hashable {
        case surface
        case control(HolySSHControlOperation)
    }

    fileprivate let id: UUID
    fileprivate let hostKey: String
    fileprivate let kind: Kind
}

struct HolySSHAdmissionSnapshot: Sendable, Equatable {
    let activeSurfaceChannels: Int
    let queuedSurfaceChannels: Int
    let activeLifecycleOperations: Int
    let activeDiscoveryOperations: Int
    let activeMetadataOperations: Int
    let queuedControlOperations: Int
}

/// Fair, host-scoped admission for every logical SSH channel Holy owns.
///
/// Callers hold a surface lease for the lifetime of the terminal. Short-lived
/// control work should use `withControlPermit`, which releases automatically.
/// Waiting is intentional: hitting the budget queues work instead of launching
/// another SSH process and turning server saturation into a user-visible
/// connection failure.
actor HolySSHAdmissionController {
    static let shared = HolySSHAdmissionController()

    private struct HostState {
        var surfaceLeaseIDs: Set<UUID> = []
        var controlLeases: [UUID: HolySSHControlOperation] = [:]
    }

    private enum RequestKind: Sendable {
        case surface
        case control(HolySSHControlOperation)

        var queuePriority: Int {
            switch self {
            case .surface:
                return 1
            case let .control(operation):
                return operation.reservesLifecycleCapacity ? 0 : 1
            }
        }
    }

    private struct Waiter {
        let id: UUID
        let sequence: UInt64
        let hostKey: String
        let kind: RequestKind
        let continuation: CheckedContinuation<HolySSHAdmissionLease, any Error>
    }

    private let limits: HolySSHAdmissionLimits
    private var hosts: [String: HostState] = [:]
    private var waiters: [Waiter] = []
    private var nextSequence: UInt64 = 0

    init(limits: HolySSHAdmissionLimits = .production) {
        self.limits = limits.normalized
    }

    func acquireSurface(for destination: String) async throws -> HolySSHAdmissionLease {
        try await acquire(hostKey: Self.hostKey(for: destination), kind: .surface)
    }

    func acquireControl(
        for destination: String,
        operation: HolySSHControlOperation
    ) async throws -> HolySSHAdmissionLease {
        try await acquire(
            hostKey: Self.hostKey(for: destination),
            kind: .control(operation)
        )
    }

    func withControlPermit<T: Sendable>(
        for destination: String,
        operation: HolySSHControlOperation,
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        let lease = try await acquireControl(for: destination, operation: operation)
        defer { release(lease) }
        return try await body()
    }

    func release(_ lease: HolySSHAdmissionLease) {
        guard var state = hosts[lease.hostKey] else { return }

        let removed: Bool
        switch lease.kind {
        case .surface:
            removed = state.surfaceLeaseIDs.remove(lease.id) != nil
        case .control:
            removed = state.controlLeases.removeValue(forKey: lease.id) != nil
        }
        guard removed else { return }

        if state.surfaceLeaseIDs.isEmpty, state.controlLeases.isEmpty {
            hosts.removeValue(forKey: lease.hostKey)
        } else {
            hosts[lease.hostKey] = state
        }
        admitQueuedWork()
    }

    func snapshot(for destination: String) -> HolySSHAdmissionSnapshot {
        let hostKey = Self.hostKey(for: destination)
        let state = hosts[hostKey] ?? HostState()
        let queuedForHost = waiters.filter { $0.hostKey == hostKey }

        return HolySSHAdmissionSnapshot(
            activeSurfaceChannels: state.surfaceLeaseIDs.count,
            queuedSurfaceChannels: queuedForHost.filter {
                if case .surface = $0.kind { return true }
                return false
            }.count,
            activeLifecycleOperations: state.controlLeases.values.filter(\.reservesLifecycleCapacity).count,
            activeDiscoveryOperations: state.controlLeases.values.filter(\.isDiscovery).count,
            activeMetadataOperations: state.controlLeases.values.filter { $0 == .metadata }.count,
            queuedControlOperations: queuedForHost.filter {
                if case .control = $0.kind { return true }
                return false
            }.count
        )
    }

    private func acquire(
        hostKey: String,
        kind: RequestKind
    ) async throws -> HolySSHAdmissionLease {
        try Task.checkCancellation()
        if canAdmit(hostKey: hostKey, kind: kind) {
            return admit(hostKey: hostKey, kind: kind)
        }

        let requestID = UUID()
        let sequence = nextSequence
        nextSequence &+= 1
        let lease = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(.init(
                    id: requestID,
                    sequence: sequence,
                    hostKey: hostKey,
                    kind: kind,
                    continuation: continuation
                ))
            }
        } onCancel: {
            Task { await self.cancelWaiter(requestID) }
        }

        if Task.isCancelled {
            release(lease)
            throw CancellationError()
        }
        return lease
    }

    private func canAdmit(hostKey: String, kind: RequestKind) -> Bool {
        let state = hosts[hostKey] ?? HostState()
        switch kind {
        case .surface:
            return state.surfaceLeaseIDs.count < limits.surfaceChannelsPerHost

        case let .control(operation):
            let activeControlCount = state.controlLeases.count
            guard activeControlCount < limits.controlOperationsPerHost else {
                return false
            }

            if !operation.reservesLifecycleCapacity {
                let sharedCapacity = limits.controlOperationsPerHost
                    - limits.reservedLifecycleOperationsPerHost
                let activeSharedCount = state.controlLeases.values.filter {
                    !$0.reservesLifecycleCapacity
                }.count
                guard activeSharedCount < sharedCapacity else { return false }
            }

            if operation.isDiscovery {
                let hostDiscoveryCount = state.controlLeases.values.filter(\.isDiscovery).count
                guard hostDiscoveryCount < limits.discoveryOperationsPerHost else { return false }
                guard activeDiscoveryCount < limits.discoveryOperationsGlobally else { return false }
            }

            return true
        }
    }

    private var activeDiscoveryCount: Int {
        hosts.values.reduce(into: 0) { count, state in
            count += state.controlLeases.values.filter(\.isDiscovery).count
        }
    }

    private func admit(hostKey: String, kind: RequestKind) -> HolySSHAdmissionLease {
        let leaseKind: HolySSHAdmissionLease.Kind
        switch kind {
        case .surface:
            leaseKind = .surface
        case let .control(operation):
            leaseKind = .control(operation)
        }

        let lease = HolySSHAdmissionLease(
            id: UUID(),
            hostKey: hostKey,
            kind: leaseKind
        )
        var state = hosts[hostKey] ?? HostState()
        switch kind {
        case .surface:
            state.surfaceLeaseIDs.insert(lease.id)
        case let .control(operation):
            state.controlLeases[lease.id] = operation
        }
        hosts[hostKey] = state
        return lease
    }

    private func admitQueuedWork() {
        while let index = nextAdmissibleWaiterIndex() {
            let waiter = waiters.remove(at: index)
            let lease = admit(hostKey: waiter.hostKey, kind: waiter.kind)
            waiter.continuation.resume(returning: lease)
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func nextAdmissibleWaiterIndex() -> Int? {
        waiters.indices
            .filter { canAdmit(hostKey: waiters[$0].hostKey, kind: waiters[$0].kind) }
            .min { lhs, rhs in
                let left = waiters[lhs]
                let right = waiters[rhs]
                if left.kind.queuePriority != right.kind.queuePriority {
                    return left.kind.queuePriority < right.kind.queuePriority
                }
                return left.sequence < right.sequence
            }
    }

    nonisolated static func hostKey(for destination: String) -> String {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.lastIndex(of: "@") else {
            return trimmed.lowercased()
        }

        let user = trimmed[..<separator]
        let host = trimmed[trimmed.index(after: separator)...]
        return "\(user)@\(host.lowercased())"
    }
}
