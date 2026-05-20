const std = @import("std");
const Grid = @import("../terminal/Grid.zig");
const Cell = @import("../terminal/Cell.zig");
const Settings = @import("../config/Settings.zig").Settings;
const ConfigWriter = @import("../config/ConfigWriter.zig");

// ── Theme list ────────────────────────────────────────────────────────────────
const themes = [_][]const u8{
    "default", "dracula", "nord", "solarized-dark",
    "catppuccin", "gruvbox", "tokyo-night",
};

// ── Schema ───────────────────────────────────────────────────────────────────
const RowTag = enum {
    theme, font_family, zoom_level, font_size,
    padding_x, padding_y, inner_padding, border_size,
    initial_cols, initial_rows, window_width, window_height,
    pty_read_interval_ms, clock_tick_interval_ms,
    tab_min_width_chars, tab_max_width_chars,
};

const Category = enum { appearance, terminal, window, timing };

const Row = struct {
    tag: RowTag,
    label: []const u8,
    description: []const u8,
    category: Category,
};

const all_rows = [_]Row{
    .{ .tag = .theme,                  .label = "Theme",          .description = "Color theme",       .category = .appearance },
    .{ .tag = .font_family,            .label = "Font Family",    .description = "Font name",         .category = .appearance },
    .{ .tag = .zoom_level,             .label = "Zoom Level",     .description = "Text zoom %",        .category = .appearance },
    .{ .tag = .font_size,              .label = "Font Size",      .description = "Base font px",       .category = .appearance },
    .{ .tag = .padding_x,              .label = "Padding X",      .description = "Outer horiz px",     .category = .terminal   },
    .{ .tag = .padding_y,              .label = "Padding Y",      .description = "Outer vert px",      .category = .terminal   },
    .{ .tag = .inner_padding,          .label = "Inner Padding",  .description = "Inner margin px",    .category = .terminal   },
    .{ .tag = .border_size,            .label = "Border Size",    .description = "Split border px",    .category = .terminal   },
    .{ .tag = .initial_cols,           .label = "Initial Cols",   .description = "Start width cols",   .category = .window     },
    .{ .tag = .initial_rows,           .label = "Initial Rows",   .description = "Start height rows",  .category = .window     },
    .{ .tag = .window_width,           .label = "Window Width",   .description = "Window px width",    .category = .window     },
    .{ .tag = .window_height,          .label = "Window Height",  .description = "Window px height",   .category = .window     },
    .{ .tag = .pty_read_interval_ms,   .label = "PTY Interval",   .description = "Read interval ms",   .category = .timing     },
    .{ .tag = .clock_tick_interval_ms, .label = "Clock Interval", .description = "Clock refresh ms",   .category = .timing     },
    .{ .tag = .tab_min_width_chars,    .label = "Tab Min Width",  .description = "Min tab chars",      .category = .timing     },
    .{ .tag = .tab_max_width_chars,    .label = "Tab Max Width",  .description = "Max tab chars",      .category = .timing     },
};

const category_names = [_][]const u8{ "Appearance", "Terminal", "Window", "Timing" };

// ── State ─────────────────────────────────────────────────────────────────────
var g_settings: Settings = undefined;
var g_selected: usize = 0;
var g_saved_grid: ?Grid.Grid = null;
var g_cols: u32 = 0;
var g_rows: u32 = 0;
var g_dirty: bool = false;
var g_filter_buf: [32]u8 = undefined;
var g_filter_len: usize = 0;
var g_filtered_indices: [all_rows.len]usize = undefined;
var g_filtered_count: usize = 0;

// Inline numeric edit mode
var g_edit_mode: bool = false;
var g_edit_buf: [16]u8 = undefined;
var g_edit_len: usize = 0;

// Set when user changes the theme; caller must poll consumeThemeChanged() and
// trigger a full terminal repaint so existing cell colours update immediately.
var g_theme_changed: bool = false;

