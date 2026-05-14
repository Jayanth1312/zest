/// zest — Terminal emulator with GTK4 native Wayland/X11 support.
const std = @import("std");
const bindings = @import("gl.zig");
const c = bindings.c;
const Font = @import("renderer/Font.zig");
const FontConfig = @import("renderer/FontConfig.zig");
const Renderer = @import("renderer/Renderer.zig");
const Terminal = @import("terminal/Terminal.zig");
const RingBuffer = @import("terminal/RingBuffer.zig");
const PaneManager = @import("layout/PaneManager.zig").PaneManager;
const KeyBindings = @import("layout/KeyBindings.zig").KeyBindings;
const GtkKey = @import("apprt/gtk/key.zig");

const INITIAL_COLS: u32 = 120;
const INITIAL_ROWS: u32 = 35;
const PADDING_X: f32 = 32.0;
const PADDING_Y: f32 = 16.0;

const GtkApplication = opaque {};
const GtkWindow = opaque {};
const GtkGLArea = opaque {};
const GtkWidget = opaque {};
const GtkEventControllerKey = opaque {};
const GtkEventControllerMotion = opaque {};
const GtkGestureClick = opaque {};
const GtkIMContext = opaque {};
const GdkClipboard = opaque {};
const cairo_t = opaque {};
const GtkEventControllerScroll = opaque {};

extern fn gtk_event_controller_scroll_new(flags: c_int) *GtkEventControllerScroll;
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
extern fn gtk_widget_get_clipboard(widget: *GtkWidget) *GdkClipboard;
extern fn gdk_clipboard_set_text(clipboard: *GdkClipboard, text: [*:0]const u8) void;
extern fn gdk_clipboard_read_text_async(clipboard: *GdkClipboard, cancellable: ?*anyopaque, callback: *const fn (*GdkClipboard, ?*anyopaque, ?*anyopaque) callconv(.c) void, user_data: ?*anyopaque) void;
extern fn gdk_clipboard_read_text_finish(clipboard: *GdkClipboard, result: ?*anyopaque, err: ?*?*anyopaque) ?[*:0]const u8;
extern fn g_idle_add(func: *const fn (?*anyopaque) callconv(.c) c_int, data: ?*anyopaque) c_uint;
extern fn clock_gettime(clk_id: c_int, tp: *std.c.timespec) c_int;

const CLOCK_MONOTONIC: c_int = 1;
const G_APPLICATION_FLAGS_NONE: c_int = 0;

var g_pane_manager: ?*PaneManager = null;
var g_key_bindings: KeyBindings = KeyBindings{};
var g_font: ?*Font.Font = null;
var g_renderer: ?*Renderer.Renderer = null;
var g_last_input_time: f64 = 0.0;
var g_dpi_scale: f32 = 1.0;
var g_initialized: bool = false;

var g_app: ?*GtkApplication = null;
var g_window: ?*GtkWindow = null;
var g_gl_area: ?*GtkGLArea = null;
var g_gl_widget: ?*GtkWidget = null;
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

fn gl_realize_cb(_: ?*GtkGLArea, _: ?*anyopaque) callconv(.c) void {
    if (g_gl_area) |area| {
        gtk_gl_area_make_current(area);
        _ = FontConfig.init();
    }

    const font_pixel_size: u32 = 32;

    const font_paths = [_][*:0]const u8{
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
        "/usr/share/fonts/truetype/ubuntu/UbuntuMono-Regular.ttf",
        "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
        "/usr/share/fonts/liberation/LiberationMono-Regular.ttf",
    };
    var font: ?Font.Font = null;
    for (&font_paths) |path| {
        font = Font.Font.init(std.heap.page_allocator, path, font_pixel_size) catch continue;
        std.debug.print("zest: using font: {s}\n", .{path});
        break;
    }
    const loaded_font = font orelse {
        std.debug.print("zest: no font found\n", .{});
        return;
    };
    const font_ptr = std.heap.page_allocator.create(Font.Font) catch return;
    font_ptr.* = loaded_font;
    g_font = font_ptr;

    var emoji_font: ?Font.Font = null;
    const emoji_path = FontConfig.findEmojiFont(std.heap.page_allocator) catch null;
    if (emoji_path) |path| {
        defer std.heap.page_allocator.free(path);
        std.debug.print("zest: using emoji font: {s}\n", .{path});
        emoji_font = Font.Font.init(std.heap.page_allocator, @ptrCast(path), font_pixel_size) catch null;
    }

    if (emoji_font == null) {
        std.debug.print("zest: no emoji font found, emojis will not render\n", .{});
    }
    var emoji_ptr: ?*Font.Font = null;
    if (emoji_font) |ef| {
        emoji_ptr = std.heap.page_allocator.create(Font.Font) catch null;
        if (emoji_ptr) |p| p.* = ef;
    }

    const renderer_ptr = std.heap.page_allocator.create(Renderer.Renderer) catch return;
    renderer_ptr.* = Renderer.Renderer.init(font_ptr, emoji_ptr) catch |err| {
        std.debug.print("zest: renderer init failed: {}\n", .{err});
        return;
    };
    g_renderer = renderer_ptr;

    const pm_ptr = std.heap.page_allocator.create(PaneManager) catch return;
    pm_ptr.* = PaneManager.init(std.heap.page_allocator, font_ptr, INITIAL_COLS, INITIAL_ROWS) catch {
        std.debug.print("zest: pane manager init failed\n", .{});
        return;
    };
    g_pane_manager = pm_ptr;

    g_initialized = true;
    _ = g_idle_add(ptyReadIdle, null);
}

