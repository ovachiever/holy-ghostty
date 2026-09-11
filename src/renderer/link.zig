const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const oni = @import("oniguruma");
const inputpkg = @import("../input.zig");
const terminal = @import("../terminal/main.zig");
const point = terminal.point;
const Screen = terminal.Screen;
const Terminal = terminal.Terminal;

const log = std.log.scoped(.renderer_link);

/// Renderer-only styling. These rules do not add clickable input links.
pub const CellStyle = struct {
    foreground: ?terminal.color.RGB = null,
    underline: bool = false,
};

pub const CellMap = std.AutoArrayHashMapUnmanaged(point.Coordinate, CellStyle);

const manna_regex = "\\bmn-[a-f0-9]{6,}\\b";

/// The link configuration needed for renderers.
pub const Link = struct {
    /// The regular expression to match the link against.
    regex: oni.Regex,

    /// The situations in which the link should be highlighted.
    highlight: inputpkg.Link.Highlight,

    style: CellStyle = .{ .underline = true },

    pub fn deinit(self: *Link) void {
        self.regex.deinit();
    }
};

/// A set of links. This provides a higher level API for renderers
/// to match against a viewport and determine if cells are part of
/// a link.
pub const Set = struct {
    links: []Link,

    /// Returns the slice of links from the configuration.
    pub fn fromConfig(
        alloc: Allocator,
        config: []const inputpkg.Link,
        holy_manna_highlight: bool,
        holy_manna_highlight_color: terminal.color.RGB,
    ) !Set {
        var links: std.ArrayList(Link) = .empty;
        defer links.deinit(alloc);
        errdefer for (links.items) |*link| link.deinit();

        for (config) |link| {
            var regex = try link.oniRegex();
            errdefer regex.deinit();
            try links.append(alloc, .{
                .regex = regex,
                .highlight = link.highlight,
            });
        }

        if (holy_manna_highlight) {
            var regex = try oni.Regex.init(
                manna_regex,
                .{},
                oni.Encoding.utf8,
                oni.Syntax.default,
                null,
            );
            errdefer regex.deinit();
            try links.append(alloc, .{
                .regex = regex,
                .highlight = .always,
                .style = .{ .foreground = holy_manna_highlight_color },
            });
        }

        return .{ .links = try links.toOwnedSlice(alloc) };
    }

    pub fn deinit(self: *Set, alloc: Allocator) void {
        for (self.links) |*link| link.deinit();
        alloc.free(self.links);
    }

    /// Fills matches with the matches from regex link matches.
    pub fn renderCellMap(
        self: *const Set,
        alloc: Allocator,
        result: *CellMap,
        render_state: *const terminal.RenderState,
        mouse_viewport: ?point.Coordinate,
        mouse_mods: inputpkg.Mods,
    ) !void {
        // Fast path, not very likely since we have default links.
        if (self.links.len == 0) return;

        // Convert our render state to a string + byte map.
        var builder: std.Io.Writer.Allocating = .init(alloc);
        defer builder.deinit();
        var map: terminal.RenderState.StringMap = .empty;
        defer map.deinit(alloc);
        try render_state.string(&builder.writer, .{
            .alloc = alloc,
            .map = &map,
        });

        const str = builder.writer.buffered();

        // Go through each link and see if we have any matches.
        for (self.links) |*link| {
            // Determine if our highlight conditions are met. We use a
            // switch here instead of an if so that we can get a compile
            // error if any other conditions are added.
            switch (link.highlight) {
                .always => {},
                .always_mods => |v| if (!mouse_mods.equal(v)) continue,

                // We check the hover points later.
                .hover => if (mouse_viewport == null) continue,
                .hover_mods => |v| {
                    if (mouse_viewport == null) continue;
                    if (!mouse_mods.equal(v)) continue;
                },
            }

            var offset: usize = 0;
            while (offset < str.len) {
                var region = link.regex.search(
                    str[offset..],
                    .{},
                ) catch |err| switch (err) {
                    error.Mismatch => break,
                    else => return err,
                };
                defer region.deinit();

                // We have a match!
                const offset_start: usize = @intCast(region.starts()[0]);
                const offset_end: usize = @intCast(region.ends()[0]);
                const start = offset + offset_start;
                const end = offset + offset_end;

                // Increment our offset by the number of bytes in the match.
                // We defer this so that we can return the match before
                // modifying the offset.
                defer offset = end;

                switch (link.highlight) {
                    .always, .always_mods => {},
                    .hover, .hover_mods => if (mouse_viewport) |vp| {
                        for (map.items[start..end]) |pt| {
                            if (pt.eql(vp)) break;
                        } else continue;
                    } else continue,
                }

                // Record the match
                for (map.items[start..end]) |pt| {
                    const entry = try result.getOrPut(alloc, pt);
                    if (!entry.found_existing) entry.value_ptr.* = .{};
                    // Earlier foreground rules win. URL/OSC8 hover decoration
                    // can coexist with the built-in foreground rule.
                    if (entry.value_ptr.foreground == null)
                        entry.value_ptr.foreground = link.style.foreground;
                    entry.value_ptr.underline = entry.value_ptr.underline or link.style.underline;
                }
            }
        }
    }
};