// ── Public API ────────────────────────────────────────────────────────────────
pub fn isOpen() bool { return g_saved_grid != null; }
pub fn isDirty() bool { return g_dirty; }
pub fn getSettings() *const Settings { return &g_settings; }

/// Returns true (once) after the user changes the theme. The caller should
/// force-repaint every terminal cell so the new palette takes effect without
/// needing a manual `clear`.
pub fn consumeThemeChanged() bool {
    const v = g_theme_changed;
    g_theme_changed = false;
    return v;
}

var g_theme_preview_requested: bool = false;

pub fn consumeThemePreviewRequest() bool {
    const v = g_theme_preview_requested;
    g_theme_preview_requested = false;
    return v;
}

pub fn open(grid: *Grid.Grid, settings: *const Settings, pane_cols: u32, pane_rows: u32) !void {
    g_cols = pane_cols;
    g_rows = pane_rows;
    g_settings = settings.*;
    g_selected = 0;
    g_dirty = false;
    g_filter_len = 0;
    g_edit_mode = false;
    g_edit_len = 0;
    rebuildFilteredList();

    const total = @as(usize, g_cols) * @as(usize, g_rows);
    const cells = try grid.allocator.alloc(Cell.Cell, total);
    @memcpy(cells, grid.cells[0..total]);
    g_saved_grid = Grid.Grid{
        .cells = cells,
        .row_indices = try grid.allocator.dupe(u32, grid.row_indices[0..g_rows]),
        .cols = g_cols,
        .rows = g_rows,
        .allocator = grid.allocator,
    };
    render(grid);
}

pub fn close(grid: *Grid.Grid) void {
    if (g_saved_grid) |sg| {
        const total = @as(usize, g_cols) * @as(usize, g_rows);
        @memcpy(grid.cells[0..total], sg.cells[0..total]);
        @constCast(&sg).deinit();
        g_saved_grid = null;
        g_dirty = false;
        g_edit_mode = false;
    }
}

pub fn saveToFile() !void {
    try ConfigWriter.writeSettingsFile(&g_settings, std.heap.page_allocator);
    g_dirty = false;
}

// ── Filtering ─────────────────────────────────────────────────────────────────
fn matchesFilter(row: *const Row) bool {
    if (g_filter_len == 0) return true;
    const filter = g_filter_buf[0..g_filter_len];
    var lb: [64]u8 = undefined;
    var db: [64]u8 = undefined;
    var fb: [32]u8 = undefined;
    const ll = @min(row.label.len, lb.len);
    const dl = @min(row.description.len, db.len);
    for (row.label[0..ll], 0..) |ch, i| lb[i] = std.ascii.toLower(ch);
    for (row.description[0..dl], 0..) |ch, i| db[i] = std.ascii.toLower(ch);
    for (filter, 0..) |ch, i| fb[i] = std.ascii.toLower(ch);
    const fl = fb[0..filter.len];
    return std.mem.indexOf(u8, lb[0..ll], fl) != null or
           std.mem.indexOf(u8, db[0..dl], fl) != null;
}

fn rebuildFilteredList() void {
    g_filtered_count = 0;
    for (all_rows, 0..) |row, i| {
        if (matchesFilter(&row)) {
            g_filtered_indices[g_filtered_count] = i;
            g_filtered_count += 1;
        }
    }
    if (g_selected >= g_filtered_count)
        g_selected = if (g_filtered_count > 0) g_filtered_count - 1 else 0;
}

fn getRowTagByFilteredIndex(fi: usize) ?RowTag {
    if (fi >= g_filtered_count) return null;
    return all_rows[g_filtered_indices[fi]].tag;
}

fn getRowByFilteredIndex(fi: usize) ?*const Row {
    if (fi >= g_filtered_count) return null;
    return &all_rows[g_filtered_indices[fi]];
}