fn gl_render_cb(_: ?*GtkGLArea, _: ?*cairo_t, _: ?*anyopaque) callconv(.c) c_int {
    if (!g_initialized or g_renderer == null or g_pane_manager == null) return 1;
    if (g_gl_area) |area| {
        gtk_gl_area_make_current(area);
    }

    const bg_f = @import("terminal/Cell.zig").Color.default_bg.toFloats();
    c.glClearColor(bg_f[0], bg_f[1], bg_f[2], 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);

    var panes = g_pane_manager.?.getVisiblePanes() catch return 1;
    defer panes.deinit(std.heap.page_allocator);

    const current_time = getTime();
    const panes_count = panes.items.len;

    for (panes.items) |pane| {
        const offset_x = pane.x + g_pane_manager.?.inner_padding;
        const offset_y = g_pane_manager.?.computeVerticalOffset(pane);
        g_renderer.?.render(
            &pane.terminal.grid,
            g_fb_width, g_fb_height,
            offset_x, offset_y,
            pane.terminal.cursor_col, pane.terminal.cursor_row,
            current_time, g_last_input_time,
            pane.terminal.selection_start, pane.terminal.selection_end,
            pane.focused,
        );
    }

    if (panes_count > 1) {
        var split_lines = g_pane_manager.?.getSplitLines() catch return 1;
        defer split_lines.deinit(std.heap.page_allocator);

        const border_color = @import("terminal/Cell.zig").Color.base03;
        c.glEnable(c.GL_SCISSOR_TEST);
        for (split_lines.items) |line| {
            const lx: i32 = @intFromFloat(@round(line.x));
            const ly: i32 = @intFromFloat(@round(line.y));
            const lw: i32 = @intFromFloat(@round(line.width));
            const lh: i32 = @intFromFloat(@round(line.height));
            c.glScissor(lx, g_fb_height - ly - lh, lw, lh);
            c.glClearColor(border_color.toFloats()[0], border_color.toFloats()[1], border_color.toFloats()[2], 1.0);
            c.glClear(c.GL_COLOR_BUFFER_BIT);
        }
        c.glDisable(c.GL_SCISSOR_TEST);
    }

    c.glViewport(0, 0, g_fb_width, g_fb_height);

    return 1;
}

fn gl_resize_cb(_: ?*GtkGLArea, w: c_int, h: c_int, _: ?*anyopaque) callconv(.c) void {
    g_fb_width = w;
    g_fb_height = h;
    updateSizes();
    if (g_pane_manager != null) {
        g_pane_manager.?.handleResize(w, h) catch {};
    }
    queueRender();
}

