const std = @import("std");
const Grid = @import("../terminal/Grid.zig").Grid;
const Cell = @import("../terminal/Cell.zig");
const Theme = @import("../config/Theme.zig").Theme;
const Settings = @import("../config/Settings.zig").Settings;
const ConfigParser = @import("../config/ConfigParser.zig");

pub const themes = [_][]const u8{
    "default", "dracula", "nord", "solarized-dark",
    "catppuccin", "gruvbox", "tokyo-night",
};

var g_saved_grid: ?Grid = null;
var g_cols: u32 = 0;
var g_rows: u32 = 0;
var g_selected: usize = 0;
var g_original_theme: []const u8 = "";
var g_preview_theme: Theme = undefined;

pub fn isOpen() bool { return g_saved_grid != null; }

pub fn open(grid: *Grid, settings: *const Settings, pane_cols: u32, pane_rows: u32) !void {
    g_cols = pane_cols;
    g_rows = pane_rows;
    g_original_theme = settings.theme;
    
    // Find initial selected index
    g_selected = 0;
    for (themes, 0..) |t, i| {
        if (std.mem.eql(u8, t, settings.theme)) { g_selected = i; break; }
    }

    const total = @as(usize, g_cols) * @as(usize, g_rows);
    const cells = try grid.allocator.alloc(Cell.Cell, total);
    @memcpy(cells, grid.cells[0..total]);
    g_saved_grid = Grid{
        .cells = cells,
        .row_indices = try grid.allocator.dupe(u32, grid.row_indices[0..g_rows]),
        .cols = g_cols,
        .rows = g_rows,
        .allocator = grid.allocator,
    };
    
    try loadPreviewTheme();
    render(grid);
}

pub fn close(grid: *Grid, confirm: bool, settings: *Settings) void {
    if (g_saved_grid) |sg| {
        const total = @as(usize, g_cols) * @as(usize, g_rows);
        @memcpy(grid.cells[0..total], sg.cells[0..total]);
        @constCast(&sg).deinit();
        g_saved_grid = null;
        if (confirm) {
            settings.theme = themes[g_selected];
        }
    }
}

fn loadPreviewTheme() !void {
    const theme_name = themes[g_selected];
    var buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "src/config/themes/{s}.conf", .{theme_name}) catch return;
    
    var map = ConfigParser.parseFile(std.heap.page_allocator, path) catch return;
    defer ConfigParser.deinitMap(&map);
    
    g_preview_theme = try Theme.load(std.heap.page_allocator, &map);
}

pub fn handleKey(grid: *Grid, settings: *Settings, keyval: c_uint, ctrl: bool) bool {
    if (ctrl) return false;
    
    // ESC: close without saving
    if (keyval == 0xFF1B) {
        close(grid, false, settings);
        return true;
    }
    
    // Enter: close and save
    if (keyval == 0xFF0D or keyval == 0xFF8D) {
        close(grid, true, settings);
        return true;
    }
    
    // Navigation
    switch (keyval) {
        0xFF52 => { // Up
            if (g_selected > 0) {
                g_selected -= 1;
                loadPreviewTheme() catch {};
                render(grid);
            }
            return true;
        },
        0xFF54 => { // Down
            if (g_selected < themes.len - 1) {
                g_selected += 1;
                loadPreviewTheme() catch {};
                render(grid);
            }
            return true;
        },
        else => {},
    }
    
    return true; // Eat other keys
}

fn setCell(grid: *Grid, col: u32, row: u32, ch: u21, fg: Cell.Color, bg: Cell.Color, bold: bool) void {
    if (col < g_cols and row < g_rows)
        grid.setCellAt(@intCast(col), @intCast(row), .{ .char = ch, .fg = fg, .bg = bg, .attrs = .{ .bold = bold } });
}

fn writeStr(grid: *Grid, col: *u32, row: u32, str: []const u8, fg: Cell.Color, bg: Cell.Color, bold: bool) void {
    var view = std.unicode.Utf8View.initUnchecked(str);
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| {
        setCell(grid, col.*, row, cp, fg, bg, bold);
        col.* += 1;
    }
}

fn writeChar(grid: *Grid, col: *u32, row: u32, cp: u21, fg: Cell.Color, bg: Cell.Color, bold: bool) void {
    setCell(grid, col.*, row, cp, fg, bg, bold);
    col.* += 1;
}