// ── Value formatting ──────────────────────────────────────────────────────────
fn formatValue(buf: []u8, tag: RowTag) []const u8 {
    return switch (tag) {
        .theme               => std.fmt.bufPrint(buf, "{s}",    .{g_settings.theme})                    catch "?",
        .font_family         => std.fmt.bufPrint(buf, "{s}",    .{g_settings.font_family})              catch "?",
        .zoom_level          => std.fmt.bufPrint(buf, "{d}%",   .{g_settings.zoom_level})               catch "?",
        .font_size           => std.fmt.bufPrint(buf, "{d}",    .{g_settings.font_size})                catch "?",
        .padding_x           => std.fmt.bufPrint(buf, "{d:.1}", .{g_settings.padding_x})                catch "?",
        .padding_y           => std.fmt.bufPrint(buf, "{d:.1}", .{g_settings.padding_y})                catch "?",
        .inner_padding       => std.fmt.bufPrint(buf, "{d:.1}", .{g_settings.inner_padding})            catch "?",
        .border_size         => std.fmt.bufPrint(buf, "{d:.1}", .{g_settings.border_size})              catch "?",
        .initial_cols        => std.fmt.bufPrint(buf, "{d}",    .{g_settings.initial_cols})             catch "?",
        .initial_rows        => std.fmt.bufPrint(buf, "{d}",    .{g_settings.initial_rows})             catch "?",
        .window_width        => std.fmt.bufPrint(buf, "{d}",    .{g_settings.window_width})             catch "?",
        .window_height       => std.fmt.bufPrint(buf, "{d}",    .{g_settings.window_height})            catch "?",
        .pty_read_interval_ms   => std.fmt.bufPrint(buf, "{d}ms", .{g_settings.pty_read_interval_ms})   catch "?",
        .clock_tick_interval_ms => std.fmt.bufPrint(buf, "{d}ms", .{g_settings.clock_tick_interval_ms}) catch "?",
        .tab_min_width_chars => std.fmt.bufPrint(buf, "{d}",    .{g_settings.tab_min_width_chars})      catch "?",
        .tab_max_width_chars => std.fmt.bufPrint(buf, "{d}",    .{g_settings.tab_max_width_chars})      catch "?",
    };
}

fn isNumericTag(tag: RowTag) bool {
    return tag != .theme;
}

