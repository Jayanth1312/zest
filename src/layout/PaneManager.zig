const std = @import("std");
const Pane = @import("Pane.zig").Pane;
const PaneTree = @import("PaneTree.zig").PaneTree;
const Direction = @import("PaneTree.zig").Direction;
const NavDir = @import("PaneTree.zig").NavDir;
const SplitLine = @import("PaneTree.zig").SplitLine;
const Command = @import("KeyBindings.zig").Command;
const Font = @import("../renderer/Font.zig");
const FileExplorer = @import("../fileexplorer/FileExplorer.zig");
const SearchMode = @import("../fileexplorer/FileExplorer.zig").SearchMode;

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
    pane_cache: std.ArrayListUnmanaged(*Pane) = .empty,

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
        self.pane_cache.deinit(self.allocator);
        var panes: std.ArrayListUnmanaged(*Pane) = .empty;
        defer panes.deinit(self.allocator);
        self.tree.root.collectPanes(&panes, self.allocator) catch return;

        for (panes.items) |p| {
            p.deinit(self.allocator);
            self.allocator.destroy(p);
        }

        self.tree.deinit();
    }

    pub fn handleResize(self: *PaneManager, fb_width: i32, fb_height: i32) !void {
        self.fb_width = fb_width;
        self.fb_height = fb_height;

        const pad_x = self.padding_x;
        const pad_y = self.padding_y;
        const avail_w = @max(0.0, @as(f32, @floatFromInt(fb_width)) - (pad_x * 2.0));
        const avail_h = @max(0.0, @as(f32, @floatFromInt(fb_height)) - (pad_y * 2.0));

        self.tree.root.calculateBounds(pad_x, pad_y, avail_w, avail_h, self.border_size);

        try self.getVisiblePanesInto(&self.pane_cache);

        const cell_w: f32 = @floatFromInt(self.font.cell_width);
        const cell_h: f32 = @floatFromInt(self.font.cell_height);

        const input_bar_height: f32 = @as(f32, @floatFromInt(self.input_bar_rows)) * cell_h;

        for (self.pane_cache.items) |p| {
            const inner_w = p.width - (self.inner_padding * 2.0);
            const inner_h = p.height - (self.inner_padding * 2.0) - input_bar_height;
            const new_cols = @max(1, @as(u32, @intFromFloat(@max(0.0, inner_w) / cell_w)));
            const new_rows = @max(1, @as(u32, @intFromFloat(@max(0.0, inner_h) / cell_h)));
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

    pub fn getVisiblePanesInto(self: *PaneManager, out: *std.ArrayListUnmanaged(*Pane)) !void {
        out.clearRetainingCapacity();
        try self.tree.root.collectPanes(out, self.allocator);
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
            .toggleExplorer => {
                if (self.getFocusedPane()) |pane| {
                    if (pane.file_explorer == null) {
                        const home = std.c.getenv("HOME") orelse "/home";
                        const home_str = std.mem.span(home);
                        try pane.initExplorer(self.allocator, home_str);
                    }
                    if (pane.file_explorer) |explorer| {
                        const cell_h: f32 = @floatFromInt(self.font.cell_height);
                        const inner_h = pane.height - (self.inner_padding * 2.0);
                        const total_rows = @as(u32, @intFromFloat(inner_h / cell_h));
                        const cell_w: f32 = @floatFromInt(self.font.cell_width);
                        const inner_w = pane.width - (self.inner_padding * 2.0);
                        const total_cols = @as(u32, @intFromFloat(inner_w / cell_w));
                        explorer.toggle(&pane.terminal.grid, total_cols, total_rows);
                    }
                }
            },
            .explorerUp => {
                if (self.getFocusedPane()) |pane| {
                    if (pane.file_explorer) |explorer| {
                        const visible_rows = self.getExplorerVisibleRows(pane);
                        explorer.navigateUp(visible_rows);
                    }
                }
            },
            .explorerDown => {
                if (self.getFocusedPane()) |pane| {
                    if (pane.file_explorer) |explorer| {
                        const visible_rows = self.getExplorerVisibleRows(pane);
                        explorer.navigateDown(visible_rows);
                    }
                }
            },
            .explorerSelect => {
                if (self.getFocusedPane()) |pane| {
                    if (pane.file_explorer) |explorer| {
                        if (explorer.searching) {
                            if (explorer.search_len > 0) {
                                if (explorer.selectEntry() catch null) |file_path| {
                                    const open_cmd = try std.fmt.allocPrint(self.allocator, "xdg-open \"{s}\" &\n", .{file_path});
                                    defer self.allocator.free(open_cmd);
                                    try pane.write(open_cmd);
                                }
                                explorer.cancelSearch();
                            } else {
                                explorer.cancelSearch();
                            }
                        } else {
                            if (explorer.selectEntry() catch null) |file_path| {
                                const open_cmd = try std.fmt.allocPrint(self.allocator, "xdg-open \"{s}\" &\n", .{file_path});
                                defer self.allocator.free(open_cmd);
                                try pane.write(open_cmd);
                            }
                        }
                    }
                }
            },
            .explorerCtrlSelect => {
                if (self.getFocusedPane()) |pane| {
                    if (pane.file_explorer) |explorer| {
                        if (explorer.getSelectedPath()) |path| {
                            const kind = explorer.getSelectedKind() orelse return;
                            if (kind == .directory) {
                                const cd_cmd = try std.fmt.allocPrint(self.allocator, "cd \"{s}\"\n", .{path});
                                defer self.allocator.free(cd_cmd);
                                try pane.write(cd_cmd);
                            } else {
                                const open_cmd = try std.fmt.allocPrint(self.allocator, "xdg-open \"{s}\" &\n", .{path});
                                defer self.allocator.free(open_cmd);
                                try pane.write(open_cmd);
                            }
                            explorer.close(&pane.terminal.grid);
                        }
                    }
                }
            },
            .explorerBack => {
                if (self.getFocusedPane()) |pane| {
                    if (pane.file_explorer) |explorer| {
                        if (explorer.searching) {
                            if (explorer.search_len > 0) {
                                explorer.removeSearchChar();
                            } else {
                                explorer.cancelSearch();
                            }
                        } else {
                            try explorer.goBack();
                        }
                    }
                }
            },
            .explorerSearch => {
                if (self.getFocusedPane()) |pane| {
                    if (pane.file_explorer) |explorer| {
                        if (!explorer.searching) {
                            explorer.startSearch(.both);
                        }
                    }
                }
            },
            .explorerSearchFiles => {
                if (self.getFocusedPane()) |pane| {
                    if (pane.file_explorer) |explorer| {
                        if (!explorer.searching) {
                            explorer.startSearch(.files_only);
                        }
                    }
                }
            },
            .explorerSearchDirs => {
                if (self.getFocusedPane()) |pane| {
                    if (pane.file_explorer) |explorer| {
                        if (!explorer.searching) {
                            explorer.startSearch(.dirs_only);
                        }
                    }
                }
            },
            .explorerCancelSearch => {
                if (self.getFocusedPane()) |pane| {
                    if (pane.file_explorer) |explorer| {
                        if (explorer.searching) {
                            explorer.cancelSearch();
                        } else {
                            const cell_h: f32 = @floatFromInt(self.font.cell_height);
                            const inner_h = pane.height - (self.inner_padding * 2.0);
                            const total_rows = @as(u32, @intFromFloat(inner_h / cell_h));
                            const cell_w: f32 = @floatFromInt(self.font.cell_width);
                            const inner_w = pane.width - (self.inner_padding * 2.0);
                            const total_cols = @as(u32, @intFromFloat(inner_w / cell_w));
                            explorer.close(&pane.terminal.grid);
                            _ = total_rows;
                            _ = total_cols;
                        }
                    }
                }
            },
            .explorerSearchChar => {},
            .explorerSearchBackspace => {
                if (self.getFocusedPane()) |pane| {
                    if (pane.file_explorer) |explorer| {
                        if (explorer.searching) {
                            explorer.removeSearchChar();
                        }
                    }
                }
            },
            .none => {},
        }
    }

    fn getExplorerVisibleRows(self: *PaneManager, pane: *Pane) usize {
        const cell_h: f32 = @floatFromInt(self.font.cell_height);
        const inner_h = pane.height - (self.inner_padding * 2.0);
        const total_rows = @as(u32, @intFromFloat(inner_h / cell_h));
        const header_rows: u32 = 3;
        const footer_rows: u32 = 1;
        if (total_rows > header_rows + footer_rows) {
            return @intCast(total_rows - header_rows - footer_rows);
        }
        return 0;
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

    pub fn isExplorerActive(self: *PaneManager) bool {
        if (self.getFocusedPane()) |pane| {
            return pane.hasExplorer();
        }
        return false;
    }

    pub fn handleExplorerClick(self: *PaneManager, fb_x: f32, fb_y: f32, ctrl: bool) bool {
        if (self.getFocusedPane()) |pane| {
            if (pane.file_explorer) |explorer| {
                if (!explorer.visible) return false;

                const cell_w: f32 = @floatFromInt(self.font.cell_width);
                const cell_h: f32 = @floatFromInt(self.font.cell_height);

                const rel_x = fb_x - pane.x - self.inner_padding;
                const rel_y = fb_y - pane.y - self.inner_padding;

                const col: u32 = @intFromFloat(rel_x / cell_w);
                const row: u32 = @intFromFloat(rel_y / cell_h);

                const inner_h = pane.height - (self.inner_padding * 2.0);
                const total_rows = @as(u32, @intFromFloat(inner_h / cell_h));

                if (explorer.handleClick(col, row, total_rows)) |_| {
                    if (ctrl) {
                        if (explorer.getSelectedPath()) |path| {
                            const kind = explorer.getSelectedKind() orelse return true;
                            if (kind == .directory) {
                                const cd_cmd = std.fmt.allocPrint(self.allocator, "cd \"{s}\"\n", .{path}) catch return true;
                                defer self.allocator.free(cd_cmd);
                                pane.write(cd_cmd) catch {};
                            } else {
                                const open_cmd = std.fmt.allocPrint(self.allocator, "xdg-open \"{s}\" &\n", .{path}) catch return true;
                                defer self.allocator.free(open_cmd);
                                pane.write(open_cmd) catch {};
                            }
                            explorer.close(&pane.terminal.grid);
                            return true;
                        }
                    } else {
                        if (explorer.selectEntry() catch null) |file_path| {
                            const open_cmd = std.fmt.allocPrint(self.allocator, "xdg-open \"{s}\" &\n", .{file_path}) catch return true;
                            defer self.allocator.free(open_cmd);
                            pane.write(open_cmd) catch {};
                            return true;
                        }
                        return true;
                    }
                }
            }
        }
        return false;
    }
};
