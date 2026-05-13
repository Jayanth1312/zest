/// zest GTK4 Application Runtime — native Wayland/X11 with proper fractional scaling.
const std = @import("std");

const c_gtk = @cImport({
    @cDefine("GDK_VERSION_MIN_REQUIRED", "GDK_VERSION_4_0");
    @cDefine("GDK_VERSION_MAX_ALLOWED", "GDK_VERSION_4_0");
    @cInclude("gtk/gtk.h");
});

pub const ContentScale = struct { x: f32, y: f32 };

/// Global GTK state
pub var g_app: ?*c_gtk.GtkApplication = null;
pub var g_window: ?*c_gtk.GtkWindow = null;
pub var g_gl_area: ?*c_gtk.GtkGLArea = null;
pub var g_scale_factor: f32 = 1.0;
pub var g_fb_width: i32 = 0;
pub var g_fb_height: i32 = 0;
pub var g_win_width: i32 = 0;
pub var g_win_height: i32 = 0;

/// User-provided callbacks
pub var g_on_realize: ?*const fn () callconv(.c) void = null;
pub var g_on_render: ?*const fn (i32, i32) callconv(.c) void = null;
pub var g_on_resize: ?*const fn (i32, i32) callconv(.c) void = null;
pub var g_on_key_pressed: ?*const fn (c_uint, c_uint, c_gtk.GdkModifierType) callconv(.c) c_int = null;
pub var g_on_char: ?*const fn ([*:0]const u8) callconv(.c) void = null;
pub var g_on_mouse_pressed: ?*const fn (c_int, f64, f64) callconv(.c) void = null;
pub var g_on_mouse_released: ?*const fn (c_int, f64, f64) callconv(.c) void = null;
pub var g_on_mouse_motion: ?*const fn (f64, f64) callconv(.c) void = null;

// C callback wrappers
fn gl_realize_cb(_: ?*c_gtk.GtkGLArea, _: ?*anyopaque) callconv(.c) void {
    if (g_on_realize) |cb| cb.*();
}

fn gl_render_cb(_: ?*c_gtk.GtkGLArea, _: ?*c_gtk.cairo_t, _: ?*anyopaque) callconv(.c) c_int {
    if (g_on_render) |cb| cb.*(g_fb_width, g_fb_height);
    return 1;
}

fn gl_resize_cb(_: ?*c_gtk.GtkGLArea, w: c_int, h: c_int, _: ?*anyopaque) callconv(.c) void {
    g_fb_width = w;
    g_fb_height = h;
    updateSizes();
    if (g_on_resize) |cb| cb.*(w, h);
}

fn key_pressed_cb(_: ?*c_gtk.GtkEventControllerKey, keyval: c_uint, keycode: c_uint, state: c_gtk.GdkModifierType, _: ?*anyopaque) callconv(.c) c_int {
    if (g_on_key_pressed) |cb| return cb.*(keyval, keycode, state);
    return 0;
}

fn im_commit_cb(_: ?*c_gtk.GtkIMContext, text: [*:0]const u8, _: ?*anyopaque) callconv(.c) void {
    if (text[0] != 0 and g_on_char) |cb| cb.*(text);
}

fn mouse_pressed_cb(gesture: ?*c_gtk.GtkGestureClick, _: c_int, x: f64, y: f64, _: ?*anyopaque) callconv(.c) void {
    const button = c_gtk.gtk_gesture_single_get_current_button(@ptrCast(gesture));
    if (g_on_mouse_pressed) |cb| cb.*(@intCast(button), x * g_scale_factor, y * g_scale_factor);
}

fn mouse_released_cb(gesture: ?*c_gtk.GtkGestureClick, _: c_int, x: f64, y: f64, _: ?*anyopaque) callconv(.c) void {
    const button = c_gtk.gtk_gesture_single_get_current_button(@ptrCast(gesture));
    if (g_on_mouse_released) |cb| cb.*(@intCast(button), x * g_scale_factor, y * g_scale_factor);
}

fn mouse_motion_cb(_: ?*c_gtk.GtkEventControllerMotion, x: f64, y: f64, _: ?*anyopaque) callconv(.c) void {
    if (g_on_mouse_motion) |cb| cb.*(x * g_scale_factor, y * g_scale_factor);
}