/// Invalidate cached rows when their renderer-only styling changes, including
/// the unchanged prefix of an ID completed or invalidated on a wrapped row.
/// Unchanged maps leave clean rows alone during animation and streaming.
pub fn updateCellMap(
    alloc: Allocator,
    previous: *CellMap,
    current: *const CellMap,
    state: *terminal.RenderState,
) Allocator.Error!void {
    // Allocate before changing either the dirty flags or the previous map.
    try previous.ensureTotalCapacity(alloc, current.count());
    const dirty = state.row_data.items(.dirty);
    for (
        [2]*const CellMap{ previous, current },
        [2]*const CellMap{ current, previous },
    ) |from, to| {
        for (from.keys(), from.values()) |pt, style| {
            if (to.get(pt)) |other| {
                if (std.meta.eql(style, other)) continue;
            }
            if (pt.y >= dirty.len) continue;
            dirty[pt.y] = true;
            if (state.dirty == .false) state.dirty = .partial;
        }
    }
    previous.clearRetainingCapacity();
    for (current.keys(), current.values()) |pt, style|
        previous.putAssumeCapacity(pt, style);
}

const test_manna_gold: terminal.color.RGB = .{ .r = 0xFF, .g = 0xB8, .b = 0x6C };

test "renderCellMap" {
    const testing = std.testing;
    const alloc = testing.allocator;
    try oni.testing.ensureInit();

    var t: terminal.Terminal = try .init(alloc, .{
        .cols = 5,
        .rows = 3,
    });
    defer t.deinit(alloc);

    var s = t.vtStream();
    defer s.deinit();
    const str = "1ABCD2EFGH\r\n3IJKL";
    s.nextSlice(str);

    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);

    // Get a set
    var set = try Set.fromConfig(alloc, &.{
        .{
            .regex = "AB",
            .action = .{ .open = {} },
            .highlight = .{ .always = {} },
        },

        .{
            .regex = "EF",
            .action = .{ .open = {} },
            .highlight = .{ .always = {} },
        },
    }, false, test_manna_gold);
    defer set.deinit(alloc);

    // Get our matches
    var result: CellMap = .empty;
    defer result.deinit(alloc);
    try set.renderCellMap(
        alloc,
        &result,
        &state,
        null,
        .{},
    );
    try testing.expect(!result.contains(.{ .x = 0, .y = 0 }));
    try testing.expect(result.contains(.{ .x = 1, .y = 0 }));
    try testing.expect(result.contains(.{ .x = 2, .y = 0 }));
    try testing.expect(!result.contains(.{ .x = 3, .y = 0 }));
    try testing.expect(result.contains(.{ .x = 1, .y = 1 }));
    try testing.expect(!result.contains(.{ .x = 1, .y = 2 }));
}

