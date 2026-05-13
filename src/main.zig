/// zest — Terminal emulator with GTK4 native Wayland/X11 support.
const std = @import("std");
const bindings = @import("gl.zig");
const c = bindings.c;
const Font = @import("renderer/Font.zig");
const Renderer = @import("renderer/Renderer.zig");
const Terminal = @import("terminal/Terminal.zig");
const RingBuffer = @import("terminal/RingBuffer.zig");
const Pty = @import("pty/Pty.zig");
const GtkKey = @import("apprt/gtk/key.zig");

const INITIAL_COLS: u32 = 120;
const INITIAL_ROWS: u32 = 35;
const PADDING_X: f32 = 8.0;
const PADDING_Y: f32 = 8.0;

// ── GTK4 extern declarations ───────────────────────────────────────
const GtkApplication = opaque {};
const GtkWindow = opaque {};
const GtkGLArea = opaque {};
const GtkWidget = opaque {};
const GtkEventControllerKey = opaque {};
const GtkEventControllerMotion = opaque {};
const GtkGestureClick = opaque {};
const GtkIMContext = opaque {};
const cairo_t = opaque {};

extern fn gtk_application_new(id: [*:0]const u8, flags: c_int) *GtkApplication;
extern fn g_signal_connect_data(instance: *anyopaque, signal: [*:0]const u8, handler: ?*anyopaque, data: ?*anyopaque, destroy_data: ?*anyopaque, flags: c_uint) c_ulong;

fn signalConnect(instance: *anyopaque, signal: [*:0]const u8, handler: *anyopaque, data: ?*anyopaque) c_ulong {
    return g_signal_connect_data(instance, signal, handler, data, null, 0);
}
extern fn g_application_run(app: *GtkApplication, argc: c_int, argv: ?*[*:0]u8) c_int;
extern fn gtk_application_window_new(app: *GtkApplication) *GtkWindow;
extern fn gtk_window_set_title(win: *GtkWindow, title: [*:0]const u8) void;
extern fn gtk_window_set_default_size(win: *GtkWindow, w: c_int, h: c_int) void;
extern fn gtk_widget_get_width(widget: *GtkWidget) c_int;
extern fn gtk_widget_get_height(widget: *GtkWidget) c_int;
extern fn gtk_window_set_child(win: *GtkWindow, child: *GtkWidget) void;
extern fn gtk_window_present(win: *GtkWindow) void;
extern fn gtk_gl_area_new() *GtkGLArea;
extern fn gtk_gl_area_set_auto_render(area: *GtkGLArea, auto_render: c_int) void;
extern fn gtk_gl_area_set_has_stencil_buffer(area: *GtkGLArea, has: c_int) void;
extern fn gtk_gl_area_set_has_depth_buffer(area: *GtkGLArea, has: c_int) void;
extern fn gtk_gl_area_queue_render(area: *GtkGLArea) void;
extern fn gtk_gl_area_make_current(area: *GtkGLArea) void;
extern fn gtk_gl_area_set_use_es(area: *GtkGLArea, use_es: c_int) void;
extern fn gtk_widget_add_controller(widget: *GtkWidget, controller: *anyopaque) void;
extern fn gtk_widget_set_focusable(widget: *GtkWidget, focusable: c_int) void;
extern fn gtk_widget_grab_focus(widget: *GtkWidget) void;
extern fn gtk_event_controller_key_new() *GtkEventControllerKey;
extern fn gtk_event_controller_motion_new() *GtkEventControllerMotion;
extern fn gtk_gesture_click_new() *GtkGestureClick;
extern fn gtk_gesture_single_get_current_button(gesture: *anyopaque) c_int;
extern fn gtk_im_multicontext_new() *GtkIMContext;
extern fn gtk_im_context_set_client_widget(ctx: *GtkIMContext, widget: *GtkWidget) void;
extern fn g_idle_add(func: *const fn (?*anyopaque) callconv(.c) c_int, data: ?*anyopaque) c_uint;
extern fn clock_gettime(clk_id: c_int, tp: *std.c.timespec) c_int;

const CLOCK_MONOTONIC: c_int = 1;
const G_APPLICATION_FLAGS_NONE: c_int = 0;

// ── Global state ───────────────────────────────────────────────────
var g_pty: ?*Pty.Pty = null;
var g_term: ?*Terminal.Terminal = null;
var g_font: ?*Font.Font = null;
var g_renderer: ?*Renderer.Renderer = null;
var g_last_input_time: f64 = 0.0;
var g_dpi_scale: f32 = 1.0;
var g_initialized: bool = false;