fn updateSizes() void {
    if (g_window) |win| {
        g_win_width = c_gtk.gtk_window_get_width(win);
        g_win_height = c_gtk.gtk_window_get_height(win);
        if (g_win_width > 0) {
            g_scale_factor = @as(f32, @floatFromInt(g_fb_width)) / @as(f32, @floatFromInt(g_win_width));
        }
    }
}

fn on_activate(_: ?*c_gtk.GtkApplication, _: ?*anyopaque) callconv(.c) void {
    g_window = @ptrCast(c_gtk.gtk_application_window_new(g_app.?));
    c_gtk.gtk_window_set_title(g_window.?, "zest");
    c_gtk.gtk_window_set_default_size(g_window.?, 1280, 720);

    g_gl_area = @ptrCast(c_gtk.gtk_gl_area_new());
    c_gtk.gtk_gl_area_set_auto_render(g_gl_area.?, 0);
    c_gtk.gtk_gl_area_set_has_stencil_buffer(g_gl_area.?, 0);
    c_gtk.gtk_gl_area_set_has_depth_buffer(g_gl_area.?, 0);

    _ = c_gtk.g_signal_connect(g_gl_area.?, "realize", c_gtk.G_CALLBACK(gl_realize_cb), null);
    _ = c_gtk.g_signal_connect(g_gl_area.?, "render", c_gtk.G_CALLBACK(gl_render_cb), null);
    _ = c_gtk.g_signal_connect(g_gl_area.?, "resize", c_gtk.G_CALLBACK(gl_resize_cb), null);

    c_gtk.gtk_window_set_child(g_window.?, @ptrCast(g_gl_area.?));

    // Input setup
    const widget = @as(*c_gtk.GtkWidget, @ptrCast(g_gl_area.?));

    const key_ctrl = c_gtk.gtk_event_controller_key_new();
    _ = c_gtk.g_signal_connect(key_ctrl, "key-pressed", c_gtk.G_CALLBACK(key_pressed_cb), null);
    c_gtk.gtk_widget_add_controller(widget, @ptrCast(key_ctrl));

    const im = c_gtk.gtk_im_multicontext_new();
    c_gtk.gtk_im_context_set_client_widget(im, widget);
    _ = c_gtk.g_signal_connect(im, "commit", c_gtk.G_CALLBACK(im_commit_cb), null);
    c_gtk.gtk_widget_set_focusable(widget, 1);
    c_gtk.gtk_widget_grab_focus(widget);

    const click = c_gtk.gtk_gesture_click_new();
    _ = c_gtk.g_signal_connect(click, "pressed", c_gtk.G_CALLBACK(mouse_pressed_cb), null);
    _ = c_gtk.g_signal_connect(click, "released", c_gtk.G_CALLBACK(mouse_released_cb), null);
    c_gtk.gtk_widget_add_controller(widget, @ptrCast(click));

    const motion = c_gtk.gtk_event_controller_motion_new();
    _ = c_gtk.g_signal_connect(motion, "motion", c_gtk.G_CALLBACK(mouse_motion_cb), null);
    c_gtk.gtk_widget_add_controller(widget, @ptrCast(motion));

    c_gtk.gtk_window_present(g_window.?);
    updateSizes();
}

/// Initialize GTK4 application
pub fn init(title: [*:0]const u8, width: i32, height: i32) !void {
    _ = title; _ = width; _ = height;
    g_app = @ptrCast(c_gtk.gtk_application_new("com.zest.terminal", c_gtk.G_APPLICATION_FLAGS_NONE));
    if (g_app == null) return error.GtkInitFailed;
    _ = c_gtk.g_signal_connect(g_app.?, "activate", c_gtk.G_CALLBACK(on_activate), null);
}

/// Run the GTK main loop (blocking)
pub fn run() void {
    _ = c_gtk.g_application_run(@ptrCast(g_app.?), 0, null);
}

/// Queue a redraw
pub fn queueRender() void {
    if (g_gl_area) |area| {
        c_gtk.gtk_gl_area_queue_render(area);
    }
}

/// Get content scale factor
pub fn getContentScale() ContentScale {
    return .{ .x = g_scale_factor, .y = g_scale_factor };
}

/// Get framebuffer size
pub fn getFramebufferSize() struct { w: i32, h: i32 } {
    return .{ .w = g_fb_width, .h = g_fb_height };
}
