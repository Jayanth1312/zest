/// zest Atlas — GPU-side dynamic glyph texture atlas.
/// Rasterizes Unicode glyphs on the fly and packs them into an OpenGL texture.
const std = @import("std");
const bindings = @import("../gl.zig");
const c = bindings.c;
const ft_c = bindings.ft;
const Font = @import("Font.zig");

pub const Atlas = struct {
    texture_id: c.GLuint,
    width: u32,
    height: u32,
    cursor_x: u32,
    cursor_y: u32,
    row_height: u32,

    /// Initialize an empty dynamic texture atlas.
    pub fn init(font: *Font.Font) !Atlas {
        _ = font; // Not used during init, we start empty
        const width = 1024;
        const height = 1024;

        var texture_id: c.GLuint = 0;
        c.glGenTextures(1, &texture_id);
        c.glBindTexture(c.GL_TEXTURE_2D, texture_id);
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);

        // Allocate empty GPU buffer
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGB,
            @intCast(width),
            @intCast(height),
            0,
            c.GL_RGB,
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
            .row_height = 0,
        };
    }

    /// Dynamically render a character and pack its bitmap into the GPU atlas.
    pub fn loadGlyph(self: *Atlas, font: *Font.Font, fallback_font: ?*Font.Font, char: u21) !Font.GlyphInfo {
        // Intercept block drawing characters (U+2580 to U+259F) for perfect rendering
        if (char >= 0x2580 and char <= 0x259F) {
            return self.loadBlockGlyph(font, char);
        }

        const is_wide = @import("../terminal/Terminal.zig").Terminal.isWide(char);
        const slot_width = if (is_wide) font.cell_width * 2 else font.cell_width;
        const slot_height = font.cell_height;

        var face = font.ft_face;
        if (ft_c.FT_Load_Char(face, char, ft_c.FT_LOAD_RENDER | ft_c.FT_LOAD_TARGET_LCD) != 0) {
            if (fallback_font) |fallback| {
                face = fallback.ft_face;
                if (ft_c.FT_Load_Char(face, char, ft_c.FT_LOAD_RENDER | ft_c.FT_LOAD_TARGET_LCD) != 0) {
                    return error.GlyphLoadFailed;
                }
            } else {
                return error.GlyphLoadFailed;
            }
        }

        const g = face.*.glyph;
        const bmp = g.*.bitmap;

        // Check if we need a new row
        if (self.cursor_x + slot_width > self.width) {
            self.cursor_x = 0;
            self.cursor_y += font.cell_height;
        }

        // Check if atlas is full
        if (self.cursor_y + font.cell_height > self.height) {
            return error.AtlasFull;
        }

        // Create a temporary buffer for the full cell slot (3 bytes per pixel for RGB)
        const buf_size = slot_width * slot_height * 3;
        const cell_buf = try std.heap.page_allocator.alloc(u8, buf_size);
        defer std.heap.page_allocator.free(cell_buf);
        @memset(cell_buf, 0);

        // Blit the glyph bitmap into the cell buffer at the correct bearing offset
        if (bmp.width > 0 and bmp.rows > 0 and bmp.buffer != null) {
            const bx = g.*.bitmap_left;
            const by = font.ascender - g.*.bitmap_top;

            var y: u32 = 0;
            while (y < bmp.rows) : (y += 1) {
                const target_y = @as(i32, @intCast(y)) + by;
                if (target_y < 0 or target_y >= slot_height) continue;

                var x: u32 = 0;
                while (x < bmp.width / 3) : (x += 1) { // 3 channels per logical pixel
                    const target_x = @as(i32, @intCast(x)) + bx;
                    if (target_x < 0 or target_x >= slot_width) continue;
                    
                    const src_idx = y * @as(u32, @intCast(bmp.pitch)) + x * 3;
                    const dst_idx = @as(u32, @intCast(target_y * @as(i32, @intCast(slot_width)) + target_x)) * 3;
                    cell_buf[dst_idx + 0] = bmp.buffer[src_idx + 0];
                    cell_buf[dst_idx + 1] = bmp.buffer[src_idx + 1];
                    cell_buf[dst_idx + 2] = bmp.buffer[src_idx + 2];
                }
            }
        }

        // Upload the full cell slot to the GPU
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
            c.GL_RGB,
            c.GL_UNSIGNED_BYTE,
            cell_buf.ptr,
        );

        const glyph_info = Font.GlyphInfo{
            .atlas_x = self.cursor_x,
            .atlas_y = self.cursor_y,
            .width = slot_width,
            .height = slot_height,
            .bearing_x = 0,
            .bearing_y = @intCast(font.ascender),
            .advance = @intCast(g.*.advance.x >> 6),
            .has_glyph = true,
        };

        // Advance cursor by full slot width
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

        const buf_size = width * height * 3;
        var buf = try std.heap.page_allocator.alloc(u8, buf_size);
        defer std.heap.page_allocator.free(buf);
        @memset(buf, 0);

        const mid_w = width / 2;
        const mid_h = height / 2;

        switch (char) {
            0x2580 => { // Upper half block
                var y: u32 = 0;
                while (y < mid_h) : (y += 1) {
                    @memset(buf[y * width * 3 .. (y + 1) * width * 3], 255);
                }
            },
            0x2584 => { // Lower half block
                var y: u32 = mid_h;
                while (y < height) : (y += 1) {
                    @memset(buf[y * width * 3 .. (y + 1) * width * 3], 255);
                }
            },
            0x2588 => { // Full block
                @memset(buf, 255);
            },
            0x258C => { // Left half block
                var y: u32 = 0;
                while (y < height) : (y += 1) {
                    @memset(buf[y * width * 3 .. (y * width + mid_w) * 3], 255);
                }
            },
            0x2590 => { // Right half block
                var y: u32 = 0;
                while (y < height) : (y += 1) {
                    @memset(buf[(y * width + mid_w) * 3 .. (y + 1) * width * 3], 255);
                }
            },
            0x2596 => { // Quadrant lower left
                var y = mid_h;
                while (y < height) : (y += 1) {
                    @memset(buf[y * width * 3 .. (y * width + mid_w) * 3], 255);
                }
            },
            0x2597 => { // Quadrant lower right
                var y = mid_h;
                while (y < height) : (y += 1) {
                    @memset(buf[(y * width + mid_w) * 3 .. (y + 1) * width * 3], 255);
                }
            },
            0x2598 => { // Quadrant upper left
                var y: u32 = 0;
                while (y < mid_h) : (y += 1) {
                    @memset(buf[y * width * 3 .. (y * width + mid_w) * 3], 255);
                }
            },
            0x259D => { // Quadrant upper right
                var y: u32 = 0;
                while (y < mid_h) : (y += 1) {
                    @memset(buf[(y * width + mid_w) * 3 .. (y + 1) * width * 3], 255);
                }
            },
            0x2582 => { // Lower quarter block
                var y: u32 = height - (height / 4);
                while (y < height) : (y += 1) {
                    @memset(buf[y * width * 3 .. (y + 1) * width * 3], 255);
                }
            },
            0x2586 => { // Lower three quarters block
                var y: u32 = height / 4;
                while (y < height) : (y += 1) {
                    @memset(buf[y * width * 3 .. (y + 1) * width * 3], 255);
                }
            },
            0x2587 => { // Lower seven eighths block
                var y: u32 = height / 8;
                while (y < height) : (y += 1) {
                    @memset(buf[y * width * 3 .. (y + 1) * width * 3], 255);
                }
            },
            else => { // Fallback to full block for other range characters
                @memset(buf, 255);
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
            c.GL_RGB,
            c.GL_UNSIGNED_BYTE,
            buf.ptr,
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
        };

        self.cursor_x += width;
        return glyph_info;
    }

    pub fn deinit(self: *Atlas) void {
        c.glDeleteTextures(1, &self.texture_id);
    }
};