test "renderCellMap hover links" {
    const testing = std.testing;
    const alloc = testing.allocator;
    try oni.testing.ensureInit();

    var t: terminal.Terminal = try .init(alloc, .{
        .cols = 5,
        .rows = 3,
    });
    defer t.deinit(alloc);

    var s = t.vtStream();
    defer s.deinit();
    const str = "1ABCD2EFGH\r\n3IJKL";
    s.nextSlice(str);

    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);

    // Get a set
    var set = try Set.fromConfig(alloc, &.{
        .{
            .regex = "AB",
            .action = .{ .open = {} },
            .highlight = .{ .hover = {} },
        },

        .{
            .regex = "EF",
            .action = .{ .open = {} },
            .highlight = .{ .always = {} },
        },
    }, false, test_manna_gold);
    defer set.deinit(alloc);

    // Not hovering over the first link
    {
        var result: CellMap = .empty;
        defer result.deinit(alloc);
        try set.renderCellMap(
            alloc,
            &result,
            &state,
            null,
            .{},
        );

        // Test our matches
        try testing.expect(!result.contains(.{ .x = 0, .y = 0 }));
        try testing.expect(!result.contains(.{ .x = 1, .y = 0 }));
        try testing.expect(!result.contains(.{ .x = 2, .y = 0 }));
        try testing.expect(!result.contains(.{ .x = 3, .y = 0 }));
        try testing.expect(result.contains(.{ .x = 1, .y = 1 }));
        try testing.expect(!result.contains(.{ .x = 1, .y = 2 }));
    }

    // Hovering over the first link
    {
        var result: CellMap = .empty;
        defer result.deinit(alloc);
        try set.renderCellMap(
            alloc,
            &result,
            &state,
            .{ .x = 1, .y = 0 },
            .{},
        );

        // Test our matches
        try testing.expect(!result.contains(.{ .x = 0, .y = 0 }));
        try testing.expect(result.contains(.{ .x = 1, .y = 0 }));
        try testing.expect(result.contains(.{ .x = 2, .y = 0 }));
        try testing.expect(!result.contains(.{ .x = 3, .y = 0 }));
        try testing.expect(result.contains(.{ .x = 1, .y = 1 }));
        try testing.expect(!result.contains(.{ .x = 1, .y = 2 }));
    }
}

test "renderCellMap mods no match" {
    const testing = std.testing;
    const alloc = testing.allocator;
    try oni.testing.ensureInit();

    var t: terminal.Terminal = try .init(alloc, .{
        .cols = 5,
        .rows = 3,
    });
    defer t.deinit(alloc);

    var s = t.vtStream();
    defer s.deinit();
    const str = "1ABCD2EFGH\r\n3IJKL";
    s.nextSlice(str);

    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);

    // Get a set
    var set = try Set.fromConfig(alloc, &.{
        .{
            .regex = "AB",
            .action = .{ .open = {} },
            .highlight = .{ .always = {} },
        },

        .{
            .regex = "EF",
            .action = .{ .open = {} },
            .highlight = .{ .always_mods = .{ .ctrl = true } },
        },
    }, false, test_manna_gold);
    defer set.deinit(alloc);

    // Get our matches
    var result: CellMap = .empty;
    defer result.deinit(alloc);
    try set.renderCellMap(
        alloc,
        &result,
        &state,
        null,
        .{},
    );

    // Test our matches
    try testing.expect(!result.contains(.{ .x = 0, .y = 0 }));
    try testing.expect(result.contains(.{ .x = 1, .y = 0 }));
    try testing.expect(result.contains(.{ .x = 2, .y = 0 }));
    try testing.expect(!result.contains(.{ .x = 3, .y = 0 }));
    try testing.expect(!result.contains(.{ .x = 1, .y = 1 }));
    try testing.expect(!result.contains(.{ .x = 1, .y = 2 }));
}

test "renderCellMap Manna matcher boundaries" {
    const testing = std.testing;
    const alloc = testing.allocator;
    try oni.testing.ensureInit();

    var set = try Set.fromConfig(alloc, &.{}, true, test_manna_gold);
    defer set.deinit(alloc);

    const cases = [_]struct { text: []const u8, cells: usize }{
        .{ .text = "mn-abcdef", .cells = 9 },
        .{ .text = "(mn-0123456789abcdef).", .cells = 19 },
        .{ .text = "mn-abcdef,mn-123456", .cells = 18 },
        .{ .text = "mn-abcde", .cells = 0 },
        .{ .text = "MN-abcdef", .cells = 0 },
        .{ .text = "mn-ABCDEF", .cells = 0 },
        .{ .text = "mn-abcdeF", .cells = 0 },
        .{ .text = "mn-abcdefG", .cells = 0 },
        .{ .text = "mn-abcdefg", .cells = 0 },
        .{ .text = "xmn-abcdef", .cells = 0 },
        .{ .text = "1mn-abcdef", .cells = 0 },
        .{ .text = "_mn-abcdef", .cells = 0 },
        .{ .text = "mn-abcdef_", .cells = 0 },
        .{ .text = "mn-abcdefmn-123456", .cells = 0 },
        .{ .text = "émn-abcdef", .cells = 0 },
        .{ .text = "mn-abcdefé", .cells = 0 },
    };
    for (cases) |case| {
        var t: terminal.Terminal = try .init(alloc, .{ .cols = 40, .rows = 1 });
        defer t.deinit(alloc);
        var stream = t.vtStream();
        defer stream.deinit();
        stream.nextSlice(case.text);

        var state: terminal.RenderState = .empty;
        defer state.deinit(alloc);
        try state.update(alloc, &t);
        var result: CellMap = .empty;
        defer result.deinit(alloc);
        try set.renderCellMap(alloc, &result, &state, null, .{});

        try testing.expectEqual(case.cells, result.count());
        for (result.values()) |style|
            try testing.expectEqualDeep(CellStyle{ .foreground = test_manna_gold }, style);
    }
}

