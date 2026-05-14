/// zest Renderer — OpenGL 3.3 GPU-accelerated text rendering.
/// Uses a single-pass shader that blends glyph alpha between fg/bg colors.
const std = @import("std");
const bindings = @import("../gl.zig");
const c = bindings.c;
const Atlas = @import("Atlas.zig");
const Font = @import("Font.zig");
const Grid = @import("../terminal/Grid.zig");
const Cell = @import("../terminal/Cell.zig");
const Terminal = @import("../terminal/Terminal.zig");

// Vertex: position(2) + texcoord(2) + fg(3) + bg(3) = 10 floats
const FLOATS_PER_VERTEX = 10;
const VERTICES_PER_CELL = 6; // 2 triangles
const FLOATS_PER_CELL = FLOATS_PER_VERTEX * VERTICES_PER_CELL;

const vertex_shader_src: [*:0]const u8 =
    \\#version 320 es
    \\layout (location = 0) in vec2 aPos;
    \\layout (location = 1) in vec2 aTexCoord;
    \\layout (location = 2) in vec3 aFgColor;
    \\layout (location = 3) in vec3 aBgColor;
    \\out vec2 TexCoord;
    \\out vec3 FgColor;
    \\out vec3 BgColor;
    \\uniform mat4 projection;
    \\void main() {
    \\    gl_Position = projection * vec4(aPos, 0.0, 1.0);
    \\    TexCoord = aTexCoord;
    \\    FgColor = aFgColor;
    \\    BgColor = aBgColor;
    \\}
    \\
;

const fragment_shader_src: [*:0]const u8 =
    \\#version 320 es
    \\precision highp float;
    \\in vec2 TexCoord;
    \\in vec3 FgColor;
    \\in vec3 BgColor;
    \\out vec4 FragColor;
    \\uniform sampler2D glyphAtlas;
    \\void main() {
    \\    // Get the alpha mask from the font atlas
    \\    float alpha = texture(glyphAtlas, TexCoord).r;
    \\    
    \\    // Directly mix the raw hex colors without gamma curves
    \\    vec3 final_color = mix(BgColor, FgColor, alpha);
    \\    FragColor = vec4(final_color, 1.0);
    \\}
    \\
;

