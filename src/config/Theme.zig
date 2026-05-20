const std = @import("std");

pub const Color3 = [3]u8;

pub const Theme = struct {
    foreground: Color3 = .{ 0xc1, 0xc1, 0xc1 },
    background: Color3 = .{ 0x00, 0x00, 0x00 },
    base00: Color3 = .{ 0x00, 0x00, 0x00 },
    base01: Color3 = .{ 0x12, 0x12, 0x12 },
    base02: Color3 = .{ 0x22, 0x22, 0x22 },
    base03: Color3 = .{ 0x33, 0x33, 0x33 },
    base04: Color3 = .{ 0x99, 0x99, 0x99 },
    base05: Color3 = .{ 0xc1, 0xc1, 0xc1 },
    base06: Color3 = .{ 0x99, 0x99, 0x99 },
    base07: Color3 = .{ 0xc1, 0xc1, 0xc1 },
    base08: Color3 = .{ 0x5f, 0x87, 0x87 },
    base09: Color3 = .{ 0xaa, 0xaa, 0xaa },
    base0A: Color3 = .{ 0x55, 0x66, 0x77 },
    base0B: Color3 = .{ 0x77, 0x99, 0xbb },
    base0C: Color3 = .{ 0xaa, 0xaa, 0xaa },
    base0D: Color3 = .{ 0x88, 0x88, 0x88 },
    base0E: Color3 = .{ 0x99, 0x99, 0x99 },
    base0F: Color3 = .{ 0x44, 0x44, 0x44 },

    tab_bar_bg: Color3 = .{ 0x0d, 0x0d, 0x0d },
    tab_button_bg: Color3 = .{ 0x1a, 0x1a, 0x1a },
    tab_button_fg: Color3 = .{ 0x99, 0x99, 0x99 },
    tab_button_hover_bg: Color3 = .{ 0x25, 0x25, 0x25 },
    tab_button_hover_fg: Color3 = .{ 0xc1, 0xc1, 0xc1 },
    tab_active_bg: Color3 = .{ 0x00, 0x00, 0x00 },
    tab_active_fg: Color3 = .{ 0xe0, 0xe0, 0xe0 },
    tab_active_border: Color3 = .{ 0x5f, 0x87, 0x87 },
    right_section_accent: Color3 = .{ 0x5f, 0x87, 0x87 },
    clock_fg: Color3 = .{ 0x00, 0x00, 0x00 },
    history_button_fg: Color3 = .{ 0x00, 0x00, 0x00 },
    history_button_active_bg: Color3 = .{ 0x5f, 0x87, 0x87 },
    zoom_label_fg: Color3 = .{ 0x00, 0x00, 0x00 },

    pub fn load(allocator: std.mem.Allocator, map: *const std.StringHashMap([]u8)) !Theme {
        var t = Theme{};
        var it = map.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;
            parseField(&t, key, value);
        }
        _ = allocator;
        return t;
    }

    pub fn generateCss(self: *const Theme, allocator: std.mem.Allocator) ![:0]u8 {
        var buf: std.ArrayList(u8) = .empty;
        const bg = self.background;
        const tb = self.tab_bar_bg;
        const tbb = self.tab_button_bg;
        const tbf = self.tab_button_fg;
        const tbhb = self.tab_button_hover_bg;
        const tbhf = self.tab_button_hover_fg;
        const tab = self.tab_active_bg;
        const taf = self.tab_active_fg;
        const tabo = self.tab_active_border;
        const rsa = self.right_section_accent;
        const cf = self.background;
        const hf = self.background;
        const hab = self.history_button_active_bg;
        const zf = self.background;

        try buf.print(allocator,
            \\.gl-area {{ background-color: #{x:0>2}{x:0>2}{x:0>2}; }}
            \\box.tab-bar {{ background-color: #{x:0>2}{x:0>2}{x:0>2}; padding: 0; min-height: 28px; }}
            \\box.window-controls {{ padding: 0 8px; }}
            \\button.window-btn-close, button.window-btn-minimize, button.window-btn-maximize {{
            \\    background-color: transparent;
            \\    border: none;
            \\    border-radius: 50%;
            \\    min-width: 12px;
            \\    min-height: 12px;
            \\    padding: 0;
            \\    margin: 0 3px;
            \\    box-shadow: none;
            \\}}
            \\button.window-btn-close {{ background-color: #ff5f56; }}
            \\button.window-btn-minimize {{ background-color: #ffbd2e; }}
            \\button.window-btn-maximize {{ background-color: #27c93f; }}
            \\button.window-btn-close:hover {{ background-color: #ff3f34; }}
            \\button.window-btn-minimize:hover {{ background-color: #ff9f1a; }}
            \\button.window-btn-maximize:hover {{ background-color: #1a9c33; }}
            \\box.tab-container {{ background-color: #{x:0>2}{x:0>2}{x:0>2}; }}
            \\scrolledwindow.tab-scroll {{ background-color: #{x:0>2}{x:0>2}{x:0>2}; border: none; }}
            \\scrolledwindow.tab-scroll undershoot, scrolledwindow.tab-scroll overshoot {{ border: none; box-shadow: none; }}
        , .{ bg[0], bg[1], bg[2], tb[0], tb[1], tb[2], tb[0], tb[1], tb[2], tb[0], tb[1], tb[2] });

        try buf.print(allocator,
            \\button.tab-button {{ background-color: #{x:0>2}{x:0>2}{x:0>2}; color: #{x:0>2}{x:0>2}{x:0>2}; border: none; border-radius: 0; padding: 4px 12px; font-size: 11px; min-height: 28px; transition: all 150ms ease; }}
            \\button.tab-button:hover {{ background-color: #{x:0>2}{x:0>2}{x:0>2}; color: #{x:0>2}{x:0>2}{x:0>2}; }}
        , .{ tbb[0], tbb[1], tbb[2], tbf[0], tbf[1], tbf[2], tbhb[0], tbhb[1], tbhb[2], tbhf[0], tbhf[1], tbhf[2] });

        try buf.print(allocator,
            \\button.active-tab {{ background-color: #{x:0>2}{x:0>2}{x:0>2}; color: #{x:0>2}{x:0>2}{x:0>2}; border-bottom: 2px solid #{x:0>2}{x:0>2}{x:0>2}; }}
        , .{ tab[0], tab[1], tab[2], taf[0], taf[1], taf[2], tabo[0], tabo[1], tabo[2] });

        try buf.print(allocator,
            \\box.right-section {{
            \\    background-image: linear-gradient(to right, rgba({d},{d},{d},0) 0%, rgba({d},{d},{d},1) 30%);
            \\    padding: 0 6px 0 32px;
            \\}}
        , .{ rsa[0], rsa[1], rsa[2], rsa[0], rsa[1], rsa[2] });

        try buf.print(allocator,
            \\label.clock-label {{
            \\    color: #{x:0>2}{x:0>2}{x:0>2};
            \\    background-color: transparent;
            \\    font-size: 15px;
            \\    font-weight: 700;
            \\    font-family: monospace;
            \\    padding: 2px 14px;
            \\    border-radius: 2px;
            \\    letter-spacing: 1px;
            \\}}
            \\button.history-button {{
            \\    background-color: transparent;
            \\    color: #{x:0>2}{x:0>2}{x:0>2};
            \\    border: none;
            \\    border-radius: 0;
            \\    padding: 2px 8px;
            \\    font-size: 16px;
            \\    font-weight: 700;
            \\    min-height: 28px;
            \\}}
        , .{ cf[0], cf[1], cf[2], hf[0], hf[1], hf[2] });

        try buf.print(allocator,
            \\button.history-button:hover {{
            \\    background-color: rgba({d},{d},{d},0.15);
            \\    color: #{x:0>2}{x:0>2}{x:0>2};
            \\}}
            \\button.history-button.active {{
            \\    background-color: rgba({d},{d},{d},0.3);
            \\    color: #{x:0>2}{x:0>2}{x:0>2};
            \\}}
        , .{ hab[0], hab[1], hab[2], hf[0], hf[1], hf[2], hab[0], hab[1], hab[2], hf[0], hf[1], hf[2] });

        try buf.print(allocator,
            \\button.zoom-label {{
            \\    background-color: transparent;
            \\    color: #{x:0>2}{x:0>2}{x:0>2};
            \\    border: none;
            \\    border-radius: 0;
            \\    padding: 2px 6px;
            \\    font-size: 12px;
            \\    font-weight: 700;
            \\    font-family: monospace;
            \\    min-height: 28px;
            \\}}
            \\button.zoom-label:hover {{
            \\    background-color: rgba({d},{d},{d},0.15);
            \\    color: #{x:0>2}{x:0>2}{x:0>2};
            \\}}
            \\button.gear-button {{
            \\    background-color: transparent;
            \\    color: #{x:0>2}{x:0>2}{x:0>2};
            \\    border: none;
            \\    border-radius: 0;
            \\    padding: 2px 8px;
            \\    font-size: 16px;
            \\    min-height: 28px;
            \\    min-width: 28px;
            \\}}
            \\button.gear-button:hover {{
            \\    background-color: rgba({d},{d},{d},0.15);
            \\    color: #{x:0>2}{x:0>2}{x:0>2};
            \\}}
        , .{ zf[0], zf[1], zf[2], zf[0], zf[1], zf[2], zf[0], zf[1], zf[2], zf[0], zf[1], zf[2], zf[0], zf[1], zf[2], zf[0], zf[1], zf[2] });

        try buf.append(allocator, 0);
        return buf.items[0 .. buf.items.len - 1 :0];
    }

    fn parseField(t: *Theme, key: []const u8, value: []const u8) void {
        const colors = struct {
            fn parseHex(s: []const u8) ?Color3 {
                const trimmed = std.mem.trim(u8, s, &std.ascii.whitespace);
                if (trimmed.len == 7 and trimmed[0] == '#') {
                    const r = std.fmt.parseInt(u8, trimmed[1..3], 16) catch return null;
                    const g = std.fmt.parseInt(u8, trimmed[3..5], 16) catch return null;
                    const b = std.fmt.parseInt(u8, trimmed[5..7], 16) catch return null;
                    return Color3{ r, g, b };
                }
                return null;
            }
        };

        if (colors.parseHex(value)) |c| {
            if (std.mem.eql(u8, key, "foreground")) { t.foreground = c; } else if (std.mem.eql(u8, key, "background")) { t.background = c; } else if (std.mem.eql(u8, key, "base00")) { t.base00 = c; } else if (std.mem.eql(u8, key, "base01")) { t.base01 = c; } else if (std.mem.eql(u8, key, "base02")) { t.base02 = c; } else if (std.mem.eql(u8, key, "base03")) { t.base03 = c; } else if (std.mem.eql(u8, key, "base04")) { t.base04 = c; } else if (std.mem.eql(u8, key, "base05")) { t.base05 = c; } else if (std.mem.eql(u8, key, "base06")) { t.base06 = c; } else if (std.mem.eql(u8, key, "base07")) { t.base07 = c; } else if (std.mem.eql(u8, key, "base08")) { t.base08 = c; } else if (std.mem.eql(u8, key, "base09")) { t.base09 = c; } else if (std.mem.eql(u8, key, "base0A")) { t.base0A = c; } else if (std.mem.eql(u8, key, "base0B")) { t.base0B = c; } else if (std.mem.eql(u8, key, "base0C")) { t.base0C = c; } else if (std.mem.eql(u8, key, "base0D")) { t.base0D = c; } else if (std.mem.eql(u8, key, "base0E")) { t.base0E = c; } else if (std.mem.eql(u8, key, "base0F")) { t.base0F = c; } else if (std.mem.eql(u8, key, "tab_bar_bg")) { t.tab_bar_bg = c; } else if (std.mem.eql(u8, key, "tab_button_bg")) { t.tab_button_bg = c; } else if (std.mem.eql(u8, key, "tab_button_fg")) { t.tab_button_fg = c; } else if (std.mem.eql(u8, key, "tab_button_hover_bg")) { t.tab_button_hover_bg = c; } else if (std.mem.eql(u8, key, "tab_button_hover_fg")) { t.tab_button_hover_fg = c; } else if (std.mem.eql(u8, key, "tab_active_bg")) { t.tab_active_bg = c; } else if (std.mem.eql(u8, key, "tab_active_fg")) { t.tab_active_fg = c; } else if (std.mem.eql(u8, key, "tab_active_border")) { t.tab_active_border = c; } else if (std.mem.eql(u8, key, "right_section_accent")) { t.right_section_accent = c; } else if (std.mem.eql(u8, key, "clock_fg")) { t.clock_fg = c; } else if (std.mem.eql(u8, key, "history_button_fg")) { t.history_button_fg = c; } else if (std.mem.eql(u8, key, "history_button_active_bg")) { t.history_button_active_bg = c; } else if (std.mem.eql(u8, key, "zoom_label_fg")) { t.zoom_label_fg = c; }
        }
    }
};