test "renderCellMap Manna wrapped cell runs" {
    const testing = std.testing;
    const alloc = testing.allocator;
    try oni.testing.ensureInit();

    var t: terminal.Terminal = try .init(alloc, .{ .cols = 6, .rows = 3 });
    defer t.deinit(alloc);
    var stream = t.vtStream();
    defer stream.deinit();
    stream.nextSlice("  mn-abc12345!");

    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);
    var set = try Set.fromConfig(alloc, &.{}, true, test_manna_gold);
    defer set.deinit(alloc);
    var result: CellMap = .empty;
    defer result.deinit(alloc);
    try set.renderCellMap(alloc, &result, &state, null, .{});

    try testing.expectEqual(@as(usize, 11), result.count());
    for (0..18) |i| {
        const style = result.get(.{ .x = @intCast(i % 6), .y = @intCast(i / 6) });
        if (i >= 2 and i < 13) {
            try testing.expectEqualDeep(CellStyle{ .foreground = test_manna_gold }, style.?);
        } else {
            try testing.expect(style == null);
        }
    }
}

test "renderCellMap Manna config off preserves URL hover" {
    const testing = std.testing;
    const alloc = testing.allocator;
    const Config = @import("../config/Config.zig");
    try oni.testing.ensureInit();

    var config = try Config.default(alloc);
    defer config.deinit();
    config.@"holy-manna-highlight" = false;
    var set = try Set.fromConfig(
        alloc,
        config.link.links.items,
        config.@"holy-manna-highlight",
        config.@"holy-manna-highlight-color".toTerminalRGB(),
    );
    defer set.deinit(alloc);
    var t: terminal.Terminal = try .init(alloc, .{ .cols = 40, .rows = 1 });
    defer t.deinit(alloc);
    var stream = t.vtStream();
    defer stream.deinit();
    stream.nextSlice("mn-abcdef https://example.com");
    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);
    var result: CellMap = .empty;
    defer result.deinit(alloc);

    try set.renderCellMap(alloc, &result, &state, null, .{});
    try testing.expectEqual(@as(usize, 0), result.count());
    try set.renderCellMap(alloc, &result, &state, .{ .x = 12, .y = 0 }, inputpkg.ctrlOrSuper(.{}));
    try testing.expectEqual(@as(usize, 19), result.count());
    try testing.expect(!result.contains(.{ .x = 0, .y = 0 }));
    for (result.values()) |style|
        try testing.expectEqualDeep(CellStyle{ .underline = true }, style);
}

test "renderCellMap Manna foreground coexists with URL and OSC8 underline" {
    const testing = std.testing;
    const alloc = testing.allocator;
    const Config = @import("../config/Config.zig");
    try oni.testing.ensureInit();

    var config = try Config.default(alloc);
    defer config.deinit();
    var set = try Set.fromConfig(
        alloc,
        config.link.links.items,
        config.@"holy-manna-highlight",
        config.@"holy-manna-highlight-color".toTerminalRGB(),
    );
    defer set.deinit(alloc);
    var t: terminal.Terminal = try .init(alloc, .{ .cols = 40, .rows = 1 });
    defer t.deinit(alloc);
    var stream = t.vtStream();
    defer stream.deinit();
    stream.nextSlice("https://example.com/mn-abcdef");
    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);
    var result: CellMap = .empty;
    defer result.deinit(alloc);

    try set.renderCellMap(alloc, &result, &state, null, .{});
    try testing.expectEqual(@as(usize, 9), result.count());
    for (result.values()) |style|
        try testing.expectEqualDeep(CellStyle{ .foreground = test_manna_gold }, style);

    result.clearRetainingCapacity();
    // An OSC8 hover contributes the same underline style before regex matching.
    try result.put(alloc, .{ .x = 20, .y = 0 }, .{ .underline = true });
    try set.renderCellMap(alloc, &result, &state, .{ .x = 12, .y = 0 }, inputpkg.ctrlOrSuper(.{}));
    try testing.expectEqual(@as(usize, 29), result.count());
    try testing.expectEqualDeep(CellStyle{ .underline = true }, result.get(.{ .x = 0, .y = 0 }).?);
    try testing.expectEqualDeep(CellStyle{ .underline = true }, result.get(.{ .x = 19, .y = 0 }).?);
    try testing.expectEqualDeep(CellStyle{ .foreground = test_manna_gold, .underline = true }, result.get(.{ .x = 20, .y = 0 }).?);
    try testing.expectEqualDeep(CellStyle{ .foreground = test_manna_gold, .underline = true }, result.get(.{ .x = 28, .y = 0 }).?);
    try testing.expect(!result.contains(.{ .x = 29, .y = 0 }));
}