// ── Value mutation ────────────────────────────────────────────────────────────
fn applyChange(tag: RowTag, dir: i32) void {
    switch (tag) {
        .theme => {
            var idx: usize = 0;
            for (themes, 0..) |t, i| {
                if (std.mem.eql(u8, g_settings.theme, t)) { idx = i; break; }
            }
            const new_idx: usize = @intCast(@max(
                @as(i64, 0),
                @min(
                    @as(i64, @intCast(themes.len - 1)),
                    @as(i64, @intCast(idx)) + @as(i64, dir),
                ),
            ));
            if (new_idx != idx) {
                g_settings.theme = themes[new_idx];
                g_dirty = true;
                // Signal caller to flush a full-frame repaint with new palette
                g_theme_changed = true;
            }
        },
        .font_family => {},
        .zoom_level => {
            g_settings.zoom_level = @max(50, @min(300, @as(u32, @intCast(@max(0, @as(i32, @intCast(g_settings.zoom_level)) + 10 * dir)))));
            g_dirty = true;
        },
        .font_size => {
            g_settings.font_size = @max(8, @min(96, @as(u32, @intCast(@max(0, @as(i32, @intCast(g_settings.font_size)) + 2 * dir)))));
            g_dirty = true;
        },
        .padding_x => {
            g_settings.padding_x = @max(0, g_settings.padding_x + @as(f32, @floatFromInt(dir)));
            g_dirty = true;
        },
        .padding_y => {
            g_settings.padding_y = @max(0, g_settings.padding_y + @as(f32, @floatFromInt(dir)));
            g_dirty = true;
        },
        .inner_padding => {
            g_settings.inner_padding = @max(0, g_settings.inner_padding + @as(f32, @floatFromInt(dir)));
            g_dirty = true;
        },
        .border_size => {
            g_settings.border_size = @max(0, g_settings.border_size + @as(f32, @floatFromInt(dir)) * 0.5);
            g_dirty = true;
        },
        .initial_cols => {
            g_settings.initial_cols = @max(20, @as(u32, @intCast(@max(0, @as(i32, @intCast(g_settings.initial_cols)) + dir))));
            g_dirty = true;
        },
        .initial_rows => {
            g_settings.initial_rows = @max(5, @as(u32, @intCast(@max(0, @as(i32, @intCast(g_settings.initial_rows)) + dir))));
            g_dirty = true;
        },
        .window_width => {
            g_settings.window_width = @max(400, g_settings.window_width + dir * 10);
            g_dirty = true;
        },
        .window_height => {
            g_settings.window_height = @max(200, g_settings.window_height + dir * 10);
            g_dirty = true;
        },
        .pty_read_interval_ms => {
            g_settings.pty_read_interval_ms = @max(8, @as(u32, @intCast(@max(0, @as(i32, @intCast(g_settings.pty_read_interval_ms)) + 8 * dir))));
            g_dirty = true;
        },
        .clock_tick_interval_ms => {
            g_settings.clock_tick_interval_ms = @max(100, @as(u32, @intCast(@max(0, @as(i32, @intCast(g_settings.clock_tick_interval_ms)) + 500 * dir))));
            g_dirty = true;
        },
        .tab_min_width_chars => {
            g_settings.tab_min_width_chars = @max(1, g_settings.tab_min_width_chars + dir);
            g_dirty = true;
        },
        .tab_max_width_chars => {
            g_settings.tab_max_width_chars = @max(5, g_settings.tab_max_width_chars + dir * 5);
            g_dirty = true;
        },
    }
}

/// Commit the inline-typed edit buffer to the current setting.
fn commitEdit(tag: RowTag) void {
    if (g_edit_len == 0) return;
    const str = g_edit_buf[0..g_edit_len];
    
    switch (tag) {
        .theme => {},
        .font_family => {
            const new_str = std.heap.page_allocator.dupe(u8, str) catch return;
            g_settings.font_family = new_str;
            g_dirty = true;
        },
        .zoom_level          => { if (std.fmt.parseInt(u32, str, 10)) |v| { g_settings.zoom_level = @max(50, @min(300, v)); g_dirty = true; } else |_| {} },
        .font_size           => { if (std.fmt.parseInt(u32, str, 10)) |v| { g_settings.font_size = @max(8, @min(96, v)); g_dirty = true; } else |_| {} },
        .padding_x           => { if (std.fmt.parseFloat(f32, str)) |v| { g_settings.padding_x = @max(0, v); g_dirty = true; } else |_| {} },
        .padding_y           => { if (std.fmt.parseFloat(f32, str)) |v| { g_settings.padding_y = @max(0, v); g_dirty = true; } else |_| {} },
        .inner_padding       => { if (std.fmt.parseFloat(f32, str)) |v| { g_settings.inner_padding = @max(0, v); g_dirty = true; } else |_| {} },
        .border_size         => { if (std.fmt.parseFloat(f32, str)) |v| { g_settings.border_size = @max(0, v); g_dirty = true; } else |_| {} },
        .initial_cols        => { if (std.fmt.parseInt(u32, str, 10)) |v| { g_settings.initial_cols = @max(20, v); g_dirty = true; } else |_| {} },
        .initial_rows        => { if (std.fmt.parseInt(u32, str, 10)) |v| { g_settings.initial_rows = @max(5, v); g_dirty = true; } else |_| {} },
        .window_width        => { if (std.fmt.parseInt(i32, str, 10)) |v| { g_settings.window_width = @max(400, v); g_dirty = true; } else |_| {} },
        .window_height       => { if (std.fmt.parseInt(i32, str, 10)) |v| { g_settings.window_height = @max(200, v); g_dirty = true; } else |_| {} },
        .pty_read_interval_ms   => { if (std.fmt.parseInt(u32, str, 10)) |v| { g_settings.pty_read_interval_ms = @max(8, v); g_dirty = true; } else |_| {} },
        .clock_tick_interval_ms => { if (std.fmt.parseInt(u32, str, 10)) |v| { g_settings.clock_tick_interval_ms = @max(100, v); g_dirty = true; } else |_| {} },
        .tab_min_width_chars => { if (std.fmt.parseInt(i32, str, 10)) |v| { g_settings.tab_min_width_chars = @max(1, v); g_dirty = true; } else |_| {} },
        .tab_max_width_chars => { if (std.fmt.parseInt(i32, str, 10)) |v| { g_settings.tab_max_width_chars = @max(5, v); g_dirty = true; } else |_| {} },
    }
}