fn key_pressed_cb(_: ?*GtkEventControllerKey, keyval: c_uint, keycode: c_uint, state: c_uint, _: ?*anyopaque) callconv(.c) c_int {
    _ = keycode;
    g_last_input_time = getTime();

    const mods = GtkKey.translateMods(state);
    const ctrl = mods.ctrl;
    const shift = mods.shift;
    const alt = mods.alt;

    const direct_cmd = KeyBindings.handleDirectShortcut(keyval, ctrl, shift, alt);
    if (direct_cmd != .none and g_pane_manager != null) {
        g_pane_manager.?.executeCommand(direct_cmd) catch {};
        queueRender();
        return 1;
    }

    if (ctrl and shift) {
        if (keyval == 'c' or keyval == 'C') {
            if (g_pane_manager != null) {
                const focused = g_pane_manager.?.getFocusedPane();
                if (focused) |pane| {
                    if (pane.terminal.selection_start != null and pane.terminal.selection_end != null) {
                        const text = pane.terminal.getSelectedText(std.heap.page_allocator) catch null;
                        if (text) |t| {
                            defer std.heap.page_allocator.free(t);
                            if (g_gl_widget) |widget| {
                                const clipboard = gtk_widget_get_clipboard(@ptrCast(widget));
                                gdk_clipboard_set_text(clipboard, @ptrCast(t));
                            }
                        }
                    }
                }
            }
            return 1;
        }
        if (keyval == 'v' or keyval == 'V') {
            if (g_gl_widget) |widget| {
                const clipboard = gtk_widget_get_clipboard(@ptrCast(widget));
                gdk_clipboard_read_text_async(clipboard, null, clipboardReadCb, null);
            }
            return 1;
        }
    }

    if (GtkKey.keyToSequence(keyval, mods)) |seq| {
        if (g_pane_manager != null) {
            const focused = g_pane_manager.?.getFocusedPane();
            if (focused) |pane| {
                pane.write(seq) catch {};
            }
        }
        return 1;
    }

    if (!ctrl and !alt) {
        if (keyval >= 0x20 and keyval < 0x7F) {
            if (g_pane_manager != null) {
                const focused = g_pane_manager.?.getFocusedPane();
                if (focused) |pane| {
                    const ch: u8 = @intCast(keyval);
                    pane.write(&.{ch}) catch {};
                }
            }
            return 1;
        }
        if (keyval >= 0x100 and keyval < 0xFF00) {
            if (g_pane_manager != null) {
                const focused = g_pane_manager.?.getFocusedPane();
                if (focused) |pane| {
                    var buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(@intCast(keyval), &buf) catch return 0;
                    pane.write(buf[0..len]) catch {};
                }
            }
            return 1;
        }
    }

    return 0;
}

fn clipboardReadCb(clipboard: ?*GdkClipboard, result: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    if (clipboard == null or g_pane_manager == null) return;
    const text = gdk_clipboard_read_text_finish(clipboard.?, result, null);
    if (text) |t| {
        const focused = g_pane_manager.?.getFocusedPane();
        if (focused) |pane| {
            const str = std.mem.span(t);
            if (str.len > 0) pane.write(str) catch {};
        }
    }
}

fn im_commit_cb(_: ?*GtkIMContext, text: [*:0]const u8, _: ?*anyopaque) callconv(.c) void {
    g_last_input_time = getTime();
    if (text[0] != 0) {
        if (g_pane_manager != null) {
            const focused = g_pane_manager.?.getFocusedPane();
            if (focused) |pane| {
                const str = std.mem.span(text);
                if (str.len > 0) pane.write(str) catch {};
            }
        }
    }
}

fn mouse_pressed_cb(gesture: ?*GtkGestureClick, _: c_int, x: f64, y: f64, _: ?*anyopaque) callconv(.c) void {
    const button = gtk_gesture_single_get_current_button(@ptrCast(gesture));
    if (button != 1 or g_pane_manager == null) return;

    const fb_x = @as(f32, @floatCast(x)) * g_scale_factor;
    const fb_y = @as(f32, @floatCast(y)) * g_scale_factor;
    const inner_pad = g_pane_manager.?.inner_padding;

    const pane = g_pane_manager.?.findPaneAt(fb_x, fb_y);
    if (pane) |p| {
        const focused = g_pane_manager.?.getFocusedPane();
        if (focused) |f| f.focused = false;
        p.focused = true;

        const offset_x = p.x + inner_pad;
        const offset_y = g_pane_manager.?.computeVerticalOffset(p);
        const col = @as(i32, @intFromFloat((fb_x - offset_x) / @as(f32, @floatFromInt(g_font.?.cell_width))));
        const row = @as(i32, @intFromFloat((fb_y - offset_y) / @as(f32, @floatFromInt(g_font.?.cell_height))));
        if (col >= 0 and col < p.cols and row >= 0 and row < p.rows) {
            p.terminal.selection_start = .{ .col = @intCast(col), .row = @intCast(row) };
            p.terminal.selection_end = p.terminal.selection_start.?;
            p.terminal.selection_active = true;
        } else {
            p.terminal.selection_active = false;
            p.terminal.selection_start = null;
            p.terminal.selection_end = null;
        }
    }
    queueRender();
}

