const std = @import("std");
const ConfigParser = @import("ConfigParser.zig");
const SettingsMod = @import("Settings.zig");
const ThemeMod = @import("Theme.zig");

pub const Settings = SettingsMod.Settings;
pub const Theme = ThemeMod.Theme;

pub const Config = struct {
    settings: Settings,
    settings_map: std.StringHashMap([]u8),
    theme: Theme,
    css: [:0]u8,

    pub fn load(allocator: std.mem.Allocator) !Config {
        const config_dir = try getConfigDir(allocator);
        defer allocator.free(config_dir);

        var settings = Settings{};

        const settings_path = try std.fs.path.join(allocator, &.{ config_dir, "settings.conf" });
        defer allocator.free(settings_path);

        var parsed_map = ConfigParser.parseFile(allocator, settings_path) catch std.StringHashMap([]u8).init(allocator);
        settings = Settings.load(&parsed_map);

        var theme: Theme = Theme{};

        const themes_dir = try std.fs.path.join(allocator, &.{ config_dir, "themes" });
        defer allocator.free(themes_dir);

        if (settings.theme.len > 0 and !std.mem.eql(u8, settings.theme, "default")) {
            const theme_path = try std.fs.path.join(allocator, &.{ themes_dir, settings.theme });
            defer allocator.free(theme_path);

            var theme_path_with_ext: ?[]const u8 = null;
            defer if (theme_path_with_ext) |p| allocator.free(p);

            if (hasExtension(theme_path)) {
                theme_path_with_ext = try allocator.dupe(u8, theme_path);
            } else {
                theme_path_with_ext = try std.fmt.allocPrint(allocator, "{s}.conf", .{theme_path});
            }

            var theme_map = ConfigParser.parseFile(allocator, theme_path_with_ext.?) catch std.StringHashMap([]u8).init(allocator);
            defer ConfigParser.deinitMap(&theme_map);
            if (theme_map.count() > 0) {
                theme = try Theme.load(allocator, &theme_map);
            } else {
                try loadBundledTheme(allocator, settings.theme, &theme);
            }
        }

        const css = try theme.generateCss(allocator);

        return Config{
            .settings = settings,
            .settings_map = parsed_map,
            .theme = theme,
            .css = css,
        };
    }

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        ConfigParser.deinitMap(&self.settings_map);
        allocator.free(self.css);
    }
};

fn getConfigDir(allocator: std.mem.Allocator) ![]u8 {
    if (std.c.getenv("XDG_CONFIG_HOME")) |xdg| {
        const xdg_str = std.mem.span(xdg);
        return try std.fs.path.join(allocator, &.{ xdg_str, "zest" });
    }
    if (std.c.getenv("HOME")) |home| {
        const home_str = std.mem.span(home);
        return try std.fs.path.join(allocator, &.{ home_str, ".config", "zest" });
    }
    return try allocator.dupe(u8, "/home/.config/zest");
}

fn hasExtension(path: []const u8) bool {
    const last_dot = std.mem.lastIndexOfScalar(u8, path, '.');
    if (last_dot) |dot| {
        return dot > std.mem.lastIndexOfScalar(u8, path, '/') orelse 0;
    }
    return false;
}

fn loadBundledTheme(allocator: std.mem.Allocator, name: []const u8, theme: *Theme) !void {
    const content: ?[]const u8 = getBundledTheme(name);
    const data = content orelse return;
    var map = ConfigParser.parseContent(allocator, data);
    defer ConfigParser.deinitMap(&map);
    theme.* = try Theme.load(allocator, &map);
}

fn getBundledTheme(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "default")) return @embedFile("themes/default.conf");
    if (std.mem.eql(u8, name, "dracula")) return @embedFile("themes/dracula.conf");
    if (std.mem.eql(u8, name, "nord")) return @embedFile("themes/nord.conf");
    if (std.mem.eql(u8, name, "solarized-dark")) return @embedFile("themes/solarized-dark.conf");
    return null;
}
