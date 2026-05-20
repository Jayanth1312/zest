/// zest — Terminal emulator with GTK4 native Wayland/X11 support.
const std = @import("std");
const bindings = @import("gl.zig");
const c = bindings.c;
const Font = @import("renderer/Font.zig");
const FontConfig = @import("renderer/FontConfig.zig");
const Renderer = @import("renderer/Renderer.zig");
const Grid = @import("terminal/Grid.zig").Grid;
const Terminal = @import("terminal/Terminal.zig");
const PaneManager = @import("layout/PaneManager.zig").PaneManager;
const Pane = @import("layout/Pane.zig").Pane;
const KeyBindings = @import("layout/KeyBindings.zig").KeyBindings;
const GtkKey = @import("apprt/gtk/key.zig");
const FileExplorer = @import("fileexplorer/FileExplorer.zig").FileExplorer;
const Config = @import("config/Config.zig").Config;
const SettingsUI = @import("settings/SettingsUI.zig");
const ThemePreviewUI = @import("settings/ThemePreviewUI.zig");
const ConfigWriter = @import("config/ConfigWriter.zig");
const ConfigParser = @import("config/ConfigParser.zig");

const INITIAL_COLS: u32 = 120;
const INITIAL_ROWS: u32 = 35;
const PADDING_X: f32 = 32.0;
const PADDING_Y: f32 = 16.0;
const TAB_BAR_HEIGHT: c_int = 36;

const GtkApplication = opaque {};
const GtkWindow = opaque {};
const GtkGLArea = opaque {};
const GtkWidget = opaque {};
const GtkEventControllerKey = opaque {};
const GtkEventControllerMotion = opaque {};
const GtkGestureClick = opaque {};
const GtkIMContext = opaque {};
const GdkClipboard = opaque {};
const GdkDisplay = opaque {};
const cairo_t = opaque {};
const GtkEventControllerScroll = opaque {};

extern fn gtk_event_controller_scroll_new(flags: c_int) *GtkEventControllerScroll;
extern fn gtk_application_new(id: [*:0]const u8, flags: c_int) *GtkApplication;
extern fn g_signal_connect_data(instance: *anyopaque, signal: [*:0]const u8, handler: ?*anyopaque, data: ?*anyopaque, destroy_data: ?*anyopaque, flags: c_uint) c_ulong;
extern fn gtk_button_get_child(button: *GtkWidget) *GtkWidget;
extern fn gtk_label_set_ellipsize(label: *GtkWidget, mode: c_int) void;
extern fn gtk_label_set_width_chars(label: *GtkWidget, chars: c_int) void;
extern fn gtk_label_set_max_width_chars(label: *GtkWidget, n_chars: c_int) void;
const PANGO_ELLIPSIZE_END: c_int = 3;

fn signalConnect(instance: *anyopaque, signal: [*:0]const u8, handler: *anyopaque, data: ?*anyopaque) c_ulong {
    return g_signal_connect_data(instance, signal, handler, data, null, 0);
}
extern fn g_application_run(app: *GtkApplication, argc: c_int, argv: ?*[*:0]u8) c_int;
extern fn gtk_application_window_new(app: *GtkApplication) *GtkWindow;
extern fn gtk_window_set_title(win: *GtkWindow, title: [*:0]const u8) void;
extern fn gtk_window_set_default_size(win: *GtkWindow, w: c_int, h: c_int) void;
extern fn gtk_window_set_decorated(win: *GtkWindow, decorated: c_int) void;
extern fn gtk_window_set_titlebar(win: *GtkWindow, titlebar: *GtkWidget) void;
extern fn gtk_window_set_child(win: *GtkWindow, child: *GtkWidget) void;
extern fn gtk_window_present(win: *GtkWindow) void;
extern fn gtk_window_close(win: *GtkWindow) void;
extern fn gtk_window_minimize(win: *GtkWindow) void;
extern fn gtk_window_maximize(win: *GtkWindow) void;
extern fn gtk_window_unmaximize(win: *GtkWindow) void;
extern fn gtk_window_is_maximized(win: *GtkWindow) c_int;
extern fn gtk_widget_get_width(widget: *GtkWidget) c_int;
extern fn gtk_widget_get_height(widget: *GtkWidget) c_int;
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

// Overlay and layout
extern fn gtk_overlay_new() *GtkWidget;
extern fn gtk_overlay_set_child(overlay: *GtkWidget, child: *GtkWidget) void;
extern fn gtk_overlay_add_overlay(overlay: *GtkWidget, widget: *GtkWidget) void;
extern fn gtk_box_new(orientation: c_int, spacing: c_int) *GtkWidget;
extern fn gtk_box_append(box: *GtkWidget, child: *GtkWidget) void;
extern fn gtk_box_remove(box: *GtkWidget, child: *GtkWidget) void;
extern fn gtk_widget_set_vexpand(widget: *GtkWidget, expand: c_int) void;
extern fn gtk_widget_set_hexpand(widget: *GtkWidget, expand: c_int) void;
extern fn gtk_widget_set_size_request(widget: *GtkWidget, width: c_int, height: c_int) void;
extern fn gtk_scrolled_window_new(hscroll: ?*anyopaque, vscroll: ?*anyopaque) *GtkWidget;
extern fn gtk_scrolled_window_set_policy(scrolled: *GtkWidget, hpolicy: c_int, vpolicy: c_int) void;
extern fn gtk_scrolled_window_set_child(scrolled: *GtkWidget, child: *GtkWidget) void;
extern fn gtk_widget_set_overflow(widget: *GtkWidget, overflow: c_int) void;

// Label
extern fn gtk_label_new(str: [*:0]const u8) *GtkWidget;
extern fn gtk_label_set_text(label: *GtkWidget, str: [*:0]const u8) void;
extern fn gtk_widget_set_halign(widget: *GtkWidget, alignment: c_int) void;
extern fn gtk_widget_set_valign(widget: *GtkWidget, alignment: c_int) void;
extern fn gtk_widget_set_margin_bottom(widget: *GtkWidget, margin: c_int) void;
extern fn gtk_widget_set_margin_end(widget: *GtkWidget, margin: c_int) void;
extern fn gtk_widget_set_margin_top(widget: *GtkWidget, margin: c_int) void;
extern fn gtk_widget_set_margin_start(widget: *GtkWidget, margin: c_int) void;

// Button
extern fn gtk_button_new() *GtkWidget;
extern fn gtk_button_new_with_label(label: [*:0]const u8) *GtkWidget;
extern fn gtk_button_set_label(button: *GtkWidget, label: [*:0]const u8) void;
extern fn gtk_widget_add_css_class(widget: *GtkWidget, css_class: [*:0]const u8) void;
extern fn gtk_widget_remove_css_class(widget: *GtkWidget, css_class: [*:0]const u8) void;

// CSS provider
extern fn gtk_css_provider_new() *anyopaque;
extern fn gtk_css_provider_load_from_data(provider: *anyopaque, data: [*:0]const u8, length: isize) void;
extern fn gdk_display_get_default() ?*GdkDisplay;
extern fn gtk_style_context_add_provider_for_display(display: *GdkDisplay, provider: *anyopaque, priority: c_uint) void;

// C library for readlink
extern fn readlink(pathname: [*:0]const u8, buf: [*]u8, bufsiz: usize) isize;

// Timeout
extern fn g_timeout_add(interval: c_uint, func: *const fn (?*anyopaque) callconv(.c) c_int, data: ?*anyopaque) c_uint;

// Drawing area + Cairo (for block clock)
extern fn gtk_drawing_area_new() *GtkWidget;
extern fn gtk_drawing_area_set_draw_func(
    area: *GtkWidget,
    func: ?*const fn (*GtkWidget, *cairo_t, c_int, c_int, ?*anyopaque) callconv(.c) void,
    user_data: ?*anyopaque,
    destroy: ?*anyopaque,
) void;
extern fn gtk_widget_queue_draw(widget: *GtkWidget) void;
extern fn gtk_box_set_homogeneous(box: *GtkWidget, homogeneous: c_int) void;

