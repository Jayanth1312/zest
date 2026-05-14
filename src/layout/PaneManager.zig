const std = @import("std");
const Pane = @import("Pane.zig").Pane;
const PaneTree = @import("PaneTree.zig").PaneTree;
const Direction = @import("PaneTree.zig").Direction;
const NavDir = @import("PaneTree.zig").NavDir;
const SplitLine = @import("PaneTree.zig").SplitLine;
const Command = @import("KeyBindings.zig").Command;
const Font = @import("../renderer/Font.zig");

pub const Alignment = enum { top, center, bottom };

pub const PaneManager = struct {
    tree: PaneTree,
    allocator: std.mem.Allocator,
    font: *Font.Font,
    fb_width: i32 = 0,
    fb_height: i32 = 0,
    padding_x: f32 = 8.0,
    padding_y: f32 = 8.0,
    border_size: f32 = 1.5,
    inner_padding: f32 = 4.0,
    alignment: Alignment = .top,
    input_bar_rows: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, font: *Font.Font, initial_cols: u32, initial_rows: u32) !PaneManager {
        const pane = try allocator.create(Pane);
        pane.* = try Pane.init(allocator, 0, initial_cols, initial_rows);
        pane.focused = true;

        const tree = try PaneTree.init(allocator, pane);

        return PaneManager{
            .tree = tree,
            .allocator = allocator,
            .font = font,
        };
    }

    pub fn deinit(self: *PaneManager) void {
        var panes: std.ArrayListUnmanaged(*Pane) = .empty;
        defer panes.deinit(self.allocator);
        self.tree.root.collectPanes(&panes, self.allocator) catch return;

        for (panes.items) |p| {
            p.deinit();
            self.allocator.destroy(p);
        }

        self.tree.deinit();
    }

    pub fn handleResize(self: *PaneManager, fb_width: i32, fb_height: i32) !void {
        self.fb_width = fb_width;
        self.fb_height = fb_height;

        std.debug.print("handleResize: fb={}x{}\n", .{ fb_width, fb_height });

        const pad_x = self.padding_x;
        const pad_y = self.padding_y;
        const avail_w = @max(0.0, @as(f32, @floatFromInt(fb_width)) - (pad_x * 2.0));
        const avail_h = @max(0.0, @as(f32, @floatFromInt(fb_height)) - (pad_y * 2.0));

        self.tree.root.calculateBounds(pad_x, pad_y, avail_w, avail_h, self.border_size);

        var panes: std.ArrayListUnmanaged(*Pane) = .empty;
        defer panes.deinit(self.allocator);
        try self.tree.root.collectPanes(&panes, self.allocator);

        std.debug.print("handleResize: {} panes found\n", .{panes.items.len});

        const cell_w: f32 = @floatFromInt(self.font.cell_width);
        const cell_h: f32 = @floatFromInt(self.font.cell_height);

        const input_bar_height: f32 = @as(f32, @floatFromInt(self.input_bar_rows)) * cell_h;

        for (panes.items) |p| {
            std.debug.print("  pane {}: bounds=({:.1},{:.1}) {:.1}x{:.1}\n", .{ p.id, p.x, p.y, p.width, p.height });
            const inner_w = p.width - (self.inner_padding * 2.0);
            const inner_h = p.height - (self.inner_padding * 2.0) - input_bar_height;
            const new_cols = @max(1, @as(u32, @intFromFloat(@max(0.0, inner_w) / cell_w)));
            const new_rows = @max(1, @as(u32, @intFromFloat(@max(0.0, inner_h) / cell_h)));
            std.debug.print("    cols={} rows={}\n", .{ new_cols, new_rows });
            if (new_cols != p.cols or new_rows != p.rows) {
                try p.resize(new_cols, new_rows);
            }
        }
    }

    pub fn getVisiblePanes(self: *PaneManager) !std.ArrayListUnmanaged(*Pane) {
        var list: std.ArrayListUnmanaged(*Pane) = .empty;
        try self.tree.root.collectPanes(&list, self.allocator);
        return list;
    }

    pub fn getFocusedPane(self: *PaneManager) ?*Pane {
        return self.tree.root.findFocused();
    }

    pub fn findPaneAt(self: *PaneManager, px: f32, py: f32) ?*Pane {
        return self.tree.root.findPaneAt(px, py);
    }

    pub fn executeCommand(self: *PaneManager, cmd: Command) !void {
        switch (cmd) {
            .splitHorizontal => {
                _ = try self.tree.splitFocused(.horizontal, 0.5);
                try self.handleResize(self.fb_width, self.fb_height);
            },
            .splitVertical => {
                _ = try self.tree.splitFocused(.vertical, 0.5);
                try self.handleResize(self.fb_width, self.fb_height);
            },
            .closePane => {
                if (self.tree.countPanes() <= 1) return;
                _ = try self.tree.closeFocused();
                try self.handleResize(self.fb_width, self.fb_height);
            },
            .focusUp => self.tree.navigateFocus(.up),
            .focusDown => self.tree.navigateFocus(.down),
            .focusLeft => self.tree.navigateFocus(.left),
            .focusRight => self.tree.navigateFocus(.right),
            .none => {},
        }
    }

    pub fn getSplitLines(self: *PaneManager) !std.ArrayListUnmanaged(SplitLine) {
        var list: std.ArrayListUnmanaged(SplitLine) = .empty;
        try self.tree.collectSplitLines(self.fb_width, self.fb_height, self.padding_x, self.padding_y, &list, self.allocator);
        return list;
    }

    pub fn tick(self: *PaneManager, _: f64) void {
        _ = self;
    }

pub fn computeVerticalOffset(self: *PaneManager, pane: *Pane) f32 {
        if (pane.terminal.using_alt_screen) {
            return pane.y + self.inner_padding;
        }

        const cell_h: f32 = @floatFromInt(self.font.cell_height);
        const input_bar_height: f32 = @as(f32, @floatFromInt(self.input_bar_rows)) * cell_h;
        const avail_h = pane.height - (self.inner_padding * 2.0) - input_bar_height;
        
        // THE FIX: Find the lowest line that either has text OR has the cursor
        const last_used = pane.terminal.grid.getLastUsedRow();
        const active_row = @max(pane.terminal.cursor_row, last_used);
        
        const content_h = @as(f32, @floatFromInt(active_row + 1)) * cell_h;
        
        if (content_h < avail_h) {
            return pane.y + self.inner_padding + (avail_h - content_h);
        }
        
        return pane.y + self.inner_padding;
    }

    pub fn getInputBarRect(self: *PaneManager, pane: *Pane) struct { x: f32, y: f32, width: f32, height: f32 } {
        const cell_h: f32 = @floatFromInt(self.font.cell_height);
        const input_bar_height: f32 = @as(f32, @floatFromInt(self.input_bar_rows)) * cell_h;
        const inner_w = pane.width - (self.inner_padding * 2.0);

        return .{
            .x = pane.x + self.inner_padding,
            .y = pane.y + pane.height - self.inner_padding - input_bar_height,
            .width = inner_w,
            .height = input_bar_height,
        };
    }
};