// ── Key handling ──────────────────────────────────────────────────────────────
pub fn handleKey(grid: *Grid.Grid, raw_keyval: c_uint, ctrl: bool) bool {
    if (ctrl) return false;

    var keyval = raw_keyval;
    if (keyval >= 0xFFB0 and keyval <= 0xFFB9) keyval = keyval - 0xFFB0 + '0';
    if (keyval == 0xFF8D) keyval = 0xFF0D; // map KP_Enter to Enter
    
    // ESC: cancel edit or close
    if (keyval == 0xFF1B) {
        if (g_edit_mode) {
            g_edit_mode = false;
            g_edit_len = 0;
            render(grid);
        } else {
            close(grid);
        }
        return true;
    }

    // Enter: commit edit or save+close
    if (keyval == 0xFF0D) {
        if (g_edit_mode) {
            if (getRowTagByFilteredIndex(g_selected)) |tag| commitEdit(tag);
            g_edit_mode = false;
            g_edit_len = 0;
            render(grid);
        } else {
            if (getRowTagByFilteredIndex(g_selected)) |tag| {
                if (tag == .theme) {
                    g_theme_preview_requested = true;
                    close(grid);
                    return true;
                }
            }
            saveToFile() catch {};
            close(grid);
        }
        return true;
    }

    // Edit mode: only digits, backspace, minus, dot
    if (g_edit_mode) {
        switch (keyval) {
            0xFF08, 0xFF7F => {
                if (g_edit_len > 0) g_edit_len -= 1;
                render(grid);
                return true;
            },
            else => {},
        }
        if ((keyval >= '0' and keyval <= '9') or keyval == '.' or keyval == '-') {
            if (g_edit_len < g_edit_buf.len - 1) {
                g_edit_buf[g_edit_len] = @intCast(keyval);
                g_edit_len += 1;
                render(grid);
            }
        }
        return true; // consume everything else in edit mode
    }

    // Normal mode navigation
    switch (keyval) {
        0xFF52 => { // Up
            if (g_selected > 0) g_selected -= 1;
            render(grid);
            return true;
        },
        0xFF54 => { // Down
            if (g_filtered_count > 0 and g_selected < g_filtered_count - 1) g_selected += 1;
            render(grid);
            return true;
        },
        0xFF53 => { // Right — increment
            if (getRowTagByFilteredIndex(g_selected)) |tag| applyChange(tag, 1);
            render(grid);
            return true;
        },
        0xFF51 => { // Left — decrement
            if (getRowTagByFilteredIndex(g_selected)) |tag| applyChange(tag, -1);
            render(grid);
            return true;
        },
        0xFF08, 0xFF7F => { // Backspace — trim filter
            if (g_filter_len > 0) {
                g_filter_len -= 1;
                rebuildFilteredList();
                render(grid);
            }
            return true;
        },
        else => {},
    }

    // Printable chars: digit on numeric row → enter edit mode; otherwise filter
    if (keyval >= 0x20 and keyval < 0x7F) {
        const ch: u8 = @intCast(keyval);
        if (getRowTagByFilteredIndex(g_selected)) |tag| {
            if (isNumericTag(tag) or tag == .font_family) {
                g_edit_mode = true;
                g_edit_buf[0] = ch;
                g_edit_len = 1;
                render(grid);
                return true;
            }
        }
        if (g_filter_len < g_filter_buf.len) {
            g_filter_buf[g_filter_len] = ch;
            g_filter_len += 1;
            rebuildFilteredList();
            render(grid);
            return true;
        }
    }

    return false;
}

