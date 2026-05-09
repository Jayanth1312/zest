/// zest — Phase 2: PTY and Terminal Emulation
const std = @import("std");
const bindings = @import("gl.zig");
const c = bindings.c;
const Font = @import("renderer/Font.zig");
const Renderer = @import("renderer/Renderer.zig");
const Terminal = @import("terminal/Terminal.zig");
const RingBuffer = @import("terminal/RingBuffer.zig");
const Pty = @import("pty/Pty.zig");

const INITIAL_COLS: u32 = 120;
const INITIAL_ROWS: u32 = 35;
const PADDING_X: f32 = 8.0;
const PADDING_Y: f32 = 8.0;

// Global state for GLFW callbacks
var g_pty: ?*Pty.Pty = null;
var g_term: ?*Terminal.Terminal = null;
var g_font: ?*Font.Font = null;

fn glfwErrorCallback(error_code: c_int, description: [*c]const u8) callconv(.c) void {
    std.debug.print("GLFW Error {}: {s}\n", .{ error_code, description });
}

fn charCallback(window: ?*c.GLFWwindow, codepoint: c_uint) callconv(.c) void {
    _ = window;
    if (g_pty) |pty| {
        // UTF-8 encode
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(codepoint), &buf) catch return;
        pty.write(buf[0..len]) catch {};
    }
}

fn mouseButtonCallback(window: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = mods;
    if (button == c.GLFW_MOUSE_BUTTON_LEFT) {
        if (g_term) |term| {
            if (action == c.GLFW_PRESS) {
                var xpos: f64 = 0;
                var ypos: f64 = 0;
                c.glfwGetCursorPos(window, &xpos, &ypos);
                const col = @as(i32, @intFromFloat((@as(f32, @floatCast(xpos)) - PADDING_X) / @as(f32, @floatFromInt(g_font.?.cell_width))));
                const row = @as(i32, @intFromFloat((@as(f32, @floatCast(ypos)) - PADDING_Y) / @as(f32, @floatFromInt(g_font.?.cell_height))));
                
                if (col >= 0 and col < term.cols and row >= 0 and row < term.rows) {
                    term.selection_start = .{ .col = @intCast(col), .row = @intCast(row) };
                    term.selection_end = term.selection_start;
                    term.selection_active = true;
                } else {
                    term.selection_active = false;
                    term.selection_start = null;
                    term.selection_end = null;
                }
            } else if (action == c.GLFW_RELEASE) {
                if (term.selection_start != null and term.selection_end != null) {
                    if (term.selection_start.?.col == term.selection_end.?.col and term.selection_start.?.row == term.selection_end.?.row) {
                        term.selection_active = false;
                        term.selection_start = null;
                        term.selection_end = null;
                    }
                }
                term.selection_active = false;
            }
        }
    }
}

fn cursorPosCallback(window: ?*c.GLFWwindow, xpos: f64, ypos: f64) callconv(.c) void {
    _ = window;
    if (g_term) |term| {
        if (term.selection_active) {
            const col = @as(i32, @intFromFloat((@as(f32, @floatCast(xpos)) - PADDING_X) / @as(f32, @floatFromInt(g_font.?.cell_width))));
            const row = @as(i32, @intFromFloat((@as(f32, @floatCast(ypos)) - PADDING_Y) / @as(f32, @floatFromInt(g_font.?.cell_height))));
            
            const final_col = @as(u32, @intCast(std.math.clamp(col, 0, @as(i32, @intCast(term.cols - 1)))));
            const final_row = @as(u32, @intCast(std.math.clamp(row, 0, @as(i32, @intCast(term.rows - 1)))));
            
            term.selection_end = .{ .col = final_col, .row = final_row };
        }
    }
}