fn mouse_released_cb(gesture: ?*GtkGestureClick, _: c_int, _: f64, _: f64, _: ?*anyopaque) callconv(.c) void {
    const button = gtk_gesture_single_get_current_button(@ptrCast(gesture));
    if (button != 1 or g_pane_manager == null) return;

    const focused = g_pane_manager.?.getFocusedPane();
    if (focused) |p| {
        if (p.terminal.selection_start != null and p.terminal.selection_end != null) {
            if (p.terminal.selection_start.?.col == p.terminal.selection_end.?.col and
                p.terminal.selection_start.?.row == p.terminal.selection_end.?.row)
            {
                p.terminal.selection_active = false;
                p.terminal.selection_start = null;
                p.terminal.selection_end = null;
            }
        }
        p.terminal.selection_active = false;
    }
}

fn mouse_motion_cb(_: ?*GtkEventControllerMotion, x: f64, y: f64, _: ?*anyopaque) callconv(.c) void {
    if (g_pane_manager == null or g_font == null) return;
    const inner_pad = g_pane_manager.?.inner_padding;
    const focused = g_pane_manager.?.getFocusedPane();
    if (focused) |p| {
        if (!p.terminal.selection_active) return;
        const fb_x = @as(f32, @floatCast(x)) * g_scale_factor;
        const fb_y = @as(f32, @floatCast(y)) * g_scale_factor;
        const offset_x = p.x + inner_pad;
        const offset_y = g_pane_manager.?.computeVerticalOffset(p);
        const col = @as(i32, @intFromFloat((fb_x - offset_x) / @as(f32, @floatFromInt(g_font.?.cell_width))));
        const row = @as(i32, @intFromFloat((fb_y - offset_y) / @as(f32, @floatFromInt(g_font.?.cell_height))));
        const final_col = @as(u32, @intCast(std.math.clamp(col, 0, @as(i32, @intCast(p.cols - 1)))));
        const final_row = @as(u32, @intCast(std.math.clamp(row, 0, @as(i32, @intCast(p.rows - 1)))));
        p.terminal.selection_end = .{ .col = final_col, .row = final_row };
        queueRender();
    }
}

fn scroll_cb(_: ?*GtkEventControllerScroll, _: f64, dy: f64, _: ?*anyopaque) callconv(.c) c_int {
    if (g_pane_manager == null) return 0;
    
    const focused = g_pane_manager.?.getFocusedPane();
    if (focused) |pane| {
        // If we are in a TUI app (like opencode), map scrolling to Up/Down arrows
        if (pane.terminal.using_alt_screen) {
            if (dy > 0.0) {
                // Scrolled down
                pane.write("\x1b[B") catch {}; 
            } else if (dy < 0.0) {
                // Scrolled up
                pane.write("\x1b[A") catch {}; 
            }
            return 1; // Event handled
        }
    }
    return 0;
}

fn ptyReadIdle(_: ?*anyopaque) callconv(.c) c_int {
    if (g_pane_manager == null) return 1;

    var panes = g_pane_manager.?.getVisiblePanes() catch return 1;
    defer panes.deinit(std.heap.page_allocator);

    var read_buf: [65536]u8 = undefined;
    for (panes.items) |pane| {
        const bytes_read = pane.read(&read_buf) catch 0;
        if (bytes_read > 0) {
            pane.feed(read_buf[0..bytes_read]);
        }
    }

    const current_time = getTime();
    g_pane_manager.?.tick(current_time);

    queueRender();
    return 1;
}

fn on_activate(_: ?*GtkApplication, _: ?*anyopaque) callconv(.c) void {
    g_window = @ptrCast(gtk_application_window_new(g_app.?));
    gtk_window_set_title(g_window.?, "zest");
    gtk_window_set_default_size(g_window.?, 1280, 720);

    g_gl_area = @ptrCast(gtk_gl_area_new());
    g_gl_widget = @ptrCast(g_gl_area.?);
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

    const scroll = gtk_event_controller_scroll_new(1);
    _ = signalConnect(@ptrCast(scroll), "scroll", @ptrCast(@constCast(&scroll_cb)), null);
    gtk_widget_add_controller(widget, @ptrCast(scroll));
}

pub fn main() !void {
    g_last_input_time = getTime();

    g_app = @ptrCast(gtk_application_new("com.zest.terminal", G_APPLICATION_FLAGS_NONE));
    if (g_app == null) return error.GtkInitFailed;
    _ = signalConnect(@ptrCast(g_app.?), "activate", @ptrCast(@constCast(&on_activate)), null);

    _ = g_application_run(g_app.?, 0, null);
}
