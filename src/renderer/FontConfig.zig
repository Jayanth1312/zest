/// zest Fontconfig bindings for system font discovery.
const std = @import("std");
const fc = @import("c_fc");

var cached_config: ?*fc.FcConfig = null;

pub fn init() bool {
    return fc.FcInit() == fc.FcTrue;
}

pub fn deinit() void {
    fc.FcFini();
    cached_config = null;
}

fn getConfig() ?*fc.FcConfig {
    if (cached_config == null) {
        cached_config = fc.FcInitLoadConfigAndFonts();
    }
    return cached_config;
}

pub fn findMonospaceFont(allocator: std.mem.Allocator) !?[]const u8 {
    const pat = fc.FcPatternCreate();
    if (pat == null) return null;
    defer fc.FcPatternDestroy(pat);

    _ = fc.FcPatternAddString(pat, "spacing", "mono");
    _ = fc.FcPatternAddBool(pat, "scalable", fc.FcTrue);

    const config = getConfig() orelse return null;

    var result: fc.FcResult = undefined;
    const sorted = fc.FcFontSort(config, pat, fc.FcTrue, null, &result);
    if (sorted == null) return null;
    defer fc.FcFontSetDestroy(sorted);

    if (sorted.*.nfont > 0) {
        const font = sorted.*.fonts[0];
        var file: [*c]u8 = undefined;
        if (fc.FcPatternGetString(font, "file", 0, &file) == fc.FcResultMatch) {
            return try allocator.dupe(u8, std.mem.span(file));
        }
    }

    return null;
}

pub fn findEmojiFont(allocator: std.mem.Allocator) !?[]const u8 {
    const families = [_][*:0]const u8{
        "Noto Color Emoji",
        "Apple Color Emoji",
        "Segoe UI Emoji",
        "Twitter Color Emoji",
        "JoyPixels",
        "EmojiOne Mozilla",
        "Noto Emoji",
    };

    const config = getConfig() orelse return null;

    for (families) |family| {
        const pat = fc.FcPatternCreate();
        if (pat == null) continue;
        defer fc.FcPatternDestroy(pat);

        _ = fc.FcPatternAddString(pat, "family", family);

        var result: fc.FcResult = undefined;
        const sorted = fc.FcFontSort(config, pat, fc.FcTrue, null, &result);
        if (sorted == null) continue;
        defer fc.FcFontSetDestroy(sorted);

        if (sorted.*.nfont > 0) {
            const font = sorted.*.fonts[0];
            var file: [*c]u8 = undefined;
            if (fc.FcPatternGetString(font, "file", 0, &file) == fc.FcResultMatch) {
                return try allocator.dupe(u8, std.mem.span(file));
            }
        }
    }

    return null;
}
