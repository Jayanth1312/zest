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

        // Determine cell dimensions from the 'M' glyph
        _ = ft.FT_Load_Char(face, 'M', ft.FT_LOAD_RENDER | ft.FT_LOAD_TARGET_LCD);
        const metrics = face.*.size.*.metrics;
        const cell_height: u32 = @intCast(@divTrunc(metrics.height + 63, 64));
        const cell_width: u32 = @intCast(face.*.glyph.*.advance.x >> 6);
        const ascender: i32 = @intCast(@divTrunc(metrics.ascender + 63, 64));

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
};
