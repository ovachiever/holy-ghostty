import AppKit
import SwiftUI
import Testing
@testable import Ghostty

/// App-hosted: build during a no-launch lane; execute at coordinated acceptance.
/// These fixtures use responder probes and create no terminal or tmux sessions.
@MainActor
@Suite(.serialized)
struct HolyWorkspaceTerminalMouseTests {
    @Test(arguments: [false, true])
    func decorativeFrameLeavesTerminalAsMouseTarget(halo: Bool) throws {
        let surface = MouseProbeView(frame: .zero)
        let hosting = NSHostingView(rootView:
            HolyGhosttySurfaceFrame(halo: halo) {
                MouseProbeRepresentable(view: surface)
            }
            .frame(width: 600, height: 400)
        )
        let window = makeWindow()
        defer { window.close() }
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        #expect(surface.window === window)
        #expect(surface.bounds.width > 0)

        // Use nested view coordinates, just as the workspace's inset frame
        // requires. The border and its clear interior must both pass through.
        for point in [NSPoint(x: 1, y: 200), NSPoint(x: 80, y: 80), NSPoint(x: 300, y: 200)] {
            let location = hosting.convert(point, from: surface)
            let target = try #require(hosting.hitTest(location))
            #expect(target === surface)
            for flags: NSEvent.ModifierFlags in [.command, []] {
                let event = try #require(NSEvent.mouseEvent(
                    with: .leftMouseDown,
                    location: surface.convert(point, to: nil),
                    modifierFlags: flags,
                    timestamp: 1,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 1,
                    clickCount: 1,
                    pressure: 1
                ))
                target.mouseDown(with: event)
                #expect(surface.clicks.last === event)
            }
        }
    }

    @Test func modifiersReachUnfocusedPanesWithoutDuplicatingFirstResponder() throws {
        let window = makeWindow()
        defer { window.close() }
        let focused = addProbe(to: window)
        let unfocused = addProbe(to: window, x: 150)
        #expect(window.makeFirstResponder(focused))

        for flags: NSEvent.ModifierFlags in [.command, []] {
            let event = try modifierEvent(in: window, flags: flags)
            let returned = HolyWorkspaceWindowController.forwardModifierEvent(
                event, in: window, to: [focused, unfocused]
            )
            #expect(returned === event)
            #expect(unfocused.modifiers.last === event)
            #expect(focused.modifiers.isEmpty)
        }
        #expect(unfocused.modifiers.count == 2)
    }

    @Test func modifiersReachPanesWhileTextFieldHasKeyboardFocus() throws {
        let window = makeWindow()
        defer { window.close() }
        let surface = addProbe(to: window)
        let field = NSTextField(frame: NSRect(x: 150, y: 0, width: 100, height: 24))
        window.contentView?.addSubview(field)
        #expect(window.makeFirstResponder(field))
        let event = try modifierEvent(in: window, flags: .command)
        _ = HolyWorkspaceWindowController.forwardModifierEvent(event, in: window, to: [surface])
        #expect(surface.modifiers.count == 1)
    }

    @Test func releaseFromAnotherWindowClearsHoverButSkipsUnmountedPanes() throws {
        let window = makeWindow()
        let otherWindow = makeWindow()
        defer {
            window.close()
            otherWindow.close()
        }
        let contentView = try #require(window.contentView)
        contentView.clipsToBounds = false
        let visible = addProbe(to: window)
        let hidden = addProbe(to: window, x: 150)
        hidden.isHidden = true
        let clipped = addProbe(to: window, x: 1_000)
        #expect(!clipped.visibleRect.isEmpty)
        let foreign = addProbe(to: otherWindow)
        let detached = MouseProbeView(frame: visible.frame)
        #expect(window.makeFirstResponder(visible))
        let event = try modifierEvent(in: otherWindow, flags: [])
        _ = HolyWorkspaceWindowController.forwardModifierEvent(
            event, in: window, to: [visible, hidden, clipped, foreign, detached]
        )
        #expect(visible.modifiers.count == 1)
        #expect(hidden.modifiers.isEmpty)
        #expect(clipped.modifiers.isEmpty)
        #expect(foreign.modifiers.isEmpty)
        #expect(detached.modifiers.isEmpty)
    }

    @Test func releaseReachesPartiallyVisibleNestedPaneButSkipsPaneBeyondWindow() throws {
        let window = makeWindow()
        let otherWindow = makeWindow()
        defer {
            window.close()
            otherWindow.close()
        }
        let contentView = try #require(window.contentView)
        contentView.clipsToBounds = false
        let container = NSView(frame: NSRect(x: 500, y: 50, width: 100, height: 200))
        container.bounds.origin = NSPoint(x: 25, y: 10)
        container.clipsToBounds = false
        contentView.addSubview(container)
        // The panes straddle or lie beyond the window's right edge after the
        // container's offset and bounds origin are applied.
        let partial = MouseProbeView(frame: NSRect(x: 75, y: 10, width: 100, height: 100))
        let outside = MouseProbeView(frame: NSRect(x: 125, y: 10, width: 100, height: 100))
        container.addSubview(partial)
        container.addSubview(outside)
        #expect(!partial.visibleRect.isEmpty)
        #expect(!outside.visibleRect.isEmpty)
        #expect(window.makeFirstResponder(partial))

        let event = try modifierEvent(in: otherWindow, flags: [])
        let returned = HolyWorkspaceWindowController.forwardModifierEvent(
            event, in: window, to: [partial, outside]
        )
        #expect(returned === event)
        #expect(partial.modifiers.count == 1)
        #expect(partial.modifiers.last === event)
        #expect(outside.modifiers.isEmpty)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    private func addProbe(to window: NSWindow, x: CGFloat = 0) -> MouseProbeView {
        let view = MouseProbeView(frame: NSRect(x: x, y: 0, width: 100, height: 100))
        window.contentView?.addSubview(view)
        return view
    }

    private func modifierEvent(in window: NSWindow, flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: flags,
            timestamp: 1,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 0x37
        ))
    }
}

private struct MouseProbeRepresentable: NSViewRepresentable {
    let view: MouseProbeView
    func makeNSView(context: Context) -> MouseProbeView { view }
    func updateNSView(_ nsView: MouseProbeView, context: Context) {}
}

private final class MouseProbeView: NSView {
    var modifiers: [NSEvent] = []
    var clicks: [NSEvent] = []
    override var acceptsFirstResponder: Bool { true }
    override func flagsChanged(with event: NSEvent) { modifiers.append(event) }
    override func mouseDown(with event: NSEvent) { clicks.append(event) }
}