// Cairo primitives
extern fn cairo_set_source_rgb(cr: *cairo_t, r: f64, g: f64, b: f64) void;
extern fn cairo_set_source_rgba(cr: *cairo_t, r: f64, g: f64, b: f64, a: f64) void;
extern fn cairo_rectangle(cr: *cairo_t, x: f64, y: f64, w: f64, h: f64) void;
extern fn cairo_fill(cr: *cairo_t) void;
extern fn cairo_arc(cr: *cairo_t, xc: f64, yc: f64, radius: f64, angle1: f64, angle2: f64) void;

const CTime = extern struct {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
};
extern fn localtime_r(timep: *const c_long, result: *CTime) ?*CTime;

const CLOCK_MONOTONIC: c_int = 1;
const CLOCK_REALTIME: c_int = 0;
const G_APPLICATION_FLAGS_NONE: c_int = 0;
const GTK_ALIGN_END: c_int = 2;
const GTK_ORIENTATION_VERTICAL: c_int = 1;
const GTK_ORIENTATION_HORIZONTAL: c_int = 0;
const GTK_POLICY_AUTOMATIC: c_int = 1;
const GTK_POLICY_NEVER: c_int = 2;
const GTK_STYLE_PROVIDER_PRIORITY_APPLICATION: c_uint = 600;

// Black Metal Immortal theme colors
const THEME_BG = "#000000";
const THEME_BG_LIGHT = "#121212";
const THEME_BG_MID = "#1a1a1a";
const THEME_BORDER = "#333333";
const THEME_FG = "#c1c1c1";
const THEME_FG_DIM = "#666666";
const THEME_ACCENT = "#5f8787";

