const std = @import("std");
const Theme = @import("../config/Theme.zig");

pub const Cell = struct {
    char: u21 = ' ',
    fg: Color = .{ .r = 0xc1, .g = 0xc1, .b = 0xc1 },
    bg: Color = .{ .r = 0x00, .g = 0x00, .b = 0x00 },
    attrs: Attributes = .{},

    pub const blank: Cell = .{};
};

pub const Attributes = struct {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    inverse: bool = false,
    blink: bool = false,
    strikethrough: bool = false,
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub var default_fg: Color = .{ .r = 0xc1, .g = 0xc1, .b = 0xc1 };
    pub var default_bg: Color = .{ .r = 0x00, .g = 0x00, .b = 0x00 };

    pub var base00: Color = .{ .r = 0x00, .g = 0x00, .b = 0x00 };
    pub var base01: Color = .{ .r = 0x12, .g = 0x12, .b = 0x12 };
    pub var base02: Color = .{ .r = 0x22, .g = 0x22, .b = 0x22 };
    pub var base03: Color = .{ .r = 0x33, .g = 0x33, .b = 0x33 };
    pub var base04: Color = .{ .r = 0x99, .g = 0x99, .b = 0x99 };
    pub var base05: Color = .{ .r = 0xc1, .g = 0xc1, .b = 0xc1 };
    pub var base06: Color = .{ .r = 0x99, .g = 0x99, .b = 0x99 };
    pub var base07: Color = .{ .r = 0xc1, .g = 0xc1, .b = 0xc1 };
    pub var base08: Color = .{ .r = 0x5f, .g = 0x87, .b = 0x87 };
    pub var base09: Color = .{ .r = 0xaa, .g = 0xaa, .b = 0xaa };
    pub var base0A: Color = .{ .r = 0x55, .g = 0x66, .b = 0x77 };
    pub var base0B: Color = .{ .r = 0x77, .g = 0x99, .b = 0xbb };
    pub var base0C: Color = .{ .r = 0xaa, .g = 0xaa, .b = 0xaa };
    pub var base0D: Color = .{ .r = 0x88, .g = 0x88, .b = 0x88 };
    pub var base0E: Color = .{ .r = 0x99, .g = 0x99, .b = 0x99 };
    pub var base0F: Color = .{ .r = 0x44, .g = 0x44, .b = 0x44 };

    pub var black: Color = .{ .r = 0x12, .g = 0x12, .b = 0x12 };
    pub var red: Color = .{ .r = 0x5f, .g = 0x87, .b = 0x87 };
    pub var green: Color = .{ .r = 0x77, .g = 0x99, .b = 0xbb };
    pub var yellow: Color = .{ .r = 0x55, .g = 0x66, .b = 0x77 };
    pub var blue: Color = .{ .r = 0x88, .g = 0x88, .b = 0x88 };
    pub var magenta: Color = .{ .r = 0x99, .g = 0x99, .b = 0x99 };
    pub var cyan: Color = .{ .r = 0xaa, .g = 0xaa, .b = 0xaa };
    pub var white: Color = .{ .r = 0xc1, .g = 0xc1, .b = 0xc1 };

    pub var bright_black: Color = .{ .r = 0x33, .g = 0x33, .b = 0x33 };
    pub var bright_red: Color = .{ .r = 0xaa, .g = 0xaa, .b = 0xaa };
    pub var bright_green: Color = .{ .r = 0x12, .g = 0x12, .b = 0x12 };
    pub var bright_yellow: Color = .{ .r = 0x22, .g = 0x22, .b = 0x22 };
    pub var bright_blue: Color = .{ .r = 0x99, .g = 0x99, .b = 0x99 };
    pub var bright_magenta: Color = .{ .r = 0x99, .g = 0x99, .b = 0x99 };
    pub var bright_cyan: Color = .{ .r = 0x44, .g = 0x44, .b = 0x44 };
    pub var bright_white: Color = .{ .r = 0xc1, .g = 0xc1, .b = 0xc1 };

    pub fn applyTheme(theme: *const Theme.Theme) void {
        const t = theme;
        base00 = from3(t.base00);
        base01 = from3(t.base01);
        base02 = from3(t.base02);
        base03 = from3(t.base03);
        base04 = from3(t.base04);
        base05 = from3(t.base05);
        base06 = from3(t.base06);
        base07 = from3(t.base07);
        base08 = from3(t.base08);
        base09 = from3(t.base09);
        base0A = from3(t.base0A);
        base0B = from3(t.base0B);
        base0C = from3(t.base0C);
        base0D = from3(t.base0D);
        base0E = from3(t.base0E);
        base0F = from3(t.base0F);
        default_fg = from3(t.foreground);
        default_bg = from3(t.background);

        black = base01;
        red = base08;
        green = base0B;
        yellow = base0A;
        blue = base0D;
        magenta = base0E;
        cyan = base0C;
        white = base05;
        bright_black = base03;
        bright_red = base09;
        bright_green = base01;
        bright_yellow = base02;
        bright_blue = base04;
        bright_magenta = base06;
        bright_cyan = base0F;
        bright_white = base07;
    }

    fn from3(c: Theme.Color3) Color {
        return .{ .r = c[0], .g = c[1], .b = c[2] };
    }

    pub fn ansi(idx: u8) Color {
        return switch (idx) {
            0 => black,
            1 => red,
            2 => green,
            3 => yellow,
            4 => blue,
            5 => magenta,
            6 => cyan,
            7 => white,
            8 => bright_black,
            9 => bright_red,
            10 => bright_green,
            11 => bright_yellow,
            12 => bright_blue,
            13 => bright_magenta,
            14 => bright_cyan,
            15 => bright_white,
            else => default_fg,
        };
    }

    pub fn toFloats(self: Color) [3]f32 {
        return .{
            @as(f32, @floatFromInt(self.r)) / 255.0,
            @as(f32, @floatFromInt(self.g)) / 255.0,
            @as(f32, @floatFromInt(self.b)) / 255.0,
        };
    }

    pub fn toArray(self: Color) [3]u8 {
        return .{ self.r, self.g, self.b };
    }
};