var g_app: ?*GtkApplication = null;
var g_window: ?*GtkWindow = null;
var g_gl_area: ?*GtkGLArea = null;
var g_scale_factor: f32 = 1.0;
var g_fb_width: i32 = 0;
var g_fb_height: i32 = 0;
var g_win_width: i32 = 0;
var g_win_height: i32 = 0;

fn getTime() f64 {
    var ts: std.c.timespec = undefined;
    _ = clock_gettime(CLOCK_MONOTONIC, &ts);
    return @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) / 1_000_000_000.0;
}

fn updateSizes() void {
    if (g_window) |win| {
        g_win_width = gtk_widget_get_width(@ptrCast(win));
        g_win_height = gtk_widget_get_height(@ptrCast(win));
        if (g_win_width > 0) {
            g_scale_factor = @as(f32, @floatFromInt(g_fb_width)) / @as(f32, @floatFromInt(g_win_width));
        }
    }
}

fn queueRender() void {
    if (g_gl_area) |area| gtk_gl_area_queue_render(area);
}

// ── GTK C callbacks ────────────────────────────────────────────────
fn gl_realize_cb(_: ?*GtkGLArea, _: ?*anyopaque) callconv(.c) void {
    if (g_gl_area) |area| {
        gtk_gl_area_make_current(area);
    }

    const font_paths = [_][*:0]const u8{
        "/usr/share/zest/fonts/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
        "/usr/share/fonts/truetype/ubuntu/UbuntuMono-Regular.ttf",
        "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
        "/usr/share/fonts/liberation/LiberationMono-Regular.ttf",
    };
    const font_pixel_size: u32 = 32;
    var font: ?Font.Font = null;
    for (&font_paths) |path| {
        font = Font.Font.init(std.heap.page_allocator, path, font_pixel_size) catch continue;
        break;
    }
    const loaded_font = font orelse {
        std.debug.print("zest: no font found\n", .{});
        return;
    };
    const font_ptr = std.heap.page_allocator.create(Font.Font) catch return;
    font_ptr.* = loaded_font;
    g_font = font_ptr;

    const emoji_paths = [_][*:0]const u8{
        "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf",
        "/usr/share/fonts/noto-emoji/NotoColorEmoji.ttf",
        "/usr/share/fonts/google-noto-emoji/NotoColorEmoji.ttf",
        "/usr/share/fonts/noto/NotoColorEmoji.ttf",
    };
    var emoji_font: ?Font.Font = null;
    for (emoji_paths) |path| {
        emoji_font = Font.Font.init(std.heap.page_allocator, path, 26) catch continue;
        break;
    }
    var emoji_ptr: ?*Font.Font = null;
    if (emoji_font) |ef| {
        emoji_ptr = std.heap.page_allocator.create(Font.Font) catch null;
        if (emoji_ptr) |p| p.* = ef;
    }

    const renderer_ptr = std.heap.page_allocator.create(Renderer.Renderer) catch return;
    renderer_ptr.* = Renderer.Renderer.init(font_ptr, emoji_ptr) catch {
        std.debug.print("zest: renderer init failed\n", .{});
        return;
    };
    g_renderer = renderer_ptr;

    const term_ptr = std.heap.page_allocator.create(Terminal.Terminal) catch return;
    term_ptr.* = Terminal.Terminal.init(std.heap.page_allocator, INITIAL_COLS, INITIAL_ROWS) catch return;
    g_term = term_ptr;

    const pty_ptr = std.heap.page_allocator.create(Pty.Pty) catch return;
    pty_ptr.* = Pty.Pty.spawn(INITIAL_COLS, INITIAL_ROWS) catch return;
    g_pty = pty_ptr;

    g_initialized = true;
    _ = g_idle_add(ptyReadIdle, null);
}

fn gl_render_cb(_: ?*GtkGLArea, _: ?*cairo_t, _: ?*anyopaque) callconv(.c) c_int {
    if (!g_initialized or g_renderer == null or g_term == null) return 1;
    if (g_gl_area) |area| {
        gtk_gl_area_make_current(area);
    }
    const pad_x: f32 = PADDING_X * g_dpi_scale;
    const pad_y: f32 = PADDING_Y * g_dpi_scale;
    g_renderer.?.render(
        &g_term.?.grid, g_fb_width, g_fb_height,
        g_term.?.cursor_col, g_term.?.cursor_row,
        getTime(), g_last_input_time, pad_x, pad_y,
        g_term.?.selection_start, g_term.?.selection_end,
    );
    return 1;
}