const TAB_CSS =
    \\box.tab-bar { background-color: #0d0d0d; padding: 0; min-height: 28px; }
    \\box.window-controls { padding: 0 8px; }
    \\button.window-btn-close, button.window-btn-minimize, button.window-btn-maximize {
    \\    background-color: transparent;
    \\    border: none;
    \\    border-radius: 50%;
    \\    min-width: 12px;
    \\    min-height: 12px;
    \\    padding: 0;
    \\    margin: 0 3px;
    \\    box-shadow: none;
    \\}
    \\button.window-btn-close { background-color: #ff5f56; }
    \\button.window-btn-minimize { background-color: #ffbd2e; }
    \\button.window-btn-maximize { background-color: #27c93f; }
    \\button.window-btn-close:hover { background-color: #ff3f34; }
    \\button.window-btn-minimize:hover { background-color: #ff9f1a; }
    \\button.window-btn-maximize:hover { background-color: #1a9c33; }
    \\box.tab-container { background-color: #0d0d0d; }
    \\scrolledwindow.tab-scroll { background-color: #0d0d0d; border: none; }
    \\scrolledwindow.tab-scroll undershoot, scrolledwindow.tab-scroll overshoot { border: none; box-shadow: none; }
    \\button.tab-button { background-color: #1a1a1a; color: #999999; border: none; border-radius: 0; padding: 4px 12px; font-size: 11px; min-height: 28px; transition: all 150ms ease; }
    \\button.tab-button:hover { background-color: #252525; color: #c1c1c1; }
    \\button.active-tab { background-color: #000000; color: #e0e0e0; border-bottom: 2px solid #5f8787; }
    \\box.right-section {
    \\    background-image: linear-gradient(to right, rgba(95, 135, 135, 0) 0%, rgba(95, 135, 135, 1) 30%);
    \\    padding: 0 6px 0 32px;
    \\}
    \\label.clock-label {
    \\    color: #000000;
    \\    background-color: transparent;
    \\    font-size: 15px;
    \\    font-weight: 700;
    \\    font-family: monospace;
    \\    padding: 2px 14px;
    \\    border-radius: 2px;
    \\    letter-spacing: 1px;
    \\}
    \\button.history-button {
    \\    background-color: transparent;
    \\    color: #000000;
    \\    border: none;
    \\    border-radius: 0;
    \\    padding: 2px 8px;
    \\    font-size: 16px;
    \\    font-weight: 700;
    \\    min-height: 28px;
    \\}
    \\button.history-button:hover {
    \\    background-color: rgba(0, 0, 0, 0.15);
    \\    color: #000000;
    \\}
    \\button.history-button.active {
    \\    background-color: rgba(95, 135, 135, 0.3);
    \\    color: #000000;
    \\}
    \\button.zoom-label {
    \\    background-color: transparent;
    \\    color: #000000;
    \\    border: none;
    \\    border-radius: 0;
    \\    padding: 2px 6px;
    \\    font-size: 12px;
    \\    font-weight: 700;
    \\    font-family: monospace;
    \\    min-height: 28px;
    \\}
    \\button.zoom-label:hover {
    \\    background-color: rgba(0, 0, 0, 0.15);
    \\    color: #000000;
    \\}
    \\button.gear-button {
    \\    background-color: transparent;
    \\    color: #000000;
    \\    border: none;
    \\    border-radius: 0;
    \\    padding: 2px 8px;
    \\    font-size: 16px;
    \\    min-height: 28px;
    \\    min-width: 28px;
    \\}
    \\button.gear-button:hover {
    \\    background-color: rgba(0, 0, 0, 0.15);
    \\    color: #000000;
    \\}
;

const Tab = struct {
    pane_manager: *PaneManager,
    button: ?*GtkWidget = null,
    idx_ptr: ?*usize = null,
    title_buf: [256]u8 = undefined,
    title_len: usize = 0,
    history_visible: bool = false,
    history_scroll: u32 = 0,
    history_selected_idx: usize = 0,
    history_search_buf: [128]u8 = undefined,
    history_search_len: usize = 0,

    fn setTitleFmt(self: *Tab, comptime fmt: []const u8, args: anytype) void {
        const result = std.fmt.bufPrint(&self.title_buf, fmt, args) catch "Tab";
        self.title_len = @min(result.len, self.title_buf.len - 1);
        self.title_buf[self.title_len] = 0;
    }

    fn getTitle(self: *Tab) [:0]const u8 {
        return self.title_buf[0..self.title_len :0];
    }

    fn historySelectUp(self: *Tab, history_len: usize) void {
        if (history_len == 0) return;
        if (self.history_selected_idx == 0) {
            self.history_selected_idx = history_len - 1;
        } else {
            self.history_selected_idx -= 1;
        }
        self.history_scroll = 0;
    }

    fn historySelectDown(self: *Tab, history_len: usize) void {
        if (history_len == 0) return;
        if (self.history_selected_idx >= history_len - 1) {
            self.history_selected_idx = 0;
        } else {
            self.history_selected_idx += 1;
        }
        self.history_scroll = 0;
    }

    fn historyAddSearchChar(self: *Tab, ch: u8) void {
        if (self.history_search_len < self.history_search_buf.len - 1) {
            self.history_search_buf[self.history_search_len] = ch;
            self.history_search_len += 1;
        }
        self.history_selected_idx = 0;
        self.history_scroll = 0;
    }

    fn historyDeleteSearchChar(self: *Tab) void {
        if (self.history_search_len > 0) {
            self.history_search_len -= 1;
        }
        self.history_selected_idx = 0;
        self.history_scroll = 0;
    }

    fn historyClearSearch(self: *Tab) void {
        self.history_search_len = 0;
        self.history_selected_idx = 0;
        self.history_scroll = 0;
    }

    fn historyGetSearch(self: *Tab) []const u8 {
        return self.history_search_buf[0..self.history_search_len];
    }
};

var g_config: ?Config = null;
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

// Tab and clock state
var g_tabs: std.ArrayListUnmanaged(Tab) = .empty;
var g_active_tab: usize = 0;
var g_clock_label: ?*GtkWidget = null;
var g_history_button: ?*GtkWidget = null;
var g_zoom_label: ?*GtkWidget = null;
var g_gear_button: ?*GtkWidget = null;
var g_font_pixel_size: u32 = 32;
fn getDefaultFontSize() u32 {
    return if (g_config) |cfg| cfg.settings.font_size else 32;
}

fn getZoomLevel() u32 {
    return if (g_config) |cfg| cfg.settings.zoom_level else 100;
}

fn getActualFontSize() u32 {
    return @max(8, @min(96, getDefaultFontSize() * getZoomLevel() / 100));
}
var g_tab_bar: ?*GtkWidget = null;
var g_tab_container: ?*GtkWidget = null;
var g_right_section: ?*GtkWidget = null;
var g_main_box: ?*GtkWidget = null;
var g_overlay: ?*GtkWidget = null;
var g_tab_counter: u32 = 0;

// Reusable pane list to avoid per-frame allocation
var g_pane_list: std.ArrayListUnmanaged(*Pane) = .empty;

fn getTime() f64 {
    var ts: std.c.timespec = undefined;
    _ = clock_gettime(CLOCK_MONOTONIC, &ts);
    return @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) / 1_000_000_000.0;
}

fn updateSizes() void {
    if (g_window) |win| {
        g_win_width = gtk_widget_get_width(@ptrCast(win));
        g_win_height = gtk_widget_get_height(@ptrCast(win));
        if (g_win_width > 0 and g_fb_width > 0) {
            g_scale_factor = @as(f32, @floatFromInt(g_fb_width)) / @as(f32, @floatFromInt(g_win_width));
        }
    }
}

fn queueRender() void {
    if (g_gl_area) |area| gtk_gl_area_queue_render(area);
}

fn updateZoomLabel() void {
    if (g_zoom_label) |label| {
        const zoom = getZoomLevel();
        var buf: [16:0]u8 = undefined;
        const len = std.fmt.bufPrint(&buf, "{d}%", .{zoom}) catch return;
        buf[len.len] = 0;
        gtk_button_set_label(@ptrCast(label), &buf);
    }
}

fn changeZoomLevel(delta: i32) void {
    if (g_font == null or g_renderer == null) return;
    if (g_config) |*cfg| {
        const step: i32 = @intCast(cfg.settings.zoom_step);
        const new_zoom = @max(50, @min(300, @as(i32, @intCast(cfg.settings.zoom_level)) + delta * step));
        if (new_zoom == @as(i32, @intCast(cfg.settings.zoom_level))) return;
        cfg.settings.zoom_level = @intCast(new_zoom);
    }
    g_font_pixel_size = getActualFontSize();
    g_font.?.setPixelSize(g_font_pixel_size) catch return;
    if (g_renderer.?.fallback_font) |emoji| {
        emoji.setPixelSize(g_font_pixel_size) catch {};
    }
    g_renderer.?.reloadFont() catch return;
    for (g_tabs.items) |*tab| {
        tab.pane_manager.handleResize(g_fb_width, g_fb_height) catch {};
    }
    updateZoomLabel();
    queueRender();
}

fn getTabCwd(tab: *Tab) ?[:0]const u8 {
    var panes = tab.pane_manager.getVisiblePanes() catch return null;
    defer panes.deinit(std.heap.page_allocator);
    if (panes.items.len == 0) return null;

    const pane = panes.items[0];
    const pid = pane.pty.pid;

    var pid_path_buf: [64]u8 = undefined;
    const pid_path_len = std.fmt.bufPrint(&pid_path_buf, "/proc/{d}/cwd", .{pid}) catch return null;
    pid_path_buf[pid_path_len.len] = 0;

    var cwd_buf: [4096]u8 = undefined;
    const len = readlink(@ptrCast(&pid_path_buf[0]), &cwd_buf, cwd_buf.len);
    if (len <= 0) return null;

    const cwd = cwd_buf[0..@as(usize, @intCast(len))];
    if (cwd.len == 0) return null;

    const home = std.c.getenv("HOME") orelse "/home/";
    const home_str = std.mem.span(home);
    if (std.mem.startsWith(u8, cwd, home_str)) {
        // Drop the - 1 to properly strip the entire home directory
        const after_home = cwd[home_str.len..];
        // This will result in standard Unix format: ~/Projects/zest
        tab.setTitleFmt("~{s}", .{after_home});
    } else {
        const last_sep = std.mem.lastIndexOfScalar(u8, cwd, '/') orelse 0;
        const dir_name = if (last_sep == 0 and cwd.len > 0) cwd else cwd[last_sep + 1 ..];
        tab.setTitleFmt("{s}", .{dir_name});
    }
    return tab.getTitle();
}

fn updateTabButtonLabel(tab: *Tab) void {
    const cwd = getTabCwd(tab);
    const label = cwd orelse tab.getTitle();
    if (tab.button) |btn| {
        gtk_button_set_label(@ptrCast(btn), label.ptr);
    }
}

fn gl_realize_cb(_: ?*GtkGLArea, _: ?*anyopaque) callconv(.c) void {
    if (g_gl_area) |area| {
        gtk_gl_area_make_current(area);
        _ = FontConfig.init();
    }

    if (g_initialized) return;
    g_font_pixel_size = getActualFontSize();
    updateZoomLabel();

    const font_paths = [_][*:0]const u8{
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
        "/usr/share/fonts/truetype/ubuntu/UbuntuMono-Regular.ttf",
        "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
        "/usr/share/fonts/liberation/LiberationMono-Regular.ttf",
    };
    var font: ?Font.Font = null;
    for (&font_paths) |path| {
        font = Font.Font.init(std.heap.page_allocator, path, g_font_pixel_size) catch continue;
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
        emoji_font = Font.Font.init(std.heap.page_allocator, @ptrCast(path), g_font_pixel_size) catch null;
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

    g_initialized = true;

    // Create the first tab
    createTab();

    const pty_ms = if (g_config) |cfg| cfg.settings.pty_read_interval_ms else 16;
    _ = g_timeout_add(pty_ms, ptyReadIdle, null);
}

fn renderHistoryPanel(terminal: *Terminal.Terminal, history: *const std.ArrayListUnmanaged([]u8), pane_cols: u32, pane_rows: u32, tab: *Tab) void {
    const Cell = @import("terminal/Cell.zig");

    const bg = Cell.Color.base01;
    const fg = Cell.Color.base05;
    const header_bg = Cell.Color.base08;
    const header_fg = Cell.Color.base00;
    const dim_fg = Cell.Color.base04;
    const selected_bg = Cell.Color.base08;
    const selected_fg = Cell.Color.base00;
    const search_bg = Cell.Color.base03;
    const search_fg = Cell.Color.base05;

    const header_row: u32 = 0;
    const search_row: u32 = 1;
    const list_start_row: u32 = 2;
    const footer_row = pane_rows - 1;
    const visible_rows = pane_rows - 3;

    for (0..pane_rows) |row| {
        for (0..pane_cols) |col| {
            terminal.grid.setCellAt(@intCast(col), @intCast(row), .{
                .char = ' ',
                .fg = fg,
                .bg = bg,
            });
        }
    }

    const header_text = " COMMAND HISTORY ";
    const header_start = (pane_cols - header_text.len) / 2;
    for (0..header_text.len) |i| {
        const col = header_start + i;
        if (col < pane_cols) {
            terminal.grid.setCellAt(@intCast(col), header_row, .{
                .char = @as(u21, header_text[i]),
                .fg = header_fg,
                .bg = header_bg,
                .attrs = .{ .bold = true },
            });
        }
    }

    const search_prompt = "search: ";
    _ = search_prompt.len;
    var col: u32 = 0;
    for (search_prompt) |ch| {
        if (col < pane_cols) {
            terminal.grid.setCellAt(col, search_row, .{
                .char = @as(u21, ch),
                .fg = dim_fg,
                .bg = search_bg,
            });
            col += 1;
        }
    }
    for (0..tab.history_search_len) |i| {
        if (col < pane_cols) {
            terminal.grid.setCellAt(col, search_row, .{
                .char = @as(u21, tab.history_search_buf[i]),
                .fg = search_fg,
                .bg = search_bg,
            });
            col += 1;
        }
    }
    if (col < pane_cols) {
        terminal.grid.setCellAt(col, search_row, .{
            .char = '_',
            .fg = search_fg,
            .bg = search_bg,
        });
    }

    const search_text = tab.historyGetSearch();
    var filtered_indices: [1024]usize = undefined;
    var filtered_count: usize = 0;
    for (0..history.items.len) |idx| {
        if (filtered_count >= 1024) break;
        if (search_text.len == 0 or std.mem.indexOf(u8, history.items[idx], search_text) != null) {
            filtered_indices[filtered_count] = idx;
            filtered_count += 1;
        }
    }

    if (filtered_count == 0) {
        const empty_text = "(no commands found)";
        const empty_start = if (pane_cols > empty_text.len) (pane_cols - empty_text.len) / 2 else 0;
        for (0..empty_text.len) |i| {
            const cx = empty_start + i;
            if (cx < pane_cols) {
                terminal.grid.setCellAt(@intCast(cx), list_start_row, .{
                    .char = @as(u21, empty_text[i]),
                    .fg = dim_fg,
                    .bg = bg,
                });
            }
        }
    } else {
        if (tab.history_selected_idx >= filtered_count) {
            tab.history_selected_idx = filtered_count - 1;
        }

        const max_scroll: u32 = if (filtered_count > visible_rows) @intCast(filtered_count - visible_rows) else 0;
        if (tab.history_scroll > max_scroll) {
            tab.history_scroll = max_scroll;
        }
        const scroll = tab.history_scroll;

        var display_row: u32 = 0;
        var fi: usize = scroll;
        while (fi < filtered_count and display_row < visible_rows) : ({
            fi += 1;
            display_row += 1;
        }) {
            const orig_idx = filtered_indices[fi];
            const cmd = history.items[orig_idx];
            const is_selected = fi == tab.history_selected_idx;
            const entry_fg = if (is_selected) selected_fg else fg;
            const entry_bg = if (is_selected) selected_bg else bg;

            var num_buf: [4]u8 = undefined;
            const num_str = std.fmt.bufPrint(&num_buf, "{d:>3}", .{orig_idx + 1}) catch "   ";

            var c2: u32 = 0;
            for (num_str) |ch| {
                if (c2 < pane_cols) {
                    terminal.grid.setCellAt(c2, list_start_row + display_row, .{
                        .char = @as(u21, ch),
                        .fg = dim_fg,
                        .bg = entry_bg,
                    });
                    c2 += 1;
                }
            }

            if (c2 < pane_cols) {
                terminal.grid.setCellAt(c2, list_start_row + display_row, .{
                    .char = ' ',
                    .fg = dim_fg,
                    .bg = entry_bg,
                });
                c2 += 1;
            }

            for (cmd) |ch| {
                if (c2 < pane_cols) {
                    terminal.grid.setCellAt(c2, list_start_row + display_row, .{
                        .char = @as(u21, ch),
                        .fg = entry_fg,
                        .bg = entry_bg,
                        .attrs = if (is_selected) .{ .bold = true } else .{},
                    });
                    c2 += 1;
                } else {
                    break;
                }
            }
        }
    }

    const footer_text = " Esc close  Enter copy  PgUp/PgDn scroll";
    const footer_start = if (pane_cols > footer_text.len) (pane_cols - footer_text.len) / 2 else 0;
    for (0..footer_text.len) |fi| {
        const cx = footer_start + fi;
        if (cx < pane_cols) {
            terminal.grid.setCellAt(@intCast(cx), @intCast(footer_row), .{
                .char = @as(u21, footer_text[fi]),
                .fg = Cell.Color.base00,
                .bg = Cell.Color.base08,
            });
        }
    }
}

fn gl_render_cb(_: ?*GtkGLArea, _: ?*cairo_t, _: ?*anyopaque) callconv(.c) c_int {
    if (!g_initialized or g_renderer == null or g_pane_manager == null) return 1;
    if (g_gl_area) |area| {
        gtk_gl_area_make_current(area);
    }

    c.glViewport(0, 0, g_fb_width, g_fb_height);

    const bg_f = @import("terminal/Cell.zig").Color.default_bg.toFloats();
    c.glClearColor(bg_f[0], bg_f[1], bg_f[2], 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);

    g_pane_manager.?.getVisiblePanesInto(&g_pane_list) catch return 1;

    const current_time = getTime();
    const panes_count = g_pane_list.items.len;

    c.glEnable(c.GL_SCISSOR_TEST);
    for (g_pane_list.items) |pane| {
        if (pane.is_history_pane) {
            const cell_h: f32 = @floatFromInt(g_font.?.cell_height);
            const inner_h = pane.height - (g_pane_manager.?.inner_padding * 2.0);
            const total_rows = @as(u32, @intFromFloat(inner_h / cell_h));
            const cell_w: f32 = @floatFromInt(g_font.?.cell_width);
            const inner_w = pane.width - (g_pane_manager.?.inner_padding * 2.0);
            const total_cols = @as(u32, @intFromFloat(inner_w / cell_w));
            const focused = g_pane_manager.?.getFocusedPane();
            const history = if (focused) |f| &f.terminal.command_history else &pane.terminal.command_history;
            if (g_active_tab < g_tabs.items.len) {
                renderHistoryPanel(&pane.terminal, history, total_cols, total_rows, &g_tabs.items[g_active_tab]);
            }
        }

        if (pane.file_explorer) |explorer| {
            if (explorer.visible) {
                const cell_h: f32 = @floatFromInt(g_font.?.cell_height);
                const inner_h = pane.height - (g_pane_manager.?.inner_padding * 2.0);
                const total_rows = @as(u32, @intFromFloat(inner_h / cell_h));
                const cell_w: f32 = @floatFromInt(g_font.?.cell_width);
                const inner_w = pane.width - (g_pane_manager.?.inner_padding * 2.0);
                const total_cols = @as(u32, @intFromFloat(inner_w / cell_w));
                explorer.render(&pane.terminal.grid, total_cols, total_rows);
            }
        }

        const sx: i32 = @intFromFloat(@round(pane.x));
        const sy: i32 = g_fb_height - @as(i32, @intFromFloat(@round(pane.y + pane.height)));
        const sw: i32 = @intFromFloat(@round(pane.width));
        const sh: i32 = @intFromFloat(@round(pane.height));
        c.glScissor(sx, sy, sw, sh);

        const offset_x = pane.x + g_pane_manager.?.inner_padding;
        const offset_y = pane.y + g_pane_manager.?.inner_padding;
        g_renderer.?.render(
            &pane.terminal.grid,
            g_fb_width,
            g_fb_height,
            offset_x,
            offset_y,
            pane.terminal.cursor_col,
            pane.terminal.cursor_row,
            current_time,
            g_last_input_time,
            pane.terminal.selection_start,
            pane.terminal.selection_end,
            pane.focused,
        );
    }
    c.glDisable(c.GL_SCISSOR_TEST);

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
        c.glClearColor(bg_f[0], bg_f[1], bg_f[2], 1.0);
    }

    return 1;
}

fn gl_resize_cb(_: ?*GtkGLArea, w: c_int, h: c_int, _: ?*anyopaque) callconv(.c) void {
    g_fb_width = w;
    g_fb_height = h;
    updateSizes();
    for (g_tabs.items) |*tab| {
        tab.pane_manager.handleResize(w, h) catch {};
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

    // Ctrl+, to toggle settings panel
    if (ctrl and !alt and keyval == 0x2C) {
        toggleSettings();
        queueRender();
        return 1;
    }

    // Font zoom shortcuts — work even when settings is open
    if (ctrl and !alt) {
        if (keyval == 0x2D or keyval == 0x3D or keyval == 0x2B or keyval == 0xFFAB) {
            if (SettingsUI.isOpen()) {
                if (getFocusedGrid()) |grid| SettingsUI.close(grid);
            }
            if (keyval == 0x2D) {
                changeZoomLevel(-1);
            } else {
                changeZoomLevel(1);
            }
            return 1;
        }
    }

    if (getFocusedGrid()) |grid| {
        if (ThemePreviewUI.isOpen()) {
            if (ThemePreviewUI.handleKey(grid, &g_config.?.settings, keyval, ctrl)) {
                if (!ThemePreviewUI.isOpen()) {
                    applySettings();
                }
                queueRender();
                return 1;
            }
        } else if (SettingsUI.isOpen()) {
            if (SettingsUI.handleKey(grid, keyval, ctrl)) {
                if (!SettingsUI.isOpen()) {
                    if (SettingsUI.consumeThemePreviewRequest()) {
                        if (g_config) |*cfg| {
                            ThemePreviewUI.open(grid, &cfg.settings, grid.cols, grid.rows) catch {};
                        }
                    } else if (SettingsUI.isDirty()) {
                        applySettings();
                    }
                }
                queueRender();
                return 1;
            }
        }
    }

    if (g_pane_manager != null and g_pane_manager.?.isExplorerActive()) {
        const explorer_cmd = KeyBindings.handleExplorerKey(keyval, ctrl, shift, alt);
        if (explorer_cmd != .none) {
            g_pane_manager.?.executeCommand(explorer_cmd) catch {};
            queueRender();
            return 1;
        }

        if (KeyBindings.handleExplorerChar(keyval)) |ch| {
            g_pane_manager.?.executeCommand(.explorerSearchChar) catch {};
            if (g_pane_manager.?.getFocusedPane()) |pane| {
                if (pane.file_explorer) |explorer| {
                    if (explorer.searching) {
                        explorer.addSearchChar(ch);
                        queueRender();
                        return 1;
                    }
                }
            }
        }
    }

    // Tab management shortcuts
    if (ctrl and !alt) {
        const is_shift_tab = shift and (keyval == 0xff09 or keyval == 0xfe20);
        const is_tab = !shift and keyval == 0xff09;
        const is_page_down = keyval == 0xff56; // Next
        const is_page_up = keyval == 0xff55; // Prior

        if (is_tab or is_page_down) {
            switchToTab((g_active_tab + 1) % g_tabs.items.len);
            return 1;
        }
        if (is_shift_tab or is_page_up) {
            switchToTab(if (g_active_tab == 0) g_tabs.items.len - 1 else g_active_tab - 1);
            return 1;
        }
    }

    if (ctrl and shift) {
        if (keyval == 't' or keyval == 'T') {
            createTab();
            return 1;
        }
        if (keyval == 'w' or keyval == 'W') {
            closeActiveTab();
            return 1;
        }
    }

    const direct_cmd = KeyBindings.handleDirectShortcut(keyval, ctrl, shift, alt);
    if (direct_cmd != .none and g_pane_manager != null) {
        g_pane_manager.?.executeCommand(direct_cmd) catch {};
        queueRender();
        return 1;
    }

    if (g_tabs.items[g_active_tab].history_visible) {
        const tab = &g_tabs.items[g_active_tab];
        const focused = g_pane_manager.?.getFocusedPane();
        const history_len = if (focused) |f| f.terminal.command_history.items.len else 0;

        if (keyval == 0xff1b or (ctrl and keyval == 'h')) {
            var panes: std.ArrayListUnmanaged(*Pane) = .empty;
            defer panes.deinit(std.heap.page_allocator);
            g_pane_manager.?.getVisiblePanesInto(&panes) catch return 0;
            for (panes.items) |p| {
                if (p.is_history_pane) {
                    _ = g_pane_manager.?.tree.closePane(p) catch false;
                    g_pane_manager.?.handleResize(g_fb_width, g_fb_height) catch {};
                    break;
                }
            }
            tab.history_visible = false;
            tab.history_scroll = 0;
            tab.history_selected_idx = 0;
            tab.historyClearSearch();
            if (g_history_button) |btn| {
                gtk_widget_remove_css_class(btn, "active");
            }
            queueRender();
            return 1;
        }

        if (keyval == 0xff0d or keyval == 0xff8d) {
            if (focused) |pane| {
                if (history_len > 0) {
                    const search_text = tab.historyGetSearch();
                    var filtered_indices: [1024]usize = undefined;
                    var filtered_count: usize = 0;
                    for (0..pane.terminal.command_history.items.len) |idx| {
                        if (filtered_count >= 1024) break;
                        if (search_text.len == 0 or
                            std.mem.indexOf(u8, pane.terminal.command_history.items[idx], search_text) != null)
                        {
                            filtered_indices[filtered_count] = idx;
                            filtered_count += 1;
                        }
                    }
                    if (filtered_count > 0 and tab.history_selected_idx < filtered_count) {
                        const orig_idx = filtered_indices[tab.history_selected_idx];
                        const cmd = pane.terminal.command_history.items[orig_idx];
                        if (g_gl_widget) |widget| {
                            const clipboard = gtk_widget_get_clipboard(@ptrCast(widget));
                            gdk_clipboard_set_text(clipboard, @ptrCast(cmd));
                        }
                    }
                }
            }
            var panes: std.ArrayListUnmanaged(*Pane) = .empty;
            defer panes.deinit(std.heap.page_allocator);
            g_pane_manager.?.getVisiblePanesInto(&panes) catch return 0;
            for (panes.items) |p| {
                if (p.is_history_pane) {
                    _ = g_pane_manager.?.tree.closePane(p) catch false;
                    g_pane_manager.?.handleResize(g_fb_width, g_fb_height) catch {};
                    break;
                }
            }
            tab.history_visible = false;
            tab.history_scroll = 0;
            tab.history_selected_idx = 0;
            tab.historyClearSearch();
            if (g_history_button) |btn| {
                gtk_widget_remove_css_class(btn, "active");
            }
            queueRender();
            return 1;
        }

        if (keyval == 0xff52 or keyval == 0xff53) {
            tab.historySelectUp(history_len);
            queueRender();
            return 1;
        }
        if (keyval == 0xff54) {
            tab.historySelectDown(history_len);
            queueRender();
            return 1;
        }

        if (!ctrl and !alt) {
            if (keyval >= 0x20 and keyval < 0x7F) {
                tab.historyAddSearchChar(@intCast(keyval));
                queueRender();
                return 1;
            }
            if (keyval == 0xff08) {
                tab.historyDeleteSearchChar();
                queueRender();
                return 1;
            }
        }

        if (keyval == 0xff55) {
            if (tab.history_scroll > 0) {
                tab.history_scroll -= 1;
                queueRender();
            }
            return 1;
        }
        if (keyval == 0xff56) {
            tab.history_scroll += 1;
            queueRender();
            return 1;
        }

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
                if (seq.len > 0 and (seq[0] == '\r' or seq[0] == '\n')) {
                    pane.commitCommand();
                }
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
                    pane.trackInput(ch);
                    pane.write(&.{ch}) catch {};
                }
            }
            return 1;
        }
        if (keyval == 0x08) {
            if (g_pane_manager != null) {
                const focused = g_pane_manager.?.getFocusedPane();
                if (focused) |pane| {
                    pane.trackInput(0x08);
                    pane.write("\x08 \x08") catch {};
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

    if (g_pane_manager.?.handleExplorerClick(fb_x, fb_y, false)) {
        queueRender();
        return;
    }

    if (g_tabs.items[g_active_tab].history_visible) {
        var panes: std.ArrayListUnmanaged(*Pane) = .empty;
        defer panes.deinit(std.heap.page_allocator);
        g_pane_manager.?.getVisiblePanesInto(&panes) catch return;
        for (panes.items) |hist_pane| {
            if (!hist_pane.is_history_pane) continue;
            if (fb_x >= hist_pane.x and fb_x < hist_pane.x + hist_pane.width and
                fb_y >= hist_pane.y and fb_y < hist_pane.y + hist_pane.height)
            {
                const cell_h: f32 = @floatFromInt(g_font.?.cell_height);
                const inner_h = hist_pane.height - (g_pane_manager.?.inner_padding * 2.0);
                const total_rows = @as(u32, @intFromFloat(inner_h / cell_h));
                const cell_w: f32 = @floatFromInt(g_font.?.cell_width);
                _ = hist_pane.width - (g_pane_manager.?.inner_padding * 2.0);
                _ = @as(f32, @floatFromInt(g_font.?.cell_width));

                const rel_x = fb_x - hist_pane.x - g_pane_manager.?.inner_padding;
                const rel_y = fb_y - hist_pane.y - g_pane_manager.?.inner_padding;
                _ = @as(i32, @intFromFloat(rel_x / cell_w));
                const click_row = @as(i32, @intFromFloat(rel_y / cell_h));

                const list_start_row: i32 = 2;
                const visible_rows: i32 = @intCast(total_rows - 3);
                if (click_row >= list_start_row and click_row < list_start_row + visible_rows) {
                    const focused = g_pane_manager.?.getFocusedPane();
                    if (focused) |term_pane| {
                        if (term_pane.terminal.command_history.items.len > 0) {
                            const tab = &g_tabs.items[g_active_tab];
                            const search_text = tab.historyGetSearch();
                            var filtered_indices: [1024]usize = undefined;
                            var filtered_count: usize = 0;
                            for (0..term_pane.terminal.command_history.items.len) |idx| {
                                if (filtered_count >= 1024) break;
                                if (search_text.len == 0 or
                                    std.mem.indexOf(u8, term_pane.terminal.command_history.items[idx], search_text) != null)
                                {
                                    filtered_indices[filtered_count] = idx;
                                    filtered_count += 1;
                                }
                            }
                            if (filtered_count > 0) {
                                const max_scroll: u32 = if (filtered_count > @as(usize, @intCast(visible_rows)))
                                    @intCast(filtered_count - @as(usize, @intCast(visible_rows))) else 0;
                                if (tab.history_scroll > max_scroll) tab.history_scroll = max_scroll;
                                const vis_idx = @as(usize, @intCast(click_row - list_start_row)) + tab.history_scroll;
                                if (vis_idx < filtered_count) {
                                    const orig_idx = filtered_indices[vis_idx];
                                    const cmd = term_pane.terminal.command_history.items[orig_idx];
                                    if (g_gl_widget) |widget| {
                                        const clipboard = gtk_widget_get_clipboard(@ptrCast(widget));
                                        gdk_clipboard_set_text(clipboard, @ptrCast(cmd));
                                    }
                                }
                            }
                        }
                    }
                }

                _ = g_pane_manager.?.tree.closePane(hist_pane) catch false;
                g_pane_manager.?.handleResize(g_fb_width, g_fb_height) catch {};
                g_tabs.items[g_active_tab].history_visible = false;
                g_tabs.items[g_active_tab].history_scroll = 0;
                g_tabs.items[g_active_tab].history_selected_idx = 0;
                g_tabs.items[g_active_tab].historyClearSearch();
                if (g_history_button) |btn| {
                    gtk_widget_remove_css_class(btn, "active");
                }
                queueRender();
                if (g_gl_widget) |widget| {
                    gtk_widget_grab_focus(widget);
                }
                return;
            }
        }
    }

    const inner_pad = g_pane_manager.?.inner_padding;

    const pane = g_pane_manager.?.findPaneAt(fb_x, fb_y);
    if (pane) |p| {
        const focused = g_pane_manager.?.getFocusedPane();
        if (focused) |f| f.focused = false;
        p.focused = true;

        const offset_x = p.x + inner_pad;
        const offset_y = p.y + inner_pad;
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
        const offset_y = p.y + inner_pad;
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
        if (pane.terminal.using_alt_screen) {
            if (dy > 0.0) {
                pane.write("\x1b[B") catch {};
            } else if (dy < 0.0) {
                pane.write("\x1b[A") catch {};
            }
            return 1;
        }
    }
    return 0;
}

fn ptyReadIdle(_: ?*anyopaque) callconv(.c) c_int {
    if (!g_initialized) return 0;
    for (g_tabs.items) |*tab| {
        var panes: std.ArrayListUnmanaged(*Pane) = .empty;
        tab.pane_manager.getVisiblePanesInto(&panes) catch continue;
        defer panes.deinit(std.heap.page_allocator);

        var read_buf: [65536]u8 = undefined;
        for (panes.items) |pane| {
            const bytes_read = pane.read(&read_buf) catch 0;
            if (bytes_read > 0) {
                pane.feed(read_buf[0..bytes_read]);
            }
        }

        const current_time = getTime();
        tab.pane_manager.tick(current_time);
    }

    queueRender();
    return 1;
}

fn clock_tick(_: ?*anyopaque) callconv(.c) c_int {
    if (!g_initialized) return 0;
    if (g_clock_label) |label| {
        var ts: std.c.timespec = undefined;
        _ = clock_gettime(CLOCK_REALTIME, &ts);
        var tm: CTime = undefined;
        const sec = @as(c_long, @intCast(ts.sec));
        _ = localtime_r(&sec, &tm);
        const hours: u64 = @intCast(tm.tm_hour);
        const minutes: u64 = @intCast(tm.tm_min);
        var buf: [16]u8 = undefined;
        const len = std.fmt.bufPrint(&buf, "{d:0>2}:{d:0>2}", .{ hours, minutes }) catch return 1;
        var text_buf: [16:0]u8 = undefined;
        @memcpy(text_buf[0..len.len], len);
        text_buf[len.len] = 0;
        gtk_label_set_text(label, &text_buf);
    }

    // Update tab titles with CWD
    for (g_tabs.items) |*tab| {
        updateTabButtonLabel(tab);
    }

    return 1;
}

fn tab_clicked_cb(_: ?*GtkWidget, data: ?*anyopaque) callconv(.c) void {
    if (data) |d| {
        const idx = @as(*usize, @ptrCast(@alignCast(d))).*;
        switchToTab(idx);
    }
    // Re-grab focus on GL area so keyboard input keeps working
    if (g_gl_widget) |widget| {
        gtk_widget_grab_focus(widget);
    }
}

fn history_clicked_cb(_: ?*GtkWidget, _: ?*anyopaque) callconv(.c) void {
    if (g_tabs.items.len == 0 or g_pane_manager == null) return;
    const tab = &g_tabs.items[g_active_tab];

    if (tab.history_visible) {
        // Close history pane
        var panes: std.ArrayListUnmanaged(*Pane) = .empty;
        defer panes.deinit(std.heap.page_allocator);
        g_pane_manager.?.getVisiblePanesInto(&panes) catch return;
        for (panes.items) |p| {
            if (p.is_history_pane) {
                if (g_pane_manager.?.tree.countPanes() > 1) {
                    _ = g_pane_manager.?.tree.closePane(p) catch false;
                    g_pane_manager.?.handleResize(g_fb_width, g_fb_height) catch {};
                }
                break;
            }
        }
        tab.history_visible = false;
        tab.history_scroll = 0;
        tab.history_selected_idx = 0;
        tab.historyClearSearch();
        if (g_history_button) |btn| {
            gtk_widget_remove_css_class(btn, "active");
        }
    } else {
        // Create history pane
        if (g_pane_manager.?.getFocusedPane()) |focused| {
            const new_pane = g_pane_manager.?.tree.splitPane(focused, .horizontal, 0.7) catch return;
            new_pane.is_history_pane = true;
            g_pane_manager.?.handleResize(g_fb_width, g_fb_height) catch {};
            tab.history_visible = true;
            tab.history_scroll = 0;
            tab.history_selected_idx = 0;
            tab.historyClearSearch();
            if (g_history_button) |btn| {
                gtk_widget_add_css_class(btn, "active");
            }
        }
    }
    queueRender();
    if (g_gl_widget) |widget| {
        gtk_widget_grab_focus(widget);
    }
}

fn toggleSettings() void {
    const focused_grid = getFocusedGrid();
    if (SettingsUI.isOpen()) {
        if (focused_grid) |grid| SettingsUI.close(grid);
        queueRender();
        return;
    }
    const pane = g_pane_manager.?.getFocusedPane() orelse return;
    const cell_h: f32 = @floatFromInt(g_font.?.cell_height);
    const cell_w: f32 = @floatFromInt(g_font.?.cell_width);
    const inner_h = pane.height - (g_pane_manager.?.inner_padding * 2.0);
    const inner_w = pane.width - (g_pane_manager.?.inner_padding * 2.0);
    const rows = @as(u32, @intFromFloat(inner_h / cell_h));
    const cols = @as(u32, @intFromFloat(inner_w / cell_w));
    if (cols < 10 or rows < 5) return;

    const grid = &pane.terminal.grid;
    const old_cols = grid.cols;
    const old_rows = grid.rows;
    const settings = if (g_config) |*cfg| &cfg.settings else return;
    SettingsUI.open(grid, settings, @min(cols, old_cols), @min(rows, old_rows)) catch return;
    queueRender();
}

fn gear_clicked_cb(_: ?*GtkWidget, _: ?*anyopaque) callconv(.c) void {
    toggleSettings();
    if (g_gl_widget) |widget| {
        gtk_widget_grab_focus(widget);
    }
}

fn applySettings() void {
    if (g_config) |*cfg| {
        cfg.settings = SettingsUI.getSettings().*;
    }
    // Save old colors before applying theme
    const CellColor = @import("terminal/Cell.zig").Color;
    const old_colors = [_]CellColor{
        CellColor.default_bg, CellColor.default_fg,
        CellColor.black, CellColor.red, CellColor.green, CellColor.yellow,
        CellColor.blue, CellColor.magenta, CellColor.cyan, CellColor.white,
        CellColor.bright_black, CellColor.bright_red, CellColor.bright_green, CellColor.bright_yellow,
        CellColor.bright_blue, CellColor.bright_magenta, CellColor.bright_cyan, CellColor.bright_white,
    };
    // Apply theme
    if (g_config) |*cfg| {
        var new_cfg = Config.load(std.heap.page_allocator) catch return;
        std.heap.page_allocator.free(cfg.css);
        cfg.theme = new_cfg.theme;
        cfg.css = new_cfg.css;
        ConfigParser.deinitMap(&new_cfg.settings_map);
        CellColor.applyTheme(&cfg.theme);
        loadCss();
    }
    // Update cell colors in all terminals that match the old theme defaults
    const new_colors = [_]CellColor{
        CellColor.default_bg, CellColor.default_fg,
        CellColor.black, CellColor.red, CellColor.green, CellColor.yellow,
        CellColor.blue, CellColor.magenta, CellColor.cyan, CellColor.white,
        CellColor.bright_black, CellColor.bright_red, CellColor.bright_green, CellColor.bright_yellow,
        CellColor.bright_blue, CellColor.bright_magenta, CellColor.bright_cyan, CellColor.bright_white,
    };
    for (g_tabs.items) |*tab| {
        var panes = tab.pane_manager.getVisiblePanes() catch continue;
        defer panes.deinit(std.heap.page_allocator);
        for (panes.items) |pane| {
            const total = @as(usize, pane.terminal.grid.rows) * @as(usize, pane.terminal.grid.cols);
            var i: usize = 0;
            while (i < total) : (i += 1) {
                const cell = &pane.terminal.grid.cells[i];
                for (old_colors, 0..) |old_c, c_idx| {
                    if (cell.bg.r == old_c.r and cell.bg.g == old_c.g and cell.bg.b == old_c.b) {
                        cell.bg = new_colors[c_idx];
                        break;
                    }
                }
                for (old_colors, 0..) |old_c, c_idx| {
                    if (cell.fg.r == old_c.r and cell.fg.g == old_c.g and cell.fg.b == old_c.b) {
                        cell.fg = new_colors[c_idx];
                        break;
                    }
                }
            }
        }
    }
    // Apply zoom level
    g_font_pixel_size = getActualFontSize();
    if (g_font) |f| {
        f.setPixelSize(g_font_pixel_size) catch {};
    }
    if (g_renderer) |r| {
        if (r.fallback_font) |emoji| {
            emoji.setPixelSize(g_font_pixel_size) catch {};
        }
        r.reloadFont() catch {};
    }
    for (g_tabs.items) |*tab| {
        tab.pane_manager.handleResize(g_fb_width, g_fb_height) catch {};
    }
    updateZoomLabel();
    // Apply window size
    if (g_config) |cfg| {
        if (g_window) |win| {
            gtk_window_set_default_size(win, cfg.settings.window_width, cfg.settings.window_height);
        }
    }
    queueRender();
}

fn getFocusedGrid() ?*Grid {
    const pane = g_pane_manager.?.getFocusedPane() orelse return null;
    return &pane.terminal.grid;
}

fn zoom_reset_cb(_: ?*GtkWidget, _: ?*anyopaque) callconv(.c) void {
    if (getZoomLevel() == 100) return;
    changeZoomLevel(100 - @as(i32, @intCast(getZoomLevel())));
    if (g_gl_widget) |widget| {
        gtk_widget_grab_focus(widget);
    }
}

fn switchToTab(idx: usize) void {
    if (idx >= g_tabs.items.len) return;
    g_active_tab = idx;
    g_pane_manager = g_tabs.items[idx].pane_manager;

    for (g_tabs.items, 0..) |*tab, i| {
        if (tab.button) |btn| {
            if (i == idx) {
                gtk_widget_add_css_class(btn, "active-tab");
            } else {
                gtk_widget_remove_css_class(btn, "active-tab");
            }
        }
    }

    queueRender();
}

fn createTab() void {
    if (g_font == null) return;

    g_tab_counter += 1;

    const pm_ptr = std.heap.page_allocator.create(PaneManager) catch return;
    const init_cols = if (g_config) |cfg| cfg.settings.initial_cols else INITIAL_COLS;
    const init_rows = if (g_config) |cfg| cfg.settings.initial_rows else INITIAL_ROWS;
    pm_ptr.* = PaneManager.init(std.heap.page_allocator, g_font.?, init_cols, init_rows) catch {
        std.heap.page_allocator.destroy(pm_ptr);
        return;
    };

    if (g_config) |cfg| {
        pm_ptr.padding_x = cfg.settings.padding_x;
        pm_ptr.padding_y = cfg.settings.padding_y;
        pm_ptr.border_size = cfg.settings.border_size;
        pm_ptr.inner_padding = cfg.settings.inner_padding;
    }

    if (g_fb_width > 0 and g_fb_height > 0) {
        pm_ptr.handleResize(g_fb_width, g_fb_height) catch {};
    }

    const tab_idx = g_tabs.items.len;

    var tab = Tab{
        .pane_manager = pm_ptr,
    };
    tab.setTitleFmt("~", .{});

    g_tabs.append(std.heap.page_allocator, tab) catch {
        pm_ptr.deinit();
        std.heap.page_allocator.destroy(pm_ptr);
        return;
    };

    const button = gtk_button_new_with_label(tab.getTitle().ptr);
    gtk_widget_add_css_class(button, "tab-button");
    gtk_widget_add_css_class(button, "active-tab");

    // Extract the label from the button
    const label_widget = gtk_button_get_child(@ptrCast(button));

    // Enable truncation (...)
    gtk_label_set_ellipsize(label_widget, PANGO_ELLIPSIZE_END);

    // Force the absolute minimum width to 1 character.
    // This gives GTK permission to squeeze the tabs instead of widening the window.
    const min_chars = if (g_config) |cfg| cfg.settings.tab_min_width_chars else 1;
    gtk_label_set_width_chars(label_widget, min_chars);

    // Limit the maximum width so long paths don't look ridiculous before squeezing
    const max_chars = if (g_config) |cfg| cfg.settings.tab_max_width_chars else 30;
    gtk_label_set_max_width_chars(label_widget, max_chars);

    const idx_ptr = std.heap.page_allocator.create(usize) catch return;
    idx_ptr.* = tab_idx;
    g_tabs.items[tab_idx].idx_ptr = idx_ptr;
    _ = signalConnect(@ptrCast(button), "clicked", @ptrCast(@constCast(&tab_clicked_cb)), @ptrCast(idx_ptr));

    g_tabs.items[tab_idx].button = button;

    // Add to tab container (before "+" button)
    if (g_tab_container) |container| {
        gtk_box_append(container, @ptrCast(button));
    }

    switchToTab(tab_idx);
}

fn closeActiveTab() void {
    if (g_tabs.items.len <= 1) return;

    const idx = g_active_tab;
    var tab = g_tabs.items[idx];

    if (tab.idx_ptr) |ptr| {
        std.heap.page_allocator.destroy(ptr);
    }

    if (tab.button) |btn| {
        if (g_tab_container) |container| {
            gtk_box_remove(container, btn);
        }
    }

    tab.pane_manager.deinit();
    std.heap.page_allocator.destroy(tab.pane_manager);

    _ = g_tabs.swapRemove(idx);

    for (g_tabs.items, 0..) |*t, i| {
        if (t.idx_ptr) |ptr| {
            ptr.* = i;
        }
    }

    if (g_active_tab >= g_tabs.items.len) {
        g_active_tab = g_tabs.items.len - 1;
    }

    g_pane_manager = g_tabs.items[g_active_tab].pane_manager;

    switchToTab(g_active_tab);

    if (g_gl_widget) |widget| {
        gtk_widget_grab_focus(widget);
    }
    queueRender();
}

fn loadCss() void {
    const provider = gtk_css_provider_new();
    const css_data = if (g_config) |*cfg| cfg.css else TAB_CSS;
    gtk_css_provider_load_from_data(provider, css_data.ptr, -1);
    const display = gdk_display_get_default();
    if (display) |d| {
        gtk_style_context_add_provider_for_display(d, provider, GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    }
}

fn window_destroy_cb(_: ?*GtkWindow, _: ?*anyopaque) callconv(.c) void {
    shutdown();
}

fn close_window_cb(_: ?*GtkWidget, _: ?*anyopaque) callconv(.c) void {
    if (g_window) |win| {
        gtk_window_close(win);
    }
}

fn minimize_window_cb(_: ?*GtkWidget, _: ?*anyopaque) callconv(.c) void {
    if (g_window) |win| {
        gtk_window_minimize(win);
    }
}

fn maximize_window_cb(_: ?*GtkWidget, _: ?*anyopaque) callconv(.c) void {
    if (g_window) |win| {
        if (gtk_window_is_maximized(win) != 0) {
            gtk_window_unmaximize(win);
        } else {
            gtk_window_maximize(win);
        }
    }
}

fn shutdown() void {
    g_initialized = false;
    for (g_tabs.items) |*tab| {
        tab.pane_manager.deinit();
        std.heap.page_allocator.destroy(tab.pane_manager);
        if (tab.idx_ptr) |ptr| {
            std.heap.page_allocator.destroy(ptr);
        }
    }
    g_tabs.deinit(std.heap.page_allocator);
    g_pane_list.deinit(std.heap.page_allocator);

    if (g_renderer) |r| {
        r.deinit();
        std.heap.page_allocator.destroy(r);
    }

    if (g_font) |f| {
        f.deinit();
        std.heap.page_allocator.destroy(f);
    }

    FontConfig.deinit();
    g_pane_manager = null;
    g_font = null;
    g_renderer = null;
}

fn on_activate(_: ?*GtkApplication, _: ?*anyopaque) callconv(.c) void {
    g_window = @ptrCast(gtk_application_window_new(g_app.?));
    gtk_window_set_title(g_window.?, "zest");
    const win_w = if (g_config) |cfg| cfg.settings.window_width else 1280;
    const win_h = if (g_config) |cfg| cfg.settings.window_height else 720;
    gtk_window_set_default_size(g_window.?, win_w, win_h);

    _ = signalConnect(@ptrCast(g_window.?), "destroy", @ptrCast(@constCast(&window_destroy_cb)), null);

    // Apply CSS theme
    loadCss();

    // Create main vertical box
    g_main_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);

    // Create overlay for GL area
    g_overlay = gtk_overlay_new();
    gtk_widget_set_vexpand(@ptrCast(g_overlay.?), 1);
    gtk_widget_set_hexpand(@ptrCast(g_overlay.?), 1);

    // Create GL area
    g_gl_area = @ptrCast(gtk_gl_area_new());
    g_gl_widget = @ptrCast(g_gl_area.?);
    gtk_gl_area_set_auto_render(g_gl_area.?, 0);
    gtk_gl_area_set_has_stencil_buffer(g_gl_area.?, 0);
    gtk_gl_area_set_has_depth_buffer(g_gl_area.?, 0);
    gtk_gl_area_set_use_es(g_gl_area.?, 0);
    gtk_widget_add_css_class(@ptrCast(g_gl_area.?), "gl-area");

    _ = signalConnect(@ptrCast(g_gl_area.?), "realize", @ptrCast(@constCast(&gl_realize_cb)), null);
    _ = signalConnect(@ptrCast(g_gl_area.?), "render", @ptrCast(@constCast(&gl_render_cb)), null);
    _ = signalConnect(@ptrCast(g_gl_area.?), "resize", @ptrCast(@constCast(&gl_resize_cb)), null);

    gtk_overlay_set_child(@ptrCast(g_overlay.?), @ptrCast(g_gl_area.?));

    // Add overlay to main box
    gtk_box_append(@ptrCast(g_main_box.?), @ptrCast(g_overlay.?));

    // Create tab bar: [tab_container] [+] [history] [clock]
    g_tab_bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_add_css_class(@ptrCast(g_tab_bar.?), "tab-bar");
    gtk_box_append(@ptrCast(g_main_box.?), @ptrCast(g_tab_bar.?));

    // Tab container: wrapped in a scrolled window (no scrollbars) so that
    // many tabs get clipped/squeezed rather than growing the window.
    g_tab_container = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_add_css_class(@ptrCast(g_tab_container.?), "tab-container");

    // GTK_OVERFLOW_HIDDEN = 1: clip children that exceed the allocated width
    gtk_widget_set_overflow(@ptrCast(g_tab_container.?), 1);

    // Wrap in a scrolled window with POLICY_NEVER so no scrollbars appear
    // but the container is still clipped to its allocated size.
    const tab_scroll = gtk_scrolled_window_new(null, null);
    gtk_widget_add_css_class(tab_scroll, "tab-scroll");
    // GTK_POLICY_EXTERNAL = 3, GTK_POLICY_NEVER = 2
    gtk_scrolled_window_set_policy(tab_scroll, 3, 2);
    gtk_scrolled_window_set_child(tab_scroll, @ptrCast(g_tab_container.?));
    gtk_widget_set_hexpand(tab_scroll, 1);

    gtk_box_append(@ptrCast(g_tab_bar.?), tab_scroll);

    // Right section: [zoom] [history] [clock]
    g_right_section = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_add_css_class(@ptrCast(g_right_section.?), "right-section");
    gtk_box_append(@ptrCast(g_tab_bar.?), @ptrCast(g_right_section.?));

    // Zoom label (clickable button to reset)
    g_zoom_label = gtk_button_new_with_label("100%");
    gtk_widget_add_css_class(@ptrCast(g_zoom_label.?), "zoom-label");
    _ = signalConnect(@ptrCast(g_zoom_label.?), "clicked", @ptrCast(@constCast(&zoom_reset_cb)), null);
    gtk_box_append(@ptrCast(g_right_section.?), @ptrCast(g_zoom_label.?));

    // History button
    g_history_button = gtk_button_new_with_label("H");
    gtk_widget_add_css_class(@ptrCast(g_history_button.?), "history-button");
    _ = signalConnect(@ptrCast(g_history_button.?), "clicked", @ptrCast(@constCast(&history_clicked_cb)), null);
    gtk_box_append(@ptrCast(g_right_section.?), @ptrCast(g_history_button.?));

    // Gear button (settings)
    g_gear_button = gtk_button_new_with_label("\u{2699}");
    gtk_widget_add_css_class(@ptrCast(g_gear_button.?), "gear-button");
    _ = signalConnect(@ptrCast(g_gear_button.?), "clicked", @ptrCast(@constCast(&gear_clicked_cb)), null);
    gtk_box_append(@ptrCast(g_right_section.?), @ptrCast(g_gear_button.?));

    // Clock label
    g_clock_label = gtk_label_new("00:00");
    gtk_widget_add_css_class(@ptrCast(g_clock_label.?), "clock-label");
    gtk_box_append(@ptrCast(g_right_section.?), @ptrCast(g_clock_label.?));

    // Set main box as window child
    gtk_window_set_child(g_window.?, @ptrCast(g_main_box.?));

    // Setup input controllers on GL widget
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

    const scroll = gtk_event_controller_scroll_new(1);
    _ = signalConnect(@ptrCast(scroll), "scroll", @ptrCast(@constCast(&scroll_cb)), null);
    gtk_widget_add_controller(widget, @ptrCast(scroll));

    gtk_window_present(g_window.?);
    updateSizes();

    // Start clock timer
    const clock_ms = if (g_config) |cfg| cfg.settings.clock_tick_interval_ms else 1000;
    _ = g_timeout_add(clock_ms, clock_tick, null);
}

pub fn main() !void {
    g_last_input_time = getTime();

    g_config = Config.load(std.heap.page_allocator) catch null;
    if (g_config) |*cfg| {
        @import("terminal/Cell.zig").Color.applyTheme(&cfg.theme);
    }

    g_app = @ptrCast(gtk_application_new("com.zest.terminal", G_APPLICATION_FLAGS_NONE));
    if (g_app == null) return error.GtkInitFailed;
    _ = signalConnect(@ptrCast(g_app.?), "activate", @ptrCast(@constCast(&on_activate)), null);

    _ = g_application_run(g_app.?, 0, null);
}
