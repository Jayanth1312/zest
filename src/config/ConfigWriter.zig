const std = @import("std");
const Settings = @import("Settings.zig").Settings;

extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern fn fwrite(buf: *const anyopaque, size: usize, count: usize, file: *anyopaque) usize;
extern fn fclose(file: *anyopaque) c_int;

pub fn ensureConfigDir(allocator: std.mem.Allocator) ![]u8 {
    const home = std.c.getenv("HOME") orelse return error.NoHome;
    const home_str = std.mem.span(home);
    const config_dir = try std.fs.path.join(allocator, &.{ home_str, ".config", "zest" });
    const c_dir = try allocator.dupeZ(u8, config_dir);
    defer allocator.free(c_dir);
    _ = std.c.mkdir(c_dir, 0o755);
    return config_dir;
}

fn appendLine(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const line = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(line);
    try buf.appendSlice(allocator, line);
    try buf.append(allocator, '\n');
}

pub fn writeSettingsFile(settings: *const Settings, allocator: std.mem.Allocator) !void {
    const config_dir = try ensureConfigDir(allocator);
    defer allocator.free(config_dir);

    const path = try std.fs.path.join(allocator, &.{ config_dir, "settings.conf" });
    defer allocator.free(path);

    var buf: std.ArrayList(u8) = .empty;
    try appendLine(&buf, allocator, "# zest settings", .{});
    try appendLine(&buf, allocator, "theme = {s}", .{settings.theme});
    try appendLine(&buf, allocator, "font_family = {s}", .{settings.font_family});
    try appendLine(&buf, allocator, "font_size = {d}", .{settings.font_size});
    try appendLine(&buf, allocator, "zoom_level = {d}", .{settings.zoom_level});
    try appendLine(&buf, allocator, "min_font_size = {d}", .{settings.min_font_size});
    try appendLine(&buf, allocator, "max_font_size = {d}", .{settings.max_font_size});
    try appendLine(&buf, allocator, "zoom_step = {d}", .{settings.zoom_step});
    try appendLine(&buf, allocator, "padding_x = {d}", .{settings.padding_x});
    try appendLine(&buf, allocator, "padding_y = {d}", .{settings.padding_y});
    try appendLine(&buf, allocator, "inner_padding = {d}", .{settings.inner_padding});
    try appendLine(&buf, allocator, "border_size = {d}", .{settings.border_size});
    try appendLine(&buf, allocator, "initial_cols = {d}", .{settings.initial_cols});
    try appendLine(&buf, allocator, "initial_rows = {d}", .{settings.initial_rows});
    try appendLine(&buf, allocator, "window_width = {d}", .{settings.window_width});
    try appendLine(&buf, allocator, "window_height = {d}", .{settings.window_height});
    try appendLine(&buf, allocator, "max_command_history = {d}", .{settings.max_command_history});
    try appendLine(&buf, allocator, "pty_read_interval_ms = {d}", .{settings.pty_read_interval_ms});
    try appendLine(&buf, allocator, "clock_tick_interval_ms = {d}", .{settings.clock_tick_interval_ms});
    try appendLine(&buf, allocator, "tab_min_width_chars = {d}", .{settings.tab_min_width_chars});
    try appendLine(&buf, allocator, "tab_max_width_chars = {d}", .{settings.tab_max_width_chars});
    try appendLine(&buf, allocator, "explorer_header_rows = {d}", .{settings.explorer_header_rows});
    try appendLine(&buf, allocator, "explorer_footer_rows = {d}", .{settings.explorer_footer_rows});
    try appendLine(&buf, allocator, "explorer_search_max_depth = {d}", .{settings.explorer_search_max_depth});
    if (settings.shell.len > 0) {
        try appendLine(&buf, allocator, "shell = {s}", .{settings.shell});
    }
    if (settings.term.len > 0) {
        try appendLine(&buf, allocator, "term = {s}", .{settings.term});
    }
    try buf.append(allocator, 0);

    const c_path = try allocator.dupeZ(u8, path);
    defer allocator.free(c_path);

    const fp = fopen(c_path.ptr, "w") orelse return error.FileOpenFailed;
    defer _ = fclose(fp);
    _ = fwrite(buf.items.ptr, 1, buf.items.len - 1, fp);
}
