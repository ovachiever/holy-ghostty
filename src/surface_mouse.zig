/// SurfaceMouse represents mouse helper functionality for the core surface.
///
/// It's currently small in scope; its purpose is to isolate mouse logic that
/// has gotten a bit complex (e.g. pointer shape handling for key events), but
/// the intention is to grow it later so that we can better test said logic).
const SurfaceMouse = @This();

const std = @import("std");
const builtin = @import("builtin");
const input = @import("input.zig");
const terminal = @import("terminal/main.zig");
const MouseShape = terminal.MouseShape;

/// For processing key events; the key that was physically pressed on the
/// keyboard.
physical_key: input.Key,

/// The mouse event tracking mode, if any.
mouse_event: terminal.MouseEvent,

/// The current terminal's mouse shape.
mouse_shape: MouseShape,

/// The last mods state when the last mouse button (whatever it was) was
/// pressed or release.
mods: input.Mods,

/// True if the mouse position is currently over a link.
over_link: bool,

/// True if the mouse pointer is currently hidden.
hidden: bool,

/// Command is a host-side modifier on macOS: the terminal mouse protocol
/// cannot encode it. Links must remain available while tmux captures mice.
pub fn commandLinkOverride(mods: input.Mods) bool {
    return builtin.target.os.tag.isDarwin() and mods.super;
}

/// Link detection uses effective reporting, including the user's reporting
/// toggle. Keep keyboard and pointer hover on the same capture policy.
pub fn linksAllowed(reporting: bool, mods: input.Mods, shift_capture: bool) bool {
    return !reporting or commandLinkOverride(mods) or (mods.shift and !shift_capture);
}

/// A Command-link gesture claimed before its press reaches a mouse-reporting
/// application. Its release also belongs to the terminal, even if cancelled.
/// The caller owns the target string.
pub const LinkClick = struct {
    point: terminal.point.Coordinate,
    screen: terminal.ScreenSet.Key,
    target: [:0]const u8,
    cancelled: bool = false,

    pub fn move(self: *LinkClick, point: terminal.point.Coordinate, screen: terminal.ScreenSet.Key, inside: bool) void {
        if (!inside or !self.point.eql(point) or self.screen != screen) self.cancelled = true;
    }

    pub fn matches(self: LinkClick, point: terminal.point.Coordinate, screen: terminal.ScreenSet.Key, target: []const u8) bool {
        return !self.cancelled and self.point.eql(point) and self.screen == screen and
            std.mem.eql(u8, self.target, target);
    }
};

/// Translates key state to mouse shape (cursor) state, based on a state
/// machine.
///
/// There are 4 current states:
///
/// * text: starting state, displays a text bar.
/// * default: default state when in a mouse tracking mode. (e.g. vim, etc).
///   Displays an arrow pointer.
/// * pointer: default state when over a link. Displays a pointing finger.
/// * crosshair: any above state can transition to this when the rectangle
///   select keys are pressed (ctrl/super+alt).
///
/// Additionally, default can transition back to text if one of the shift keys
/// are pressed during mouse tracking mode.
///
/// Any secondary state transitions back to its default state when the
/// appropriate keys are released.
///
/// null is returned when the mouse shape does not need changing.
pub fn keyToMouseShape(self: SurfaceMouse) ?MouseShape {
    // Filter for appropriate key events
    if (!eligibleMouseShapeKeyEvent(self.physical_key)) return null;

    // Exceptions: link hover or hidden state overrides any other shape
    // processing and does not change state.
    //
    // TODO: As we unravel mouse state, we can fix this to be more explicit.
    if (self.over_link or self.hidden) {
        return null;
    }

    // Set our current default state
    var current_shape_state: MouseShape = undefined;
    if (self.mouse_event != .none) {
        // In mouse tracking mode, should be default (arrow pointer)
        current_shape_state = .default;
    } else {
        // Default terminal mode, should be text (text bar)
        current_shape_state = .text;
    }

    // Transition table.
    //
    // TODO: This could be updated eventually to be a true transition table if
    // we move to a full stateful mouse surface, e.g. very specific inputs
    // transitioning state based on previous state, versus flags like "is the
    // mouse over a link", etc.
    switch (current_shape_state) {
        .default => {
            if (isMouseModeOverrideState(self.mods) and isRectangleSelectState(self.mods)) {
                // Crosshair (rectangle select), only set if we are also
                // overriding (e.g. shift+ctrl+alt)
                return .crosshair;
            } else if (isMouseModeOverrideState(self.mods)) {
                // Normal override state
                return .text;
            } else {
                return .default;
            }
        },

        .text => {
            if (isRectangleSelectState(self.mods)) {
                // Crosshair (rectangle select)
                return .crosshair;
            } else {
                return .text;
            }
        },

        // Fall back on default state
        else => unreachable,
    }
}

fn eligibleMouseShapeKeyEvent(physical_key: input.Key) bool {
    return physical_key.ctrlOrSuper() or
        physical_key.leftOrRightShift() or
        physical_key.leftOrRightAlt();
}

