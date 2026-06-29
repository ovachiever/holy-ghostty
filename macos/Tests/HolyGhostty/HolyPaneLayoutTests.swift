import Foundation
import Testing
@testable import Ghostty

struct HolyPaneLayoutTests {
    @Test func assignmentKeepsPositionalSlot() {
        let first = UUID()
        let layout = HolyPaneLayout(kind: .single, sessionIDs: [])
            .assigning(first, toSlot: 4)

        #expect(layout.kind == .quad)
        #expect(layout.sessionID(atSlot: 1) == nil)
        #expect(layout.sessionID(atSlot: 4) == first)
        #expect(layout.slot(for: first) == 4)
    }

    @Test func assigningExistingSessionMovesIt() {
        let first = UUID()
        let second = UUID()
        let layout = HolyPaneLayout(kind: .quad, slotSessionIDs: [first, second, nil, nil])
            .assigning(first, toSlot: 3)

        #expect(layout.sessionID(atSlot: 1) == nil)
        #expect(layout.sessionID(atSlot: 2) == second)
        #expect(layout.sessionID(atSlot: 3) == first)
        #expect(layout.sessionIDs == [second, first])
    }

    @Test func removeShrinksToHighestOccupiedSlot() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let layout = HolyPaneLayout(kind: .quad, slotSessionIDs: [first, second, third, nil])
            .removingSession(second)

        #expect(layout.kind == .triple)
        #expect(layout.sessionID(atSlot: 1) == first)
        #expect(layout.sessionID(atSlot: 2) == nil)
        #expect(layout.sessionID(atSlot: 3) == third)
    }

    @Test func singleRemainingFirstSlotDissolvesToSingle() {
        let first = UUID()
        let second = UUID()
        let layout = HolyPaneLayout(kind: .splitRight, slotSessionIDs: [first, second, nil, nil])
            .removingSession(second)

        #expect(layout.kind == .single)
        #expect(layout.sessionID(atSlot: 1) == first)
    }

    @Test func singleRemainingHigherSlotKeepsPaneAddressVisible() {
        let first = UUID()
        let third = UUID()
        let layout = HolyPaneLayout(kind: .triple, slotSessionIDs: [first, nil, third, nil])
            .removingSession(first)

        #expect(layout.kind == .triple)
        #expect(layout.sessionID(atSlot: 1) == nil)
        #expect(layout.sessionID(atSlot: 3) == third)
    }

    @Test func normalizationDropsDeadSessionsWithoutPackingSlots() {
        let first = UUID()
        let missing = UUID()
        let fourth = UUID()
        let layout = HolyPaneLayout(kind: .quad, slotSessionIDs: [first, missing, nil, fourth])
            .normalized(
                availableSessionIDs: [first, fourth],
                selectedSessionID: first
            )

        #expect(layout.kind == .quad)
        #expect(layout.sessionID(atSlot: 1) == first)
        #expect(layout.sessionID(atSlot: 2) == nil)
        #expect(layout.sessionID(atSlot: 4) == fourth)
    }

    @Test func normalizationCanLeaveRemovedSelectedSessionOutOfSlots() {
        let session = UUID()
        let layout = HolyPaneLayout(kind: .splitRight, slotSessionIDs: [session, nil, nil, nil])
            .removingSession(session)
            .normalized(
                availableSessionIDs: [session],
                selectedSessionID: session,
                fillsEmptySlots: false
            )

        #expect(layout.kind == .single)
        #expect(layout.sessionIDs.isEmpty)
    }

    @Test func legacySessionIDsDecodeIntoPackedSlots() throws {
        let first = UUID()
        let second = UUID()
        let data = Data(
            """
            {
              "kind": "splitRight",
              "sessionIDs": [
                "\(first.uuidString)",
                "\(second.uuidString)"
              ]
            }
            """.utf8
        )

        let layout = try JSONDecoder().decode(HolyPaneLayout.self, from: data)

        #expect(layout.kind == .splitRight)
        #expect(layout.sessionID(atSlot: 1) == first)
        #expect(layout.sessionID(atSlot: 2) == second)
    }
}
