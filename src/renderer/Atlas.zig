/// zest Atlas — GPU-side dynamic glyph texture atlas.
/// Supports both grayscale (text) and color (emoji) rendering.
const std = @import("std");
const bindings = @import("../gl.zig");
const c = bindings.c;
const ft_c = bindings.ft;
const Font = @import("Font.zig");

const MAX_CELL_BUF = 16384 * 4;

pub const Atlas = struct {
    texture_id: c.GLuint,
    width: u32,
    height: u32,
    cursor_x: u32,
    cursor_y: u32,
    cell_buf: [MAX_CELL_BUF]u8 = undefined,

    pub fn init() !Atlas {
        const width = 2048;
        const height = 2048;

        var texture_id: c.GLuint = 0;
        c.glGenTextures(1, &texture_id);
        c.glBindTexture(c.GL_TEXTURE_2D, texture_id);
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);

        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGBA,
            @intCast(width),
            @intCast(height),
            0,
            c.GL_RGBA,
            c.GL_UNSIGNED_BYTE,
            null,
        );

        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);

        return Atlas{
            .texture_id = texture_id,
            .width = width,
            .height = height,
            .cursor_x = 0,
            .cursor_y = 0,
        };
    }

    pub fn loadGlyph(self: *Atlas, font: *Font.Font, fallback_font: ?*Font.Font, char: u21) !Font.GlyphInfo {
        if (char >= 0x2580 and char <= 0x259F) {
            return self.loadBlockGlyph(font, char);
        }

        const is_wide = @import("../terminal/Terminal.zig").Terminal.isWide(char);
        const slot_width = if (is_wide) font.cell_width * 2 else font.cell_width;
        const slot_height = font.cell_height;

        var face = font.ft_face;
        var load_flags: ft_c.FT_Int32 = ft_c.FT_LOAD_RENDER | ft_c.FT_LOAD_TARGET_LCD;
        var glyph_has_content = false;
        var used_fallback = false;
        var is_emoji = false;

        // FT_Get_Char_Index returns 0 when the character is missing from the font
        // (the .notdef glyph — typically a box). Many monospace fonts render a
        // visible box for unknown codepoints, so checking bitmap.width alone
        // does NOT tell us whether the font actually has the character.
        const char_glyph_idx = ft_c.FT_Get_Char_Index(face, char);
        const load_result = ft_c.FT_Load_Char(face, char, load_flags);
        if (char_glyph_idx != 0 and load_result == 0) {
            const g = face.*.glyph;
            if (char == ' ' or g.*.bitmap.width > 0 and g.*.bitmap.rows > 0) {
                glyph_has_content = true;
            }
        }

        if (!glyph_has_content) {
            if (fallback_font) |fallback| {
                used_fallback = true;
                face = fallback.ft_face;
                load_flags = ft_c.FT_LOAD_RENDER | ft_c.FT_LOAD_COLOR;
                if (ft_c.FT_Load_Char(face, char, load_flags) == 0) {
                    const g = face.*.glyph;
                    if (g.*.bitmap.width > 0 and g.*.bitmap.rows > 0) {
                        glyph_has_content = true;
                        is_emoji = g.*.bitmap.pixel_mode == ft_c.FT_PIXEL_MODE_BGRA;
                    }
                }
                if (!glyph_has_content) {
                    load_flags = ft_c.FT_LOAD_RENDER | ft_c.FT_LOAD_TARGET_LCD;
                    if (ft_c.FT_Load_Char(face, char, load_flags) == 0) {
                        const g = face.*.glyph;
                        if (g.*.bitmap.width > 0 and g.*.bitmap.rows > 0) {
                            glyph_has_content = true;
                        }
                    }
                }
            }
        }

        if (!glyph_has_content) {
            return error.GlyphLoadFailed;
        }

        const g = face.*.glyph;
        const bmp = g.*.bitmap;
        const pixel_mode = bmp.pixel_mode;

        if (self.cursor_x + slot_width > self.width) {
            self.cursor_x = 0;
            self.cursor_y += font.cell_height;
        }

        if (self.cursor_y + font.cell_height > self.height) {
            return error.AtlasFull;
        }

        const buf_size = slot_width * slot_height * 4;
        if (buf_size > MAX_CELL_BUF) return error.GlyphTooLarge;
        @memset(self.cell_buf[0..buf_size], 0);

        if (bmp.width > 0 and bmp.rows > 0 and bmp.buffer != null) {
            const src_bpp: u32 = switch (pixel_mode) {
                ft_c.FT_PIXEL_MODE_LCD => 3,
                ft_c.FT_PIXEL_MODE_BGRA => 4,
                else => 1,
            };
            const logical_width: u32 = switch (pixel_mode) {
                ft_c.FT_PIXEL_MODE_LCD => @intCast(bmp.width / 3),
                ft_c.FT_PIXEL_MODE_BGRA => @intCast(bmp.width),
                else => @intCast(bmp.width),
            };
            const bmp_rows: u32 = @intCast(bmp.rows);

            if (is_emoji and logical_width > 0 and bmp_rows > 0) {
                const sx: f32 = @as(f32, @floatFromInt(slot_width)) / @as(f32, @floatFromInt(logical_width));
                const sy: f32 = @as(f32, @floatFromInt(slot_height)) / @as(f32, @floatFromInt(bmp_rows));
                const scale: f32 = @min(sx, sy);

                const draw_w: u32 = @intFromFloat(@round(@as(f32, @floatFromInt(logical_width)) * scale));
                const draw_h: u32 = @intFromFloat(@round(@as(f32, @floatFromInt(bmp_rows)) * scale));
                const offset_x: i32 = @intFromFloat((@as(f32, @floatFromInt(slot_width)) - @as(f32, @floatFromInt(draw_w))) / 2.0);
                const offset_y: i32 = @intFromFloat((@as(f32, @floatFromInt(slot_height)) - @as(f32, @floatFromInt(draw_h))) / 2.0);

                var dy: u32 = 0;
                while (dy < draw_h) : (dy += 1) {
                    const dst_py: i32 = @as(i32, @intCast(dy)) + offset_y;
                    if (dst_py < 0 or dst_py >= @as(i32, @intCast(slot_height))) continue;

                    var dx: u32 = 0;
                    while (dx < draw_w) : (dx += 1) {
                        const dst_px: i32 = @as(i32, @intCast(dx)) + offset_x;
                        if (dst_px < 0 or dst_px >= @as(i32, @intCast(slot_width))) continue;

                        const src_x: u32 = @intFromFloat(@min(@round(@as(f32, @floatFromInt(dx)) / scale), @as(f32, @floatFromInt(logical_width - 1))));
                        const src_y: u32 = @intFromFloat(@min(@round(@as(f32, @floatFromInt(dy)) / scale), @as(f32, @floatFromInt(bmp_rows - 1))));

                        const dst_idx = @as(u32, @intCast(dst_py * @as(i32, @intCast(slot_width)) + dst_px)) * 4;
                        const src_idx = src_y * @as(u32, @intCast(bmp.pitch)) + src_x * src_bpp;

                        switch (pixel_mode) {
                            ft_c.FT_PIXEL_MODE_BGRA => {
                                self.cell_buf[dst_idx + 0] = bmp.buffer[src_idx + 2];
                                self.cell_buf[dst_idx + 1] = bmp.buffer[src_idx + 1];
                                self.cell_buf[dst_idx + 2] = bmp.buffer[src_idx + 0];
                                self.cell_buf[dst_idx + 3] = bmp.buffer[src_idx + 3];
                            },
                            else => {
                                const val = bmp.buffer[src_idx];
                                self.cell_buf[dst_idx + 0] = val;
                                self.cell_buf[dst_idx + 1] = val;
                                self.cell_buf[dst_idx + 2] = val;
                                self.cell_buf[dst_idx + 3] = val;
                            },
                        }
                    }
                }
            } else {
                const bx = g.*.bitmap_left;
                const by = font.ascender - g.*.bitmap_top;

                var y: u32 = 0;
                while (y < bmp_rows) : (y += 1) {
                    const target_y = @as(i32, @intCast(y)) + by;
                    if (target_y < 0 or target_y >= @as(i32, @intCast(slot_height))) continue;

                    var x: u32 = 0;
                    while (x < logical_width) : (x += 1) {
                        const target_x = @as(i32, @intCast(x)) + bx;
                        if (target_x < 0 or target_x >= @as(i32, @intCast(slot_width))) continue;

                        const src_idx = y * @as(u32, @intCast(bmp.pitch)) + x * src_bpp;
                        const dst_idx = @as(u32, @intCast(target_y * @as(i32, @intCast(slot_width)) + target_x)) * 4;

                        var mask: u8 = 0;
                        switch (pixel_mode) {
                            ft_c.FT_PIXEL_MODE_GRAY => {
                                mask = bmp.buffer[src_idx];
                            },
                            ft_c.FT_PIXEL_MODE_LCD => {
                                const r = bmp.buffer[src_idx + 0];
                                const g_val = bmp.buffer[src_idx + 1];
                                const b = bmp.buffer[src_idx + 2];
                                mask = @intCast((@as(u16, r) + @as(u16, g_val) + @as(u16, b)) / 3);
                            },
                            ft_c.FT_PIXEL_MODE_BGRA => {
                                mask = bmp.buffer[src_idx + 3];
                            },
                            else => {
                                mask = bmp.buffer[src_idx];
                            },
                        }
                        self.cell_buf[dst_idx + 0] = mask;
                        self.cell_buf[dst_idx + 1] = mask;
                        self.cell_buf[dst_idx + 2] = mask;
                        self.cell_buf[dst_idx + 3] = 255;
                    }
                }
            }
        }

        c.glBindTexture(c.GL_TEXTURE_2D, self.texture_id);
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
        c.glPixelStorei(c.GL_UNPACK_ROW_LENGTH, 0);

        c.glTexSubImage2D(
            c.GL_TEXTURE_2D,
            0,
            @intCast(self.cursor_x),
            @intCast(self.cursor_y),
            @intCast(slot_width),
            @intCast(slot_height),
            c.GL_RGBA,
            c.GL_UNSIGNED_BYTE,
            &self.cell_buf,
        );

        const advance: u32 = if (is_emoji) slot_width else @intCast(g.*.advance.x >> 6);

        const glyph_info = Font.GlyphInfo{
            .atlas_x = self.cursor_x,
            .atlas_y = self.cursor_y,
            .width = slot_width,
            .height = slot_height,
            .bearing_x = 0,
            .bearing_y = @intCast(font.ascender),
            .advance = advance,
            .has_glyph = true,
            .is_emoji = is_emoji,
        };

        self.cursor_x += slot_width;

        return glyph_info;
    }

    fn loadBlockGlyph(self: *Atlas, font: *Font.Font, char: u21) !Font.GlyphInfo {
        const width = font.cell_width;
        const height = font.cell_height;

        if (self.cursor_x + width > self.width) {
            self.cursor_x = 0;
            self.cursor_y += height;
        }

        if (self.cursor_y + height > self.height) {
            return error.AtlasFull;
        }

        const buf_size = width * height * 4;
        if (buf_size > MAX_CELL_BUF) return error.GlyphTooLarge;
        @memset(self.cell_buf[0..buf_size], 0);

        const mid_w = width / 2;
        const mid_h = height / 2;

        switch (char) {
            0x2580 => {
                var y: u32 = 0;
                while (y < mid_h) : (y += 1) {
                    @memset(self.cell_buf[y * width * 4 .. (y + 1) * width * 4], 255);
                }
            },
            0x2584 => {
                var y: u32 = mid_h;
                while (y < height) : (y += 1) {
                    @memset(self.cell_buf[y * width * 4 .. (y + 1) * width * 4], 255);
                }
            },
            0x2588 => {
                @memset(self.cell_buf[0..buf_size], 255);
            },
            0x258C => {
                var y: u32 = 0;
                while (y < height) : (y += 1) {
                    @memset(self.cell_buf[y * width * 4 .. (y * width + mid_w) * 4], 255);
                }
            },
            0x2590 => {
                var y: u32 = 0;
                while (y < height) : (y += 1) {
                    @memset(self.cell_buf[(y * width + mid_w) * 4 .. (y + 1) * width * 4], 255);
                }
            },
            0x2596 => {
                var y = mid_h;
                while (y < height) : (y += 1) {
                    @memset(self.cell_buf[y * width * 4 .. (y * width + mid_w) * 4], 255);
                }
            },
            0x2597 => {
                var y = mid_h;
                while (y < height) : (y += 1) {
                    @memset(self.cell_buf[(y * width + mid_w) * 4 .. (y + 1) * width * 4], 255);
                }
            },
            0x2598 => {
                var y: u32 = 0;
                while (y < mid_h) : (y += 1) {
                    @memset(self.cell_buf[y * width * 4 .. (y * width + mid_w) * 4], 255);
                }
            },
            0x259D => {
                var y: u32 = 0;
                while (y < mid_h) : (y += 1) {
                    @memset(self.cell_buf[(y * width + mid_w) * 4 .. (y + 1) * width * 4], 255);
                }
            },
            0x2582 => {
                var y: u32 = height - (height / 4);
                while (y < height) : (y += 1) {
                    @memset(self.cell_buf[y * width * 4 .. (y + 1) * width * 4], 255);
                }
            },
            0x2586 => {
                var y: u32 = height / 4;
                while (y < height) : (y += 1) {
                    @memset(self.cell_buf[y * width * 4 .. (y + 1) * width * 4], 255);
                }
            },
            0x2587 => {
                var y: u32 = height / 8;
                while (y < height) : (y += 1) {
                    @memset(self.cell_buf[y * width * 4 .. (y + 1) * width * 4], 255);
                }
            },
            else => {
                @memset(self.cell_buf[0..buf_size], 255);
            },
        }

        c.glBindTexture(c.GL_TEXTURE_2D, self.texture_id);
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
        c.glPixelStorei(c.GL_UNPACK_ROW_LENGTH, 0);

        c.glTexSubImage2D(
            c.GL_TEXTURE_2D,
            0,
            @intCast(self.cursor_x),
            @intCast(self.cursor_y),
            @intCast(width),
            @intCast(height),
            c.GL_RGBA,
            c.GL_UNSIGNED_BYTE,
            self.cell_buf[0..buf_size].ptr,
        );

        const glyph_info = Font.GlyphInfo{
            .atlas_x = self.cursor_x,
            .atlas_y = self.cursor_y,
            .width = width,
            .height = height,
            .bearing_x = 0,
            .bearing_y = @intCast(font.ascender),
            .advance = @intCast(width),
            .has_glyph = true,
            .is_emoji = false,
        };

        self.cursor_x += width;
        return glyph_info;
    }

    pub fn reset(self: *Atlas) !void {
        c.glDeleteTextures(1, &self.texture_id);

        var texture_id: c.GLuint = 0;
        c.glGenTextures(1, &texture_id);
        c.glBindTexture(c.GL_TEXTURE_2D, texture_id);
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);

        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGBA,
            @intCast(self.width),
            @intCast(self.height),
            0,
            c.GL_RGBA,
            c.GL_UNSIGNED_BYTE,
            null,
        );

        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);

        self.texture_id = texture_id;
        self.cursor_x = 0;
        self.cursor_y = 0;
    }

    pub fn deinit(self: *Atlas) void {
        c.glDeleteTextures(1, &self.texture_id);
    }
};