fn isMouseModeOverrideState(mods: input.Mods) bool {
    return mods.shift;
}

test "links under mouse capture" {
    const testing = std.testing;
    // Ordinary tmux input stays captured. Command opens host links on macOS,
    // while Control remains available to terminal applications.
    try testing.expect(!linksAllowed(true, .{}, false));
    try testing.expect(!linksAllowed(true, .{ .ctrl = true }, false));
    try testing.expectEqual(builtin.target.os.tag.isDarwin(), linksAllowed(true, .{ .super = true }, true));
    try testing.expect(linksAllowed(true, .{ .shift = true }, false));
    try testing.expect(!linksAllowed(true, .{ .shift = true }, true));
    // Disabling mouse reporting also restores link detection, even if the
    // terminal program left its mouse-request mode enabled.
    try testing.expect(linksAllowed(false, .{}, true));
}

test "captured link click cancellation and target identity" {
    const testing = std.testing;
    const point: terminal.point.Coordinate = .{ .x = 3, .y = 2 };
    const click: LinkClick = .{ .point = point, .screen = .primary, .target = "https://example.com" };
    try testing.expect(click.matches(point, .primary, "https://example.com"));
    try testing.expect(!click.matches(point, .primary, "https://other.example"));
    try testing.expect(!click.matches(point, .alternate, "https://example.com"));

    var dragged = click;
    dragged.move(.{ .x = 4, .y = 2 }, .primary, true);
    dragged.move(point, .primary, true);
    try testing.expect(!dragged.matches(point, .primary, click.target));

    var exited = click;
    exited.move(point, .primary, false);
    try testing.expect(!exited.matches(point, .primary, click.target));

    var switched = click;
    switched.move(point, .alternate, true);
    try testing.expect(!switched.matches(point, .primary, click.target));
}

/// Returns true if our modifiers put us in a state where dragging
/// should cause a rectangle select.
pub fn isRectangleSelectState(mods: input.Mods) bool {
    return if (comptime builtin.target.os.tag.isDarwin())
        mods.alt
    else
        mods.ctrlOrSuper() and mods.alt;
}

test "keyToMouseShape" {
    const testing = std.testing;

    {
        // No specific key pressed
        const m: SurfaceMouse = .{
            .physical_key = .unidentified,
            .mouse_event = .none,
            .mouse_shape = .progress,
            .mods = .{},
            .over_link = false,
            .hidden = false,
        };

        const got = m.keyToMouseShape();
        try testing.expect(got == null);
    }

    {
        // Over a link. NOTE: This tests that we don't touch the inbound state,
        // not necessarily if we're over a link.
        const m: SurfaceMouse = .{
            .physical_key = .shift_left,
            .mouse_event = .none,
            .mouse_shape = .progress,
            .mods = .{},
            .over_link = true,
            .hidden = false,
        };

        const got = m.keyToMouseShape();
        try testing.expect(got == null);
    }

    {
        // Mouse is currently hidden
        const m: SurfaceMouse = .{
            .physical_key = .shift_left,
            .mouse_event = .none,
            .mouse_shape = .progress,
            .mods = .{},
            .over_link = true,
            .hidden = true,
        };

        const got = m.keyToMouseShape();
        try testing.expect(got == null);
    }

    {
        // default, no mods (mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .shift_left,
            .mouse_event = .x10,
            .mouse_shape = .default,
            .mods = .{},
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .default;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }

    {
        // default -> crosshair (mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .alt_left,
            .mouse_event = .x10,
            .mouse_shape = .default,
            .mods = .{ .ctrl = true, .super = true, .alt = true, .shift = true },
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .crosshair;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }

    {
        // default -> text (mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .shift_left,
            .mouse_event = .x10,
            .mouse_shape = .default,
            .mods = .{ .shift = true },
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .text;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }

    {
        // crosshair -> text (mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .alt_left,
            .mouse_event = .x10,
            .mouse_shape = .crosshair,
            .mods = .{ .shift = true },
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .text;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }

    {
        // crosshair -> default (mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .alt_left,
            .mouse_event = .x10,
            .mouse_shape = .crosshair,
            .mods = .{},
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .default;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }

    {
        // text -> crosshair (mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .alt_left,
            .mouse_event = .x10,
            .mouse_shape = .text,
            .mods = .{ .ctrl = true, .super = true, .alt = true, .shift = true },
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .crosshair;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }

    {
        // text -> default (mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .shift_left,
            .mouse_event = .x10,
            .mouse_shape = .text,
            .mods = .{},
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .default;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }

    {
        // text, no mods (no mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .shift_left,
            .mouse_event = .none,
            .mouse_shape = .text,
            .mods = .{},
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .text;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }

    {
        // text -> crosshair (no mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .alt_left,
            .mouse_event = .none,
            .mouse_shape = .text,
            .mods = .{ .ctrl = true, .super = true, .alt = true },
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .crosshair;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }

    {
        // crosshair -> text (no mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .alt_left,
            .mouse_event = .none,
            .mouse_shape = .crosshair,
            .mods = .{},
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .text;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }
}