test "updateCellMap Manna streaming completion invalidation and animation" {
    const testing = std.testing;
    const alloc = testing.allocator;
    try oni.testing.ensureInit();

    var set = try Set.fromConfig(alloc, &.{}, true, test_manna_gold);
    defer set.deinit(alloc);
    var t: terminal.Terminal = try .init(alloc, .{ .cols = 6, .rows = 4 });
    defer t.deinit(alloc);
    var stream = t.vtStream();
    defer stream.deinit();
    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    var previous: CellMap = .empty;
    defer previous.deinit(alloc);
    var current: CellMap = .empty;
    defer current.deinit(alloc);

    stream.nextSlice("mn-abcde");
    try state.update(alloc, &t);
    try set.renderCellMap(alloc, &current, &state, null, .{});
    try updateCellMap(alloc, &previous, &current, &state);
    try testing.expectEqual(@as(usize, 0), previous.count());
    state.dirty = .false;
    @memset(state.row_data.items(.dirty), false);

    // Only the second wrapped row changes, but the prefix must turn blue too.
    stream.nextSlice("f");
    try state.update(alloc, &t);
    try testing.expect(!state.row_data.items(.dirty)[0]);
    current.clearRetainingCapacity();
    try set.renderCellMap(alloc, &current, &state, null, .{});
    try updateCellMap(alloc, &previous, &current, &state);
    try testing.expectEqual(@as(usize, 9), previous.count());
    try testing.expect(state.row_data.items(.dirty)[0]);
    try testing.expect(state.row_data.items(.dirty)[1]);
    state.dirty = .false;
    @memset(state.row_data.items(.dirty), false);

    // A spinner elsewhere leaves the cached prefix and its style intact.
    stream.nextSlice("\x1b[4;1H|");
    try state.update(alloc, &t);
    current.clearRetainingCapacity();
    try set.renderCellMap(alloc, &current, &state, null, .{});
    try updateCellMap(alloc, &previous, &current, &state);
    try testing.expectEqual(@as(usize, 9), previous.count());
    try testing.expect(!state.row_data.items(.dirty)[0]);
    state.dirty = .false;
    @memset(state.row_data.items(.dirty), false);

    // A trailing word character invalidates the entire ID across both rows.
    stream.nextSlice("\x1b[2;4Hg");
    try state.update(alloc, &t);
    try testing.expect(!state.row_data.items(.dirty)[0]);
    current.clearRetainingCapacity();
    try set.renderCellMap(alloc, &current, &state, null, .{});
    try updateCellMap(alloc, &previous, &current, &state);
    try testing.expectEqual(@as(usize, 0), previous.count());
    try testing.expect(state.row_data.items(.dirty)[0]);
    try testing.expect(state.row_data.items(.dirty)[1]);
}

test "updateCellMap Manna config off clears cached styling" {
    const testing = std.testing;
    const alloc = testing.allocator;
    try oni.testing.ensureInit();

    var t: terminal.Terminal = try .init(alloc, .{ .cols = 12, .rows = 1 });
    defer t.deinit(alloc);
    var stream = t.vtStream();
    defer stream.deinit();
    stream.nextSlice("mn-abcdef");
    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);
    var previous: CellMap = .empty;
    defer previous.deinit(alloc);
    var current: CellMap = .empty;
    defer current.deinit(alloc);

    var enabled = try Set.fromConfig(alloc, &.{}, true, test_manna_gold);
    defer enabled.deinit(alloc);
    try enabled.renderCellMap(alloc, &current, &state, null, .{});
    try updateCellMap(alloc, &previous, &current, &state);
    state.dirty = .false;
    @memset(state.row_data.items(.dirty), false);

    var disabled = try Set.fromConfig(alloc, &.{}, false, test_manna_gold);
    defer disabled.deinit(alloc);
    current.clearRetainingCapacity();
    try disabled.renderCellMap(alloc, &current, &state, null, .{});
    try updateCellMap(alloc, &previous, &current, &state);
    try testing.expectEqual(@as(usize, 0), previous.count());
    try testing.expectEqual(.partial, state.dirty);
    try testing.expect(state.row_data.items(.dirty)[0]);
}