pub const Renderer = struct {
    shader_program: c.GLuint,
    vao: c.GLuint,
    vbo: c.GLuint,
    atlas: Atlas.Atlas,
    font: *Font.Font,
    fallback_font: ?*Font.Font,
    vertex_buf: []f32,
    proj_loc: c.GLint,

    pub fn init(font: *Font.Font, fallback_font: ?*Font.Font) !Renderer {
        var atlas = try Atlas.Atlas.init();

        const vs = compileShader(c.GL_VERTEX_SHADER, vertex_shader_src) orelse return error.VertexShaderFailed;
        const fs = compileShader(c.GL_FRAGMENT_SHADER, fragment_shader_src) orelse return error.FragmentShaderFailed;

        const program = c.glCreateProgram();
        c.glAttachShader(program, vs);
        c.glAttachShader(program, fs);
        c.glLinkProgram(program);

        var success: c.GLint = 0;
        c.glGetProgramiv(program, c.GL_LINK_STATUS, &success);
        if (success == 0) {
            var info_log: [512]u8 = undefined;
            c.glGetProgramInfoLog(program, 512, null, &info_log);
            std.debug.print("Shader link error: {s}\n", .{&info_log});
            return error.ShaderLinkFailed;
        }
        c.glDeleteShader(vs);
        c.glDeleteShader(fs);

        const proj_loc = c.glGetUniformLocation(program, "projection");

        // Create VAO and VBO
        var vao: c.GLuint = 0;
        var vbo: c.GLuint = 0;
        c.glGenVertexArrays(1, &vao);
        c.glGenBuffers(1, &vbo);

        c.glBindVertexArray(vao);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);

        const stride: c.GLsizei = FLOATS_PER_VERTEX * @sizeOf(f32);

        // Position: location 0, vec2
        c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(0));
        c.glEnableVertexAttribArray(0);
        // TexCoord: location 1, vec2
        c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(2 * @sizeOf(f32)));
        c.glEnableVertexAttribArray(1);
        // FgColor: location 2, vec3
        c.glVertexAttribPointer(2, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(4 * @sizeOf(f32)));
        c.glEnableVertexAttribArray(2);
        // BgColor: location 3, vec3
        c.glVertexAttribPointer(3, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(7 * @sizeOf(f32)));
        c.glEnableVertexAttribArray(3);

        c.glBindVertexArray(0);

        // Pre-load space glyph so it occupies the 0,0 slot in the atlas and cache
        const space_glyph = try atlas.loadGlyph(font, fallback_font, ' ');
        try font.glyphs.put(' ', space_glyph);

        // Pre-allocate vertex buffer for max 200x50 grid
        const max_cells = 200 * 50;
        const buf = try std.heap.page_allocator.alloc(f32, max_cells * FLOATS_PER_CELL);

        return Renderer{
            .shader_program = program,
            .vao = vao,
            .vbo = vbo,
            .atlas = atlas,
            .font = font,
            .fallback_font = fallback_font,
            .vertex_buf = buf,
            .proj_loc = proj_loc,
        };
    }

    pub fn deinit(self: *Renderer) void {
        c.glDeleteProgram(self.shader_program);
        c.glDeleteVertexArrays(1, &self.vao);
        c.glDeleteBuffers(1, &self.vbo);
        self.atlas.deinit();
        std.heap.page_allocator.free(self.vertex_buf);
    }

    /// Render the entire grid to the screen using physical framebuffer pixels.
    pub fn render(
        self: *Renderer,
        grid: *const Grid.Grid,
        fb_width: i32,
        fb_height: i32,
        offset_x: f32,
        offset_y: f32,
        cursor_col: u32,
        cursor_row: u32,
        current_time: f64,
        last_input_time: f64,
        sel_start: ?Terminal.Pos,
        sel_end: ?Terminal.Pos,
        focused: bool,
    ) void {
        c.glUseProgram(self.shader_program);

        // Build orthographic projection using PHYSICAL framebuffer coordinates
        const w: f32 = @floatFromInt(fb_width);
        const h: f32 = @floatFromInt(fb_height);
        const proj = ortho(0.0, w, h, 0.0, -1.0, 1.0);
        c.glUniformMatrix4fv(self.proj_loc, 1, c.GL_FALSE, &proj);

        // Set atlas texture
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, self.atlas.texture_id);

        // Build vertex data for all cells using PHYSICAL pixel coordinates
        const cw: f32 = @floatFromInt(self.font.cell_width);
        const ch: f32 = @floatFromInt(self.font.cell_height);
        const atlas_w: f32 = @floatFromInt(self.atlas.width);
        const atlas_h: f32 = @floatFromInt(self.atlas.height);

        var vertex_count: u32 = 0;
        var row: u32 = 0;
        while (row < grid.rows) : (row += 1) {
            var col: u32 = 0;
            while (col < grid.cols) : (col += 1) {
                const cell = grid.cellAt(col, row);

                // Skip wide character placeholders
                if (cell.char == 0 and col > 0) {
                    const prev_cell = grid.cellAt(col - 1, row);
                    if (Terminal.Terminal.isWide(prev_cell.char)) continue;
                }

                var fg_color = cell.fg;
                var bg_color = cell.bg;

                // Selection highlight: invert colors
                if (sel_start != null and sel_end != null) {
                    var r0 = sel_start.?.row;
                    var c0 = sel_start.?.col;
                    var r1 = sel_end.?.row;
                    var c1 = sel_end.?.col;
                    if (r0 > r1 or (r0 == r1 and c0 > c1)) {
                        const temp_r = r0; r0 = r1; r1 = temp_r;
                        const temp_c = c0; c0 = c1; c1 = temp_c;
                    }
                    var in_selection = false;
                    if (row > r0 and row < r1) {
                        in_selection = true;
                    } else if (row == r0 and row == r1) {
                        in_selection = col >= c0 and col <= c1;
                    } else if (row == r0) {
                        in_selection = col >= c0;
                    } else if (row == r1) {
                        in_selection = col <= c1;
                    }
                    if (in_selection) {
                        const temp = fg_color;
                        fg_color = bg_color;
                        bg_color = temp;
                        if (fg_color.r == bg_color.r and fg_color.g == bg_color.g and fg_color.b == bg_color.b) {
                            fg_color = Cell.Color.base00;
                            bg_color = Cell.Color.base05;
                        }
                    }
                }

                // Attribute handling: Inverse
                if (cell.attrs.inverse) {
                    const temp = fg_color;
                    fg_color = bg_color;
                    bg_color = temp;
                }

                // Attribute handling: Blink
                if (cell.attrs.blink) {
                    if (@mod(current_time, 1.0) < 0.5) {
                        fg_color = bg_color;
                    }
                }

                // Cursor blink: visible for 2s after input, then blink at 1Hz
                if (focused and col == cursor_col and row == cursor_row) {
                    const time_since_input = current_time - last_input_time;
                    const cursor_on = if (time_since_input < 2.0) true else @mod(current_time, 1.0) < 0.6;
                    if (cursor_on) {
                        bg_color = Cell.Color.base05;
                        fg_color = Cell.Color.base00;
                    }
                }

                const char_idx = if (cell.char == 0) @as(u21, ' ') else cell.char;
                const glyph = self.font.glyphs.get(char_idx) orelse blk: {
                    const new_glyph = self.atlas.loadGlyph(self.font, self.fallback_font, char_idx) catch self.font.glyphs.get(' ').?;
                    self.font.glyphs.put(char_idx, new_glyph) catch {};
                    break :blk new_glyph;
                };

                const fg = fg_color.toFloats();
                const bg = bg_color.toFloats();

                // Cell position in PHYSICAL pixels — no snapping needed
                const is_wide = Terminal.Terminal.isWide(cell.char);
                const x0: f32 = @as(f32, @floatFromInt(col)) * cw + offset_x;
                const y0: f32 = @as(f32, @floatFromInt(row)) * ch + offset_y;
                const x1: f32 = x0 + (if (is_wide) 2.0 * cw else cw);
                const y1: f32 = y0 + ch;

                // Atlas UVs for this glyph's cell
                const tex_u0: f32 = @as(f32, @floatFromInt(glyph.atlas_x)) / atlas_w;
                const tex_v0: f32 = @as(f32, @floatFromInt(glyph.atlas_y)) / atlas_h;
                const tex_u1: f32 = @as(f32, @floatFromInt(glyph.atlas_x + glyph.width)) / atlas_w;
                const tex_v1: f32 = @as(f32, @floatFromInt(glyph.atlas_y + glyph.height)) / atlas_h;

                const base = vertex_count * FLOATS_PER_CELL;
                if (base + FLOATS_PER_CELL > self.vertex_buf.len) break;

                // Triangle 1: top-left, top-right, bottom-left
                writeVertex(self.vertex_buf, base + 0 * FLOATS_PER_VERTEX, x0, y0, tex_u0, tex_v0, fg, bg);
                writeVertex(self.vertex_buf, base + 1 * FLOATS_PER_VERTEX, x1, y0, tex_u1, tex_v0, fg, bg);
                writeVertex(self.vertex_buf, base + 2 * FLOATS_PER_VERTEX, x0, y1, tex_u0, tex_v1, fg, bg);
                // Triangle 2: top-right, bottom-right, bottom-left
                writeVertex(self.vertex_buf, base + 3 * FLOATS_PER_VERTEX, x1, y0, tex_u1, tex_v0, fg, bg);
                writeVertex(self.vertex_buf, base + 4 * FLOATS_PER_VERTEX, x1, y1, tex_u1, tex_v1, fg, bg);
                writeVertex(self.vertex_buf, base + 5 * FLOATS_PER_VERTEX, x0, y1, tex_u0, tex_v1, fg, bg);

                vertex_count += 1;
            }
        }

        // Upload and draw
        c.glBindVertexArray(self.vao);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        const data_size: isize = @intCast(vertex_count * FLOATS_PER_CELL * @sizeOf(f32));
        c.glBufferData(c.GL_ARRAY_BUFFER, data_size, self.vertex_buf.ptr, c.GL_DYNAMIC_DRAW);
        c.glDrawArrays(c.GL_TRIANGLES, 0, @intCast(vertex_count * VERTICES_PER_CELL));
        c.glBindVertexArray(0);
    }
};