fn keyCallback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = scancode;
    if (action != c.GLFW_PRESS and action != c.GLFW_REPEAT) return;

    if (g_pty) |pty| {
        // Basic key mapping for terminal
        switch (key) {
            c.GLFW_KEY_ENTER => pty.write("\r") catch {},
            c.GLFW_KEY_BACKSPACE => pty.write("\x08") catch {},
            c.GLFW_KEY_TAB => pty.write("\t") catch {},
            c.GLFW_KEY_ESCAPE => pty.write("\x1B") catch {},
            c.GLFW_KEY_UP => pty.write("\x1B[A") catch {},
            c.GLFW_KEY_DOWN => pty.write("\x1B[B") catch {},
            c.GLFW_KEY_RIGHT => pty.write("\x1B[C") catch {},
            c.GLFW_KEY_LEFT => pty.write("\x1B[D") catch {},
            c.GLFW_KEY_HOME => pty.write("\x1B[H") catch {},
            c.GLFW_KEY_END => pty.write("\x1B[F") catch {},
            c.GLFW_KEY_PAGE_UP => pty.write("\x1B[5~") catch {},
            c.GLFW_KEY_PAGE_DOWN => pty.write("\x1B[6~") catch {},
            c.GLFW_KEY_INSERT => pty.write("\x1B[2~") catch {},
            c.GLFW_KEY_DELETE => pty.write("\x1B[3~") catch {},
            c.GLFW_KEY_F1 => pty.write("\x1BOP") catch {},
            c.GLFW_KEY_F2 => pty.write("\x1BOQ") catch {},
            c.GLFW_KEY_F3 => pty.write("\x1BOR") catch {},
            c.GLFW_KEY_F4 => pty.write("\x1BOS") catch {},
            c.GLFW_KEY_F5 => pty.write("\x1B[15~") catch {},
            c.GLFW_KEY_F6 => pty.write("\x1B[17~") catch {},
            c.GLFW_KEY_F7 => pty.write("\x1B[18~") catch {},
            c.GLFW_KEY_F8 => pty.write("\x1B[19~") catch {},
            c.GLFW_KEY_F9 => pty.write("\x1B[20~") catch {},
            c.GLFW_KEY_F10 => pty.write("\x1B[21~") catch {},
            c.GLFW_KEY_F11 => pty.write("\x1B[23~") catch {},
            c.GLFW_KEY_F12 => pty.write("\x1B[24~") catch {},
            else => {
                // Handle Ctrl+Shift+C (Copy) and Ctrl+Shift+V (Paste)
                if ((mods & c.GLFW_MOD_CONTROL) != 0 and (mods & c.GLFW_MOD_SHIFT) != 0) {
                    if (key == c.GLFW_KEY_C) {
                        if (g_term) |term| {
                            const text_opt = term.getSelectedText(std.heap.page_allocator) catch null;
                            if (text_opt) |text| {
                                const c_str = std.heap.page_allocator.dupeZ(u8, text) catch return;
                                defer std.heap.page_allocator.free(c_str);
                                c.glfwSetClipboardString(window, c_str.ptr);
                                std.heap.page_allocator.free(text);
                            }
                        }
                        return;
                    }
                    if (key == c.GLFW_KEY_V) {
                        if (c.glfwGetClipboardString(window)) |text| {
                            const clipboard = std.mem.span(text);
                            if (g_term) |term| {
                                if (term.bracketed_paste_mode) {
                                    pty.write("\x1B[200~") catch {};
                                    pty.write(clipboard) catch {};
                                    pty.write("\x1B[201~") catch {};
                                } else {
                                    pty.write(clipboard) catch {};
                                }
                            } else {
                                pty.write(clipboard) catch {};
                            }
                        }
                        return;
                    }
                }

                // Handle ctrl+letter
                if ((mods & c.GLFW_MOD_CONTROL) != 0 and key >= 'A' and key <= 'Z') {
                    const ctrl_char = [1]u8{ @intCast(key - 'A' + 1) };
                    pty.write(&ctrl_char) catch {};
                }
            },
        }
    }
}