fn gl_resize_cb(_: ?*GtkGLArea, w: c_int, h: c_int, _: ?*anyopaque) callconv(.c) void {
    g_fb_width = w;
    g_fb_height = h;
    updateSizes();
    if (g_term != null and g_pty != null and g_font != null) {
        const pad_x: f32 = PADDING_X * g_dpi_scale;
        const pad_y: f32 = PADDING_Y * g_dpi_scale;
        const avail_w = @max(0.0, @as(f32, @floatFromInt(w)) - (pad_x * 2.0));
        const avail_h = @max(0.0, @as(f32, @floatFromInt(h)) - (pad_y * 2.0));
        const new_cols = @max(1, @as(u32, @intFromFloat(avail_w / @as(f32, @floatFromInt(g_font.?.cell_width)))));
        const new_rows = @max(1, @as(u32, @intFromFloat(avail_h / @as(f32, @floatFromInt(g_font.?.cell_height)))));
        if (new_cols != g_term.?.cols or new_rows != g_term.?.rows) {
            g_term.?.resize(new_cols, new_rows) catch {};
            g_pty.?.resize(@intCast(new_cols), @intCast(new_rows));
        }
    }
    queueRender();
}

fn key_pressed_cb(_: ?*GtkEventControllerKey, keyval: c_uint, keycode: c_uint, state: c_uint, _: ?*anyopaque) callconv(.c) c_int {
    _ = keycode;
    g_last_input_time = getTime();
    const mods = GtkKey.translateMods(state);
    if (mods.ctrl and mods.shift) {
        if (keyval == 'c' or keyval == 'C') return 0;
        if (keyval == 'v' or keyval == 'V') return 0;
    }
    if (GtkKey.keyToSequence(keyval, mods)) |seq| {
        if (g_pty) |pty| pty.write(seq) catch {};
    }
    return 0;
}

fn im_commit_cb(_: ?*GtkIMContext, text: [*:0]const u8, _: ?*anyopaque) callconv(.c) void {
    g_last_input_time = getTime();
    if (text[0] != 0) {
        if (g_pty) |pty| {
            const str = std.mem.span(text);
            if (str.len > 0) pty.write(str) catch {};
        }
    }
}

fn mouse_pressed_cb(gesture: ?*GtkGestureClick, _: c_int, x: f64, y: f64, _: ?*anyopaque) callconv(.c) void {
    const button = gtk_gesture_single_get_current_button(@ptrCast(gesture));
    if (button != 1 or g_term == null or g_font == null) return;
    const pad_x: f32 = PADDING_X * g_dpi_scale;
    const pad_y: f32 = PADDING_Y * g_dpi_scale;
    const col = @as(i32, @intFromFloat((@as(f32, @floatCast(x)) - pad_x) / @as(f32, @floatFromInt(g_font.?.cell_width))));
    const row = @as(i32, @intFromFloat((@as(f32, @floatCast(y)) - pad_y) / @as(f32, @floatFromInt(g_font.?.cell_height))));
    if (col >= 0 and col < g_term.?.cols and row >= 0 and row < g_term.?.rows) {
        g_term.?.selection_start = .{ .col = @intCast(col), .row = @intCast(row) };
        g_term.?.selection_end = g_term.?.selection_start.?;
        g_term.?.selection_active = true;
    } else {
        g_term.?.selection_active = false;
        g_term.?.selection_start = null;
        g_term.?.selection_end = null;
    }
    queueRender();
}

fn mouse_released_cb(gesture: ?*GtkGestureClick, _: c_int, _: f64, _: f64, _: ?*anyopaque) callconv(.c) void {
    const button = gtk_gesture_single_get_current_button(@ptrCast(gesture));
    if (button != 1 or g_term == null) return;
    if (g_term.?.selection_start != null and g_term.?.selection_end != null) {
        if (g_term.?.selection_start.?.col == g_term.?.selection_end.?.col and
            g_term.?.selection_start.?.row == g_term.?.selection_end.?.row)
        {
            g_term.?.selection_active = false;
            g_term.?.selection_start = null;
            g_term.?.selection_end = null;
        }
    }
    g_term.?.selection_active = false;
}