fn writeVertex(buf: []f32, offset: usize, x: f32, y: f32, u: f32, v: f32, fg: [3]f32, bg: [3]f32) void {
    buf[offset + 0] = x;
    buf[offset + 1] = y;
    buf[offset + 2] = u;
    buf[offset + 3] = v;
    buf[offset + 4] = fg[0];
    buf[offset + 5] = fg[1];
    buf[offset + 6] = fg[2];
    buf[offset + 7] = bg[0];
    buf[offset + 8] = bg[1];
    buf[offset + 9] = bg[2];
}

fn compileShader(shader_type: c.GLenum, source: [*:0]const u8) ?c.GLuint {
    const shader = c.glCreateShader(shader_type);
    const src_ptr: [*c]const u8 = source;
    c.glShaderSource(shader, 1, &src_ptr, null);
    c.glCompileShader(shader);

    var success: c.GLint = 0;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &success);
    if (success == 0) {
        var info_log: [512]u8 = undefined;
        c.glGetShaderInfoLog(shader, 512, null, &info_log);
        std.debug.print("Shader compile error: {s}\n", .{&info_log});
        c.glDeleteShader(shader);
        return null;
    }
    return shader;
}

/// Build a column-major 4x4 orthographic projection matrix.
fn ortho(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) [16]f32 {
    const rl = right - left;
    const tb = top - bottom;
    const fn_ = far - near;
    return [16]f32{
        2.0 / rl,          0.0,               0.0,              0.0,
        0.0,               2.0 / tb,           0.0,              0.0,
        0.0,               0.0,               -2.0 / fn_,        0.0,
        -(right + left) / rl, -(top + bottom) / tb, -(far + near) / fn_, 1.0,
    };
}
