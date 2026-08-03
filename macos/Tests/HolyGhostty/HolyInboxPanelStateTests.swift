import Foundation
import Testing
@testable import Ghostty

// Panel state law: one right-hand region, toggled not stacked; width stays
// inside the range where rows read comfortably and the terminal stays usable;
// the badge says a number only when the number is true.
struct HolyInboxPanelStateTests {
    // MARK: - Toggle

    @Test func togglingFlipsBetweenHiddenAndInbox() {
        #expect(HolyInboxPanelLayout.toggled(nil) == .inbox)
        #expect(HolyInboxPanelLayout.toggled(.inbox) == nil)
    }

    // MARK: - Width

    @Test func widthClampsToPanelRange() {
        #expect(HolyInboxPanelLayout.clampedWidth(100, available: 2000, reservedLeft: 700) == 300)
        #expect(HolyInboxPanelLayout.clampedWidth(360, available: 2000, reservedLeft: 700) == 360)
        #expect(HolyInboxPanelLayout.clampedWidth(900, available: 2000, reservedLeft: 700) == 480)
    }

    @Test func widthYieldsToTheTerminalOnNarrowWindows() {
        // available 1100 - reserved 700 leaves 400: the panel may not take 480.
        #expect(HolyInboxPanelLayout.clampedWidth(480, available: 1100, reservedLeft: 700) == 400)
        // Never below the floor, even when the window is tiny.
        #expect(HolyInboxPanelLayout.clampedWidth(480, available: 800, reservedLeft: 700) == 300)
    }

    // MARK: - Badge

    @Test func badgeLabelIsHonest() {
        #expect(HolyInboxBadge.label(for: 0) == nil)
        #expect(HolyInboxBadge.label(for: 3) == "3")
        #expect(HolyInboxBadge.label(for: 99) == "99")
        #expect(HolyInboxBadge.label(for: 240) == "99+")
    }
}