fn mouse_motion_cb(_: ?*GtkEventControllerMotion, x: f64, y: f64, _: ?*anyopaque) callconv(.c) void {
    if (g_term == null or g_font == null or !g_term.?.selection_active) return;
    const pad_x: f32 = PADDING_X * g_dpi_scale;
    const pad_y: f32 = PADDING_Y * g_dpi_scale;
    const col = @as(i32, @intFromFloat((@as(f32, @floatCast(x)) - pad_x) / @as(f32, @floatFromInt(g_font.?.cell_width))));
    const row = @as(i32, @intFromFloat((@as(f32, @floatCast(y)) - pad_y) / @as(f32, @floatFromInt(g_font.?.cell_height))));
    const final_col = @as(u32, @intCast(std.math.clamp(col, 0, @as(i32, @intCast(g_term.?.cols - 1)))));
    const final_row = @as(u32, @intCast(std.math.clamp(row, 0, @as(i32, @intCast(g_term.?.rows - 1)))));
    g_term.?.selection_end = .{ .col = final_col, .row = final_row };
    queueRender();
}

fn ptyReadIdle(_: ?*anyopaque) callconv(.c) c_int {
    if (g_pty == null or g_term == null) return 1;
    var read_buf: [65536]u8 = undefined;
    const bytes_read = g_pty.?.read(&read_buf) catch 0;
    if (bytes_read > 0) {
        g_term.?.feed(read_buf[0..bytes_read]);
        queueRender();
    }
    return 1;
}

fn on_activate(_: ?*GtkApplication, _: ?*anyopaque) callconv(.c) void {
    g_window = @ptrCast(gtk_application_window_new(g_app.?));
    gtk_window_set_title(g_window.?, "zest");
    gtk_window_set_default_size(g_window.?, 1280, 720);

    g_gl_area = @ptrCast(gtk_gl_area_new());
    gtk_gl_area_set_auto_render(g_gl_area.?, 0);
    gtk_gl_area_set_has_stencil_buffer(g_gl_area.?, 0);
    gtk_gl_area_set_has_depth_buffer(g_gl_area.?, 0);
    gtk_gl_area_set_use_es(g_gl_area.?, 0);

    _ = signalConnect(@ptrCast(g_gl_area.?), "realize", @ptrCast(@constCast(&gl_realize_cb)), null);
    _ = signalConnect(@ptrCast(g_gl_area.?), "render", @ptrCast(@constCast(&gl_render_cb)), null);
    _ = signalConnect(@ptrCast(g_gl_area.?), "resize", @ptrCast(@constCast(&gl_resize_cb)), null);
    gtk_window_set_child(g_window.?, @ptrCast(g_gl_area.?));

    const widget = @as(*GtkWidget, @ptrCast(g_gl_area.?));
    const key_ctrl = gtk_event_controller_key_new();
    _ = signalConnect(@ptrCast(key_ctrl), "key-pressed", @ptrCast(@constCast(&key_pressed_cb)), null);
    gtk_widget_add_controller(widget, @ptrCast(key_ctrl));

    const im = gtk_im_multicontext_new();
    gtk_im_context_set_client_widget(im, widget);
    _ = signalConnect(@ptrCast(im), "commit", @ptrCast(@constCast(&im_commit_cb)), null);
    gtk_widget_set_focusable(widget, 1);
    gtk_widget_grab_focus(widget);

    const click = gtk_gesture_click_new();
    _ = signalConnect(@ptrCast(click), "pressed", @ptrCast(@constCast(&mouse_pressed_cb)), null);
    _ = signalConnect(@ptrCast(click), "released", @ptrCast(@constCast(&mouse_released_cb)), null);
    gtk_widget_add_controller(widget, @ptrCast(click));

    const motion = gtk_event_controller_motion_new();
    _ = signalConnect(@ptrCast(motion), "motion", @ptrCast(@constCast(&mouse_motion_cb)), null);
    gtk_widget_add_controller(widget, @ptrCast(motion));

    gtk_window_present(g_window.?);
    updateSizes();
}

pub fn main() !void {
    g_last_input_time = getTime();

    g_app = @ptrCast(gtk_application_new("com.zest.terminal", G_APPLICATION_FLAGS_NONE));
    if (g_app == null) return error.GtkInitFailed;
    _ = signalConnect(@ptrCast(g_app.?), "activate", @ptrCast(@constCast(&on_activate)), null);

    _ = g_application_run(g_app.?, 0, null);
}