pub fn render(grid: *Grid) void {
    const W = g_cols;
    const H = g_rows;
    if (W < 40 or H < 20) return;
    
    const sidebar_w: u32 = 24;
    const content_x: u32 = sidebar_w + 2;

    const tc = struct {
        fn from(theme_c: [3]u8) Cell.Color {
            return .{ .r = theme_c[0], .g = theme_c[1], .b = theme_c[2] };
        }
    }.from;
    
    const bg_c = tc(g_preview_theme.background);
    const fg_c = tc(g_preview_theme.foreground);
    
    // Sidebar colors
    const sb_bg = Cell.Color{ .r = 0x0d, .g = 0x0d, .b = 0x0d };
    const sb_fg = Cell.Color{ .r = 0xaa, .g = 0xaa, .b = 0xaa };
    const sb_sel_bg = Cell.Color{ .r = 0x33, .g = 0x33, .b = 0x33 };
    const sb_sel_fg = Cell.Color{ .r = 0x5f, .g = 0x87, .b = 0x87 }; // Zest accent
    
    // Clear entire screen
    for (0..H) |r| {
        for (0..W) |c| {
            if (c < sidebar_w) {
                grid.setCellAt(@intCast(c), @intCast(r), .{ .char = ' ', .fg = sb_fg, .bg = sb_bg });
            } else {
                grid.setCellAt(@intCast(c), @intCast(r), .{ .char = ' ', .fg = fg_c, .bg = bg_c });
            }
        }
    }
    
    // Draw sidebar
    for (themes, 0..) |t, i| {
        const is_sel = i == g_selected;
        const r_bg = if (is_sel) sb_sel_bg else sb_bg;
        const r_fg = if (is_sel) sb_sel_fg else sb_fg;
        
        const y = @as(u32, @intCast(i)) + 2;
        if (y >= H) break;
        
        for (0..sidebar_w) |c| {
            grid.setCellAt(@intCast(c), y, .{ .char = ' ', .fg = r_fg, .bg = r_bg });
        }
        
        var x: u32 = 1;
        writeChar(grid, &x, y, if (is_sel) 0x276F else ' ', r_fg, r_bg, is_sel);
        x += 1;
        writeStr(grid, &x, y, t, r_fg, r_bg, is_sel);
    }
    
    // Draw preview content
    var y: u32 = 2;
    var x: u32 = content_x + (W - content_x) / 2 - @as(u32, @intCast(themes[g_selected].len)) / 2;
    writeStr(grid, &x, y, themes[g_selected], tc(g_preview_theme.base05), bg_c, true);
    
    y += 3;
    
    // Draw ANSI colors
    const colors = [_]Cell.Color{
        tc(g_preview_theme.base01), tc(g_preview_theme.base08), tc(g_preview_theme.base0B), tc(g_preview_theme.base0A),
        tc(g_preview_theme.base0D), tc(g_preview_theme.base0E), tc(g_preview_theme.base0C), tc(g_preview_theme.base05),
        tc(g_preview_theme.base03), tc(g_preview_theme.base09), tc(g_preview_theme.base01), tc(g_preview_theme.base02),
        tc(g_preview_theme.base04), tc(g_preview_theme.base06), tc(g_preview_theme.base0F), tc(g_preview_theme.base07),
    };
    
    x = content_x + 2;
    for (0..8) |i| {
        var num_buf: [4]u8 = undefined;
        const num = std.fmt.bufPrint(&num_buf, "{d}", .{i}) catch "";
        var nx = x;
        writeStr(grid, &nx, y, num, tc(g_preview_theme.base03), bg_c, false);
        
        nx = x + 3;
        for (0..4) |bw| {
            _ = bw;
            writeChar(grid, &nx, y, 0x2588, colors[i], bg_c, false);
        }
        x += 8;
    }
    
    y += 2;
    x = content_x + 2;
    for (8..16) |i| {
        var num_buf: [4]u8 = undefined;
        const num = std.fmt.bufPrint(&num_buf, "{d}", .{i}) catch "";
        var nx = x;
        writeStr(grid, &nx, y, num, tc(g_preview_theme.base03), bg_c, false);
        
        nx = x + 3;
        for (0..4) |bw| {
            _ = bw;
            writeChar(grid, &nx, y, 0x2588, colors[i], bg_c, false);
        }
        x += 8;
    }
    
    y += 3;
    x = content_x + 2;
    writeStr(grid, &x, y, "\u{279C} ", tc(g_preview_theme.base0B), bg_c, true);
    writeStr(grid, &x, y, "bat main.zig", tc(g_preview_theme.base0E), bg_c, false);
    
    y += 2;
    x = content_x + 2;
    writeStr(grid, &x, y, "const std = @import(\"std\");", tc(g_preview_theme.base05), bg_c, false);
    y += 2;
    x = content_x + 2;
    writeStr(grid, &x, y, "pub fn main() !void {", tc(g_preview_theme.base05), bg_c, false);
    y += 1;
    x = content_x + 6;
    writeStr(grid, &x, y, "std.debug.print(\"Hello, \", .{});", tc(g_preview_theme.base05), bg_c, false);
    y += 1;
    x = content_x + 6;
    writeStr(grid, &x, y, "std.debug.print(\"Zest\\n\", .{});", tc(g_preview_theme.base05), bg_c, false);
    y += 1;
    x = content_x + 2;
    writeStr(grid, &x, y, "}", tc(g_preview_theme.base05), bg_c, false);
}
