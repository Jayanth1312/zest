/// zest Font — FreeType-based font loading and glyph metrics.
const std = @import("std");
const bindings = @import("../gl.zig");
const ft = bindings.ft;

pub const GlyphInfo = struct {
    atlas_x: u32 = 0,
    atlas_y: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    bearing_x: i32 = 0,
    bearing_y: i32 = 0,
    advance: u32 = 0,
    has_glyph: bool = false,
    is_emoji: bool = false,
};

pub const Font = struct {
    ft_lib: ft.FT_Library,
    ft_face: ft.FT_Face,
    cell_width: u32,
    cell_height: u32,
    ascender: i32,
    glyphs: std.AutoHashMap(u21, GlyphInfo),
    allocator: std.mem.Allocator,

    /// Initialize FreeType and load a monospace font at the given physical pixel size.
    pub fn init(allocator: std.mem.Allocator, font_path: [*:0]const u8, pixel_size: u32) !Font {
    var lib: ft.FT_Library = null;
    if (ft.FT_Init_FreeType(&lib) != 0) {
        return error.FreeTypeInitFailed;
    }

    var face: ft.FT_Face = null;
    if (ft.FT_New_Face(lib, font_path, 0, &face) != 0) {
        return error.FontLoadFailed;
    }

    _ = ft.FT_Library_SetLcdFilter(lib, ft.FT_LCD_FILTER_DEFAULT);
    _ = ft.FT_Set_Pixel_Sizes(face, 0, pixel_size);

        _ = ft.FT_Load_Char(face, 'M', ft.FT_LOAD_RENDER | ft.FT_LOAD_TARGET_LCD);
        const metrics = face.*.size.*.metrics;

        const ascender: i32 = @intCast(@divTrunc(metrics.ascender + 63, 64));
        const descender: i32 = @intCast(@divTrunc(metrics.descender - 63, 64)); 
        
        const cell_height: u32 = @intCast(ascender - descender);
        const cell_width: u32 = @intCast(face.*.glyph.*.advance.x >> 6);

        const glyphs = std.AutoHashMap(u21, GlyphInfo).init(allocator);

        return Font{
            .ft_lib = lib,
            .ft_face = face,
            .cell_width = cell_width,
            .cell_height = cell_height,
            .ascender = ascender,
            .glyphs = glyphs,
            .allocator = allocator,
        };
}

pub fn deinit(self: *Font) void {
    self.glyphs.deinit();
    _ = ft.FT_Done_Face(self.ft_face);
    _ = ft.FT_Done_FreeType(self.ft_lib);
}

pub fn isEmoji(char: u21) bool {
    if (char >= 0x1F600 and char <= 0x1F64F) return true;
    if (char >= 0x1F300 and char <= 0x1F5FF) return true;
    if (char >= 0x1F680 and char <= 0x1F6FF) return true;
    if (char >= 0x1F900 and char <= 0x1F9FF) return true;
    if (char >= 0x1FA00 and char <= 0x1FA6F) return true;
    if (char >= 0x1FA70 and char <= 0x1FAFF) return true;
    if (char >= 0x2600 and char <= 0x26FF) return true;
    if (char >= 0x2700 and char <= 0x27BF) return true;
    if (char >= 0xFE00 and char <= 0xFE0F) return true;
    if (char >= 0x1F1E0 and char <= 0x1F1FF) return true;
    if (char >= 0x200D and char <= 0x200D) return true;
    if (char >= 0x231A and char <= 0x231B) return true;
    if (char >= 0x23E9 and char <= 0x23F3) return true;
    if (char >= 0x23F8 and char <= 0x23FA) return true;
    if (char >= 0x25AA and char <= 0x25AB) return true;
    if (char >= 0x25B6 and char <= 0x25B6) return true;
    if (char >= 0x25C0 and char <= 0x25C0) return true;
    if (char >= 0x25FB and char <= 0x25FE) return true;
    if (char >= 0x2614 and char <= 0x2615) return true;
    if (char >= 0x2648 and char <= 0x2653) return true;
    if (char >= 0x267F and char <= 0x267F) return true;
    if (char >= 0x2693 and char <= 0x2693) return true;
    if (char >= 0x26A1 and char <= 0x26A1) return true;
    if (char >= 0x26AA and char <= 0x26AB) return true;
    if (char >= 0x26BD and char <= 0x26BE) return true;
    if (char >= 0x26C4 and char <= 0x26C5) return true;
    if (char >= 0x26CE and char <= 0x26CE) return true;
    if (char >= 0x26D4 and char <= 0x26D4) return true;
    if (char >= 0x26EA and char <= 0x26EA) return true;
    if (char >= 0x26F2 and char <= 0x26F3) return true;
    if (char >= 0x26F5 and char <= 0x26F5) return true;
    if (char >= 0x26FA and char <= 0x26FA) return true;
    if (char >= 0x26FD and char <= 0x26FD) return true;
    if (char >= 0x2702 and char <= 0x2702) return true;
    if (char >= 0x2705 and char <= 0x2705) return true;
    if (char >= 0x2708 and char <= 0x270D) return true;
    if (char >= 0x270F and char <= 0x270F) return true;
    if (char >= 0x2712 and char <= 0x2712) return true;
    if (char >= 0x2714 and char <= 0x2714) return true;
    if (char >= 0x2716 and char <= 0x2716) return true;
    if (char >= 0x271D and char <= 0x271D) return true;
    if (char >= 0x2721 and char <= 0x2721) return true;
    if (char >= 0x2728 and char <= 0x2728) return true;
    if (char >= 0x2733 and char <= 0x2734) return true;
    if (char >= 0x2744 and char <= 0x2744) return true;
    if (char >= 0x2747 and char <= 0x2747) return true;
    if (char >= 0x274C and char <= 0x274C) return true;
    if (char >= 0x274E and char <= 0x274E) return true;
    if (char >= 0x2753 and char <= 0x2755) return true;
    if (char >= 0x2757 and char <= 0x2757) return true;
    if (char >= 0x2763 and char <= 0x2764) return true;
    if (char >= 0x2795 and char <= 0x2797) return true;
    if (char >= 0x27A1 and char <= 0x27A1) return true;
    if (char >= 0x27B0 and char <= 0x27B0) return true;
    if (char >= 0x27BF and char <= 0x27BF) return true;
    if (char >= 0x2934 and char <= 0x2935) return true;
    if (char >= 0x2B05 and char <= 0x2B07) return true;
    if (char >= 0x2B1B and char <= 0x2B1C) return true;
    if (char >= 0x2B50 and char <= 0x2B50) return true;
    if (char >= 0x2B55 and char <= 0x2B55) return true;
    if (char >= 0x3030 and char <= 0x3030) return true;
    if (char >= 0x303D and char <= 0x303D) return true;
    if (char >= 0x3297 and char <= 0x3297) return true;
    if (char >= 0x3299 and char <= 0x3299) return true;
    if (char >= 0x1F004 and char <= 0x1F004) return true;
    if (char >= 0x1F0CF and char <= 0x1F0CF) return true;
    if (char >= 0x1F170 and char <= 0x1F171) return true;
    if (char >= 0x1F17E and char <= 0x1F17F) return true;
    if (char >= 0x1F18E and char <= 0x1F18E) return true;
    if (char >= 0x1F191 and char <= 0x1F19A) return true;
    if (char >= 0x1F201 and char <= 0x1F202) return true;
    if (char >= 0x1F21A and char <= 0x1F21A) return true;
    if (char >= 0x1F22F and char <= 0x1F22F) return true;
    if (char >= 0x1F232 and char <= 0x1F23A) return true;
    if (char >= 0x1F250 and char <= 0x1F251) return true;
    if (char >= 0x1F300 and char <= 0x1F320) return true;
    if (char >= 0x1F32D and char <= 0x1F335) return true;
    if (char >= 0x1F337 and char <= 0x1F37C) return true;
    if (char >= 0x1F37E and char <= 0x1F393) return true;
    if (char >= 0x1F3A0 and char <= 0x1F3CA) return true;
    if (char >= 0x1F3CF and char <= 0x1F3D3) return true;
    if (char >= 0x1F3E0 and char <= 0x1F3F0) return true;
    if (char >= 0x1F3F4 and char <= 0x1F3F4) return true;
    if (char >= 0x1F3F8 and char <= 0x1F43E) return true;
    if (char >= 0x1F440 and char <= 0x1F440) return true;
    if (char >= 0x1F442 and char <= 0x1F4FC) return true;
    if (char >= 0x1F4FF and char <= 0x1F53D) return true;
    if (char >= 0x1F54B and char <= 0x1F54E) return true;
    if (char >= 0x1F550 and char <= 0x1F567) return true;
    if (char >= 0x1F57A and char <= 0x1F57A) return true;
    if (char >= 0x1F595 and char <= 0x1F596) return true;
    if (char >= 0x1F5A4 and char <= 0x1F5A4) return true;
    if (char >= 0x1F5FB and char <= 0x1F64F) return true;
    if (char >= 0x1F680 and char <= 0x1F6C5) return true;
    if (char >= 0x1F6CC and char <= 0x1F6CC) return true;
    if (char >= 0x1F6D0 and char <= 0x1F6D2) return true;
    if (char >= 0x1F6D5 and char <= 0x1F6D7) return true;
    if (char >= 0x1F6EB and char <= 0x1F6EC) return true;
    if (char >= 0x1F6F4 and char <= 0x1F6FC) return true;
    if (char >= 0x1F7E0 and char <= 0x1F7EB) return true;
    if (char >= 0x1F90C and char <= 0x1F93A) return true;
    if (char >= 0x1F93C and char <= 0x1F945) return true;
    if (char >= 0x1F947 and char <= 0x1F9FF) return true;
    if (char >= 0x1FA70 and char <= 0x1FA7C) return true;
    if (char >= 0x1FA80 and char <= 0x1FA88) return true;
    if (char >= 0x1FA90 and char <= 0x1FABD) return true;
    if (char >= 0x1FABF and char <= 0x1FAC5) return true;
    if (char >= 0x1FACE and char <= 0x1FADB) return true;
    if (char >= 0x1FAE0 and char <= 0x1FAE8) return true;
    if (char >= 0x1FAF0 and char <= 0x1FAF8) return true;
    return false;
}
};
