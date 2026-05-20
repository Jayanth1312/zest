const std = @import("std");

pub const Settings = struct {
    theme: []const u8 = "default",
    font_family: []const u8 = "monospace",
    font_size: u32 = 32,
    zoom_level: u32 = 100,
    min_font_size: u32 = 8,
    max_font_size: u32 = 96,
    zoom_step: u32 = 10,
    padding_x: f32 = 8.0,
    padding_y: f32 = 8.0,
    inner_padding: f32 = 4.0,
    border_size: f32 = 1.5,
    initial_cols: u32 = 120,
    initial_rows: u32 = 35,
    tab_bar_height: i32 = 36,
    window_width: i32 = 1280,
    window_height: i32 = 720,
    max_command_history: usize = 200,
    cursor_blink_hold: f64 = 2.0,
    cursor_blink_duty: f64 = 0.6,
    pty_read_interval_ms: u32 = 16,
    clock_tick_interval_ms: u32 = 1000,
    tab_min_width_chars: i32 = 1,
    tab_max_width_chars: i32 = 30,
    explorer_header_rows: u32 = 3,
    explorer_footer_rows: u32 = 1,
    explorer_search_max_depth: u32 = 10,
    shell: []const u8 = "",
    term: []const u8 = "xterm-256color",

    pub fn load(map: *const std.StringHashMap([]u8)) Settings {
        var s = Settings{};
        var it = map.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;
            parseField(&s, key, value);
        }
        return s;
    }

    fn parseField(s: *Settings, key: []const u8, value: []const u8) void {
        if (std.mem.eql(u8, key, "theme")) {
            s.theme = value;
        } else if (std.mem.eql(u8, key, "font_family")) {
            s.font_family = value;
        } else if (std.mem.eql(u8, key, "font_size")) {
            s.font_size = parseInt(value, 32) orelse return;
        } else if (std.mem.eql(u8, key, "zoom_level")) {
            s.zoom_level = parseInt(value, 100) orelse return;
        } else if (std.mem.eql(u8, key, "min_font_size")) {
            s.min_font_size = parseInt(value, 8) orelse return;
        } else if (std.mem.eql(u8, key, "max_font_size")) {
            s.max_font_size = parseInt(value, 96) orelse return;
        } else if (std.mem.eql(u8, key, "zoom_step")) {
            s.zoom_step = parseInt(value, 10) orelse return;
        } else if (std.mem.eql(u8, key, "padding_x")) {
            s.padding_x = parseFloat(value, 8.0) orelse return;
        } else if (std.mem.eql(u8, key, "padding_y")) {
            s.padding_y = parseFloat(value, 8.0) orelse return;
        } else if (std.mem.eql(u8, key, "inner_padding")) {
            s.inner_padding = parseFloat(value, 4.0) orelse return;
        } else if (std.mem.eql(u8, key, "border_size")) {
            s.border_size = parseFloat(value, 1.5) orelse return;
        } else if (std.mem.eql(u8, key, "initial_cols")) {
            s.initial_cols = parseInt(value, 120) orelse return;
        } else if (std.mem.eql(u8, key, "initial_rows")) {
            s.initial_rows = parseInt(value, 35) orelse return;
        } else if (std.mem.eql(u8, key, "tab_bar_height")) {
            s.tab_bar_height = parseIntSigned(value, 36) orelse return;
        } else if (std.mem.eql(u8, key, "window_width")) {
            s.window_width = parseIntSigned(value, 1280) orelse return;
        } else if (std.mem.eql(u8, key, "window_height")) {
            s.window_height = parseIntSigned(value, 720) orelse return;
        } else if (std.mem.eql(u8, key, "max_command_history")) {
            s.max_command_history = parseInt(value, 200) orelse return;
        } else if (std.mem.eql(u8, key, "cursor_blink_hold")) {
            s.cursor_blink_hold = parseFloat64(value, 2.0) orelse return;
        } else if (std.mem.eql(u8, key, "cursor_blink_duty")) {
            s.cursor_blink_duty = parseFloat64(value, 0.6) orelse return;
        } else if (std.mem.eql(u8, key, "pty_read_interval_ms")) {
            s.pty_read_interval_ms = parseInt(value, 16) orelse return;
        } else if (std.mem.eql(u8, key, "clock_tick_interval_ms")) {
            s.clock_tick_interval_ms = parseInt(value, 1000) orelse return;
        } else if (std.mem.eql(u8, key, "tab_min_width_chars")) {
            s.tab_min_width_chars = parseIntSigned(value, 1) orelse return;
        } else if (std.mem.eql(u8, key, "tab_max_width_chars")) {
            s.tab_max_width_chars = parseIntSigned(value, 30) orelse return;
        } else if (std.mem.eql(u8, key, "explorer_header_rows")) {
            s.explorer_header_rows = parseInt(value, 3) orelse return;
        } else if (std.mem.eql(u8, key, "explorer_footer_rows")) {
            s.explorer_footer_rows = parseInt(value, 1) orelse return;
        } else if (std.mem.eql(u8, key, "explorer_search_max_depth")) {
            s.explorer_search_max_depth = parseInt(value, 10) orelse return;
        } else if (std.mem.eql(u8, key, "shell") and value.len > 0) {
            s.shell = value;
        } else if (std.mem.eql(u8, key, "term") and value.len > 0) {
            s.term = value;
        }
    }

    fn parseInt(value: []const u8, default: u32) ?u32 {
        return std.fmt.parseInt(u32, value, 10) catch default;
    }

    fn parseIntSigned(value: []const u8, default: i32) ?i32 {
        return std.fmt.parseInt(i32, value, 10) catch default;
    }

    fn parseFloat(value: []const u8, default: f32) ?f32 {
        return std.fmt.parseFloat(f32, value) catch default;
    }

    fn parseFloat64(value: []const u8, default: f64) ?f64 {
        return std.fmt.parseFloat(f64, value) catch default;
    }
};
