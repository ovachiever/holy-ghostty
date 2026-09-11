import Foundation

struct HolyMannaBoardLinkResolution: Sendable {
    let matches: [HolyMannaStatePayload]
    let estate: HolyMannaEstatePayload?
}

/// A unique match is proved by reading every existing board on the originating
/// host. A failed read cannot silently turn an ambiguous id into a unique one.
struct HolyMannaBoardLinkResolver: Sendable {
    let client: HolyMannaBoardClient

    func resolve(_ id: String, from origin: HolyMannaBoardContext) async throws -> HolyMannaBoardLinkResolution {
        guard HolyMannaLink.isIdentifier(id) else {
            throw HolyMannaAskError.unavailable("Invalid Manna item id.")
        }
        var focusedRoot: String?
        if origin.boardRoot != nil {
            do {
                let focused = try await client.state(for: origin)
                focusedRoot = focused.root
                if focused.item(id: id) != nil {
                    return .init(matches: [focused], estate: nil)
                }
                try Self.requireCompleteItems(focused)
            } catch let error as HolyMannaBoardClientError {
                // A canonical absent-board reply is absence. Transport failures,
                // malformed replies and other refusals still block resolution.
                guard Self.isMissingBoard(error) else { throw error }
            }
        }
        try Task.checkCancellation()
        let estate = try await client.estate(for: origin)
        guard estate.count == estate.boards.count else {
            throw HolyMannaAskError.unavailable("The estate reply is incomplete. Refresh and try again.")
        }
        var seen = Set<String>()
        if let focusedRoot { seen.insert(focusedRoot) }
        let roots = estate.boards.filter { $0.exists && seen.insert($0.root).inserted }.map(\.root)
        let matches = try await withThrowingTaskGroup(of: HolyMannaStatePayload.self) { group in
            var remaining = roots.makeIterator()
            func enqueue(_ root: String) {
                group.addTask {
                    try Task.checkCancellation()
                    let payload = try await client.state(for: origin.selecting(boardRoot: root))
                    guard payload.root == root else {
                        throw HolyMannaAskError.unavailable("A board answered for a different repository: \(root).")
                    }
                    try Self.requireCompleteItems(payload)
                    return payload
                }
            }
            // Respect the existing host transport rather than flooding the estate.
            for _ in 0..<4 {
                if let root = remaining.next() { enqueue(root) }
            }
            var matches: [HolyMannaStatePayload] = []
            while let payload = try await group.next() {
                if payload.item(id: id) != nil { matches.append(payload) }
                if let root = remaining.next() { enqueue(root) }
            }
            return matches.sorted { $0.root < $1.root }
        }
        return .init(matches: matches, estate: estate)
    }

    private static func isMissingBoard(_ error: HolyMannaBoardClientError) -> Bool {
        switch error {
        case let .rejected(_, reason, _):
            return reason.hasPrefix("Storage not initialized.")
        case let .commandFailed(_, _, detail):
            guard let detail, let reply = try? JSONDecoder().decode(MissingBoardReply.self, from: Data(detail.utf8)) else {
                return false
            }
            return !reply.success && reply.error.hasPrefix("Storage not initialized.")
        default:
            return false
        }
    }

    private static func requireCompleteItems(_ payload: HolyMannaStatePayload) throws {
        guard payload.all.count == payload.total,
              Set(payload.all.map(\.id)).count == payload.total else {
            throw HolyMannaAskError.unavailable("The full item list is unavailable for \(payload.name). Refresh and try again.")
        }
    }

    private struct MissingBoardReply: Decodable {
        let success: Bool
        let error: String
    }
}