test "updateCellMap Manna scrolling remaps viewport rows" {
    const testing = std.testing;
    const alloc = testing.allocator;
    try oni.testing.ensureInit();

    var set = try Set.fromConfig(alloc, &.{}, true, test_manna_gold);
    defer set.deinit(alloc);
    var t: terminal.Terminal = try .init(alloc, .{ .cols = 12, .rows = 3 });
    defer t.deinit(alloc);
    var stream = t.vtStream();
    defer stream.deinit();
    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    var previous: CellMap = .empty;
    defer previous.deinit(alloc);
    var current: CellMap = .empty;
    defer current.deinit(alloc);

    stream.nextSlice("lead\r\nmn-abcdef\r\ntail");
    try state.update(alloc, &t);
    try set.renderCellMap(alloc, &current, &state, null, .{});
    try updateCellMap(alloc, &previous, &current, &state);
    try testing.expect(previous.contains(.{ .x = 0, .y = 1 }));
    state.dirty = .false;
    @memset(state.row_data.items(.dirty), false);

    stream.nextSlice("\r\nnext");
    try state.update(alloc, &t);
    current.clearRetainingCapacity();
    try set.renderCellMap(alloc, &current, &state, null, .{});
    try updateCellMap(alloc, &previous, &current, &state);
    try testing.expectEqual(@as(usize, 9), previous.count());
    for (previous.keys(), previous.values()) |pt, style| {
        try testing.expectEqual(@as(usize, 0), pt.y);
        try testing.expectEqualDeep(CellStyle{ .foreground = test_manna_gold }, style);
    }
    try testing.expect(!previous.contains(.{ .x = 0, .y = 1 }));
}

test "updateCellMap Manna RGB config change updates cached styling" {
    const testing = std.testing;
    const alloc = testing.allocator;
    const Config = @import("../config/Config.zig");
    try oni.testing.ensureInit();

    var config = try Config.default(alloc);
    defer config.deinit();
    var original = try Set.fromConfig(
        alloc,
        config.link.links.items,
        config.@"holy-manna-highlight",
        config.@"holy-manna-highlight-color".toTerminalRGB(),
    );
    defer original.deinit(alloc);
    var t: terminal.Terminal = try .init(alloc, .{ .cols = 12, .rows = 1 });
    defer t.deinit(alloc);
    var stream = t.vtStream();
    defer stream.deinit();
    stream.nextSlice("mn-abcdef");
    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);
    var previous: CellMap = .empty;
    defer previous.deinit(alloc);
    var current: CellMap = .empty;
    defer current.deinit(alloc);

    try original.renderCellMap(alloc, &current, &state, null, .{});
    try updateCellMap(alloc, &previous, &current, &state);
    for (previous.values()) |style|
        try testing.expectEqualDeep(CellStyle{ .foreground = test_manna_gold }, style);
    state.dirty = .false;
    @memset(state.row_data.items(.dirty), false);

    config.@"holy-manna-highlight-color" = .{ .r = 0x12, .g = 0xAB, .b = 0xEF };
    var updated = try Set.fromConfig(
        alloc,
        config.link.links.items,
        config.@"holy-manna-highlight",
        config.@"holy-manna-highlight-color".toTerminalRGB(),
    );
    defer updated.deinit(alloc);
    current.clearRetainingCapacity();
    try updated.renderCellMap(alloc, &current, &state, null, .{});
    try updateCellMap(alloc, &previous, &current, &state);
    try testing.expectEqual(@as(usize, 9), previous.count());
    for (previous.values()) |style|
        try testing.expectEqualDeep(CellStyle{
            .foreground = .{ .r = 0x12, .g = 0xAB, .b = 0xEF },
        }, style);
    try testing.expectEqual(.partial, state.dirty);
    try testing.expect(state.row_data.items(.dirty)[0]);
}