// ── Cell-level helpers ────────────────────────────────────────────────────────
fn setCell(grid: *Grid.Grid, col: u32, row: u32, ch: u21, fg: Cell.Color, bg: Cell.Color, bold: bool) void {
    if (col < g_cols and row < g_rows)
        grid.setCellAt(@intCast(col), @intCast(row), .{ .char = ch, .fg = fg, .bg = bg, .attrs = .{ .bold = bold } });
}

/// Write a UTF-8 string by iterating codepoints — fixes the garbled-symbol
/// bug that occurred when multi-byte characters were iterated byte-by-byte.
fn writeStr(grid: *Grid.Grid, col: *u32, row: u32, str: []const u8, fg: Cell.Color, bg: Cell.Color, bold: bool) void {
    var view = std.unicode.Utf8View.initUnchecked(str);
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| {
        setCell(grid, col.*, row, cp, fg, bg, bold);
        col.* += 1;
    }
}

fn writeChar(grid: *Grid.Grid, col: *u32, row: u32, cp: u21, fg: Cell.Color, bg: Cell.Color, bold: bool) void {
    setCell(grid, col.*, row, cp, fg, bg, bold);
    col.* += 1;
}

fn fillRow(grid: *Grid.Grid, row: u32, from: u32, to: u32, cp: u21, fg: Cell.Color, bg: Cell.Color) void {
    var c = from;
    while (c < to) : (c += 1) setCell(grid, c, row, cp, fg, bg, false);
}

fn drawHLine(grid: *Grid.Grid, row: u32, from: u32, to: u32, l: u21, m: u21, r: u21, fg: Cell.Color, bg: Cell.Color) void {
    if (to <= from) return;
    setCell(grid, from, row, l, fg, bg, false);
    var c: u32 = from + 1;
    while (c < to - 1) : (c += 1) setCell(grid, c, row, m, fg, bg, false);
    if (to - 1 > from) setCell(grid, to - 1, row, r, fg, bg, false);
}

/// Codepoint count of a UTF-8 string (= terminal columns for BMP non-wide chars).
fn cpLen(str: []const u8) u32 {
    var view = std.unicode.Utf8View.initUnchecked(str);
    var it = view.iterator();
    var n: u32 = 0;
    while (it.nextCodepoint()) |_| n += 1;
    return n;
}