pub fn main() !void {
    // ── Initialize GLFW ──────────────────────────────────────────────
    _ = c.glfwSetErrorCallback(glfwErrorCallback);

    if (c.glfwInit() == c.GLFW_FALSE) {
        return error.GLFWInitFailed;
    }
    defer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_TRUE);

    const window = c.glfwCreateWindow(1280, 720, "zest", null, null) orelse {
        return error.WindowCreationFailed;
    };
    defer c.glfwDestroyWindow(window);

    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1); // VSync on

    var xscale: f32 = 1.0;
    var yscale: f32 = 1.0;
    c.glfwGetWindowContentScale(window, &xscale, &yscale);
    const scale = @max(xscale, yscale);

    _ = c.glfwSetCharCallback(window, charCallback);
    _ = c.glfwSetKeyCallback(window, keyCallback);
    _ = c.glfwSetMouseButtonCallback(window, mouseButtonCallback);
    _ = c.glfwSetCursorPosCallback(window, cursorPosCallback);

    // ── Load Font ────────────────────────────────────────────────────
    const font_paths = [_][*:0]const u8{
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
        "/usr/share/fonts/truetype/ubuntu/UbuntuMono-Regular.ttf",
        "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
        "/usr/share/fonts/liberation/LiberationMono-Regular.ttf",
    };

    var font: ?Font.Font = null;
    for (&font_paths) |path| {
        font = Font.Font.init(std.heap.page_allocator, path, 16, scale) catch continue;
        break;
    }
    var loaded_font = font orelse return error.NoFontFound;
    defer loaded_font.deinit();

    const emoji_paths = [_][*:0]const u8{
        "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf",
        "/usr/share/fonts/noto-emoji/NotoColorEmoji.ttf",
        "/usr/share/fonts/google-noto-emoji/NotoColorEmoji.ttf",
        "/usr/share/fonts/noto/NotoColorEmoji.ttf",
    };
    var emoji_font: ?Font.Font = null;
    for (emoji_paths) |path| {
        emoji_font = Font.Font.init(std.heap.page_allocator, path, 16, scale) catch continue;
        break;
    }
    defer if (emoji_font) |*f| f.deinit();

    // ── Initialize Core Systems ──────────────────────────────────────
    var renderer = try Renderer.Renderer.init(&loaded_font, if (emoji_font) |*f| f else null);
    defer renderer.deinit();

    var term = try Terminal.Terminal.init(std.heap.page_allocator, INITIAL_COLS, INITIAL_ROWS);
    defer term.deinit();

    var pty = try Pty.Pty.spawn(INITIAL_COLS, INITIAL_ROWS);
    g_pty = &pty;
    g_term = &term;
    g_font = &loaded_font;

    var pty_buf = try RingBuffer.RingBuffer.init(std.heap.page_allocator, 1024 * 1024);
    defer pty_buf.deinit();

    // ── Main Loop ────────────────────────────────────────────────────
    var read_buf: [65536]u8 = undefined;

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        // 1. Handle Resize immediately
        var fb_width: c_int = 0;
        var fb_height: c_int = 0;
        c.glfwGetFramebufferSize(window, &fb_width, &fb_height);

        const scaled_padding_x = PADDING_X * scale;
        const scaled_padding_y = PADDING_Y * scale;

        const avail_w = @max(0, fb_width - @as(i32, @intFromFloat(scaled_padding_x * 2.0)));
        const avail_h = @max(0, fb_height - @as(i32, @intFromFloat(scaled_padding_y * 2.0)));
        const new_cols = @max(1, @as(u32, @intCast(avail_w)) / loaded_font.cell_width);
        const new_rows = @max(1, @as(u32, @intCast(avail_h)) / loaded_font.cell_height);

        if (new_cols != term.cols or new_rows != term.rows) {
            try term.resize(new_cols, new_rows);
            pty.resize(@intCast(new_cols), @intCast(new_rows));
        }

        // 2. Read PTY
        const bytes_read = try pty.read(&read_buf);
        if (bytes_read > 0) {
            _ = pty_buf.write(read_buf[0..bytes_read]);
        }

        // 3. Process data
        var parse_buf: [4096]u8 = undefined;
        const available = pty_buf.read(&parse_buf);
        if (available > 0) {
            term.feed(parse_buf[0..available]);
        }

        // 4. Render
        renderer.render(
            &term.grid,
            fb_width,
            fb_height,
            term.cursor_col,
            term.cursor_row,
            c.glfwGetTime(),
            scaled_padding_x,
            scaled_padding_y,
            term.selection_start,
            term.selection_end,
        );

        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }
}