// ── Render ────────────────────────────────────────────────────────────────────
pub fn render(grid: *Grid.Grid) void {
    // base16 colour slots
    const fg_c    = Cell.Color.base05; // default text
    const bg_c    = Cell.Color.base00; // background
    const sel_bg  = Cell.Color.base08; // selected row bg
    const sel_fg  = Cell.Color.base00; // selected row fg
    const title_c = Cell.Color.base0D; // blue  — title / borders
    const brd_c   = Cell.Color.base03; // dim   — box lines
    const val_c   = Cell.Color.base0C; // cyan  — values
    const cat_c   = Cell.Color.base0A; // amber — category names
    const dim_c   = Cell.Color.base03; // dim   — descriptions, dots
    const edit_c  = Cell.Color.base0E; // magenta — edit-mode cursor/text
    const dirty_c = Cell.Color.base0B; // green — unsaved indicator

    // Clear
    for (0..g_rows) |r|
        for (0..g_cols) |c|
            grid.setCellAt(@intCast(c), @intCast(r), .{ .char = ' ', .fg = fg_c, .bg = bg_c });

    var buf: [64]u8 = undefined;
    const W = g_cols;

    // Layout columns
    const bL: u32 = 0;       // outer border left
    const bR: u32 = W -| 1; // outer border right
    const cL: u32 = 2;       // content left  (border + 1 padding)
    const cR: u32 = W -| 2; // content right (exclusive — last drawn col = cR-1)

    // ── Row 0: ╭─────────────────────────────────────────────────╮
    drawHLine(grid, 0, bL, bR + 1, 0x256D, 0x2500, 0x256E, brd_c, bg_c);

    // ── Row 1: title bar
    setCell(grid, bL, 1, 0x2502, brd_c, bg_c, false); // │
    setCell(grid, bR, 1, 0x2502, brd_c, bg_c, false); // │
    {
        const title = " \u{2699}  Settings ";  // ⚙  Settings
        const tw = cpLen(title);
        var tc: u32 = (W -| tw) / 2;
        writeStr(grid, &tc, 1, title, title_c, bg_c, true);
    }
    // Count (top-right)
    {
        const ct = if (g_filter_len > 0)
            std.fmt.bufPrint(&buf, "{d}/{d} ", .{ g_filtered_count, all_rows.len }) catch ""
        else
            std.fmt.bufPrint(&buf, "{d} ", .{all_rows.len}) catch "";
        var cc: u32 = bR -| @as(u32, @intCast(ct.len));
        writeStr(grid, &cc, 1, ct, dim_c, bg_c, false);
    }
    // Filter hint (top-left)
    if (g_filter_len > 0) {
        var fc: u32 = cL;
        writeStr(grid, &fc, 1, "/", dim_c, bg_c, false);
        writeStr(grid, &fc, 1, g_filter_buf[0..g_filter_len], cat_c, bg_c, true);
    }
    // Edit-mode badge
    if (g_edit_mode) {
        const badge = "  EDIT ";
        var ec: u32 = cL + 1;
        writeStr(grid, &ec, 1, badge, edit_c, bg_c, true);
    }

    // ── Row 2: ╞═══════════════════════════════════════════════════╡
    drawHLine(grid, 2, bL, bR + 1, 0x255E, 0x2550, 0x2561, brd_c, bg_c);

    // ── Content rows (3 … g_rows-3)
    var cr: u32 = 3;
    var last_cat: ?Category = null;
    var fi: usize = 0;

    while (fi < g_filtered_count and cr < g_rows -| 2) : (fi += 1) {
        const row = &all_rows[g_filtered_indices[fi]];
        const is_sel = fi == g_selected;
        const r_bg = if (is_sel) sel_bg else bg_c;
        const r_fg = if (is_sel) sel_fg else fg_c;

        // Category separator: ╶ CategoryName ────────────────────
        if (last_cat == null or last_cat.? != row.category) {
            last_cat = row.category;
            if (cr < g_rows -| 2) {
                setCell(grid, bL, cr, 0x2502, brd_c, bg_c, false);
                setCell(grid, bR, cr, 0x2502, brd_c, bg_c, false);
                var lc: u32 = cL;
                writeChar(grid, &lc, cr, 0x2576, brd_c, bg_c, false); // ╶
                writeChar(grid, &lc, cr, ' ', bg_c,  bg_c, false);
                writeStr(grid,  &lc, cr, category_names[@intFromEnum(row.category)], cat_c, bg_c, true);
                writeChar(grid, &lc, cr, ' ', bg_c,  bg_c, false);
                while (lc < cR) writeChar(grid, &lc, cr, 0x2500, brd_c, bg_c, false);
                cr += 1;
            }
        }
        if (cr >= g_rows -| 2) break;

        // Side borders
        setCell(grid, bL, cr, 0x2502, brd_c, bg_c, false);
        setCell(grid, bR, cr, 0x2502, brd_c, bg_c, false);

        // Selected-row background (skip border cols)
        if (is_sel) fillRow(grid, cr, 1, bR, ' ', sel_fg, sel_bg);

        // Selection marker ▶ / space
        var lc: u32 = cL;
        writeChar(grid, &lc, cr,
            if (is_sel) @as(u21, 0x25B6) else ' ', // ▶
            if (is_sel) sel_fg else dim_c, r_bg, is_sel);
        writeChar(grid, &lc, cr, ' ', r_fg, r_bg, false);

        // Label
        writeStr(grid, &lc, cr, row.label, r_fg, r_bg, is_sel);

        // Description
        writeChar(grid, &lc, cr, ' ', dim_c, r_bg, false);
        writeStr(grid, &lc, cr, row.description, dim_c, r_bg, false);
        writeChar(grid, &lc, cr, ' ', dim_c, r_bg, false);

        // ── Value widget (right-aligned)
        const show_edit = is_sel and g_edit_mode;
        const val_str  = if (show_edit) g_edit_buf[0..g_edit_len] else formatValue(&buf, row.tag);
        // Reserve width: "[ " + value + cursor? + " ]"
        const val_w: u32 = if (show_edit)
            @as(u32, @intCast(g_edit_len)) + 1   // +1 for █ cursor
        else
            cpLen(val_str);
        const total_w = val_w + 4; // [ space val space ]
        const val_start = cR -| total_w;

        // Dot fill ·············
        while (lc < val_start)
            writeChar(grid, &lc, cr, 0x00B7, dim_c, r_bg, false); // ·

        // Bracket open
        const b_fg = if (is_sel) sel_fg else brd_c;
        const v_fg = if (show_edit) edit_c else if (is_sel) sel_fg else val_c;
        writeChar(grid, &lc, cr, '[', b_fg, r_bg, false);
        writeChar(grid, &lc, cr, ' ', b_fg, r_bg, false);
        writeStr(grid,  &lc, cr, val_str, v_fg, r_bg, true);
        if (show_edit)
            writeChar(grid, &lc, cr, 0x2588, edit_c, r_bg, true); // █
        writeChar(grid, &lc, cr, ' ', b_fg, r_bg, false);
        writeChar(grid, &lc, cr, ']', b_fg, r_bg, false);

        cr += 1;
    }

    // Fill unused interior rows
    while (cr < g_rows -| 2) : (cr += 1) {
        setCell(grid, bL, cr, 0x2502, brd_c, bg_c, false);
        setCell(grid, bR, cr, 0x2502, brd_c, bg_c, false);
    }

    // ── Row g_rows-2: ╞═══════════════════════════════════════════╡
    if (g_rows >= 3)
        drawHLine(grid, g_rows -| 2, bL, bR + 1, 0x255E, 0x2550, 0x2561, brd_c, bg_c);

    // ── Row g_rows-1: footer
    const fr = g_rows -| 1;
    setCell(grid, bL, fr, 0x2502, brd_c, bg_c, false);
    setCell(grid, bR, fr, 0x2502, brd_c, bg_c, false);

    // Status indicator
    var fc: u32 = cL;
    if (g_dirty) {
        writeChar(grid, &fc, fr, 0x25CF, dirty_c, bg_c, true);  // ●
        writeStr(grid,  &fc, fr, " unsaved", dirty_c, bg_c, true);
    } else {
        writeChar(grid, &fc, fr, 0x25CB, dim_c, bg_c, false);   // ○
        writeStr(grid,  &fc, fr, " saved", dim_c, bg_c, false);
    }

    // Centred help line (codepoint-counted so arrows don't misalign)
    const help_normal = "\u{2191}\u{2193} navigate  \u{2190}\u{2192} change  / filter  \u{23CE} save  Esc close";
    const help_edit   = "0\u{2013}9 type value  \u{23CE} confirm  Esc cancel";
    const help = if (g_edit_mode) help_edit else help_normal;
    const hw = cpLen(help);
    var hc: u32 = (W -| hw) / 2;
    writeStr(grid, &hc, fr, help, dim_c, bg_c, false);
}