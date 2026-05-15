/// zest Cell — single character cell in the terminal grid.
/// Theme: Black Metal (Immortal) by metalelf0
const std = @import("std");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    // Black Metal (Immortal) theme
    pub const default_fg = Color{ .r = 0xc1, .g = 0xc1, .b = 0xc1 }; // base05
    pub const default_bg = Color{ .r = 0x00, .g = 0x00, .b = 0x00 }; // base00

    // Base16 palette
    pub const base00 = Color{ .r = 0x00, .g = 0x00, .b = 0x00 };
    pub const base01 = Color{ .r = 0x12, .g = 0x12, .b = 0x12 };
    pub const base02 = Color{ .r = 0x22, .g = 0x22, .b = 0x22 };
    pub const base03 = Color{ .r = 0x33, .g = 0x33, .b = 0x33 };
    pub const base04 = Color{ .r = 0x99, .g = 0x99, .b = 0x99 };
    pub const base05 = Color{ .r = 0xc1, .g = 0xc1, .b = 0xc1 };
    pub const base06 = Color{ .r = 0x99, .g = 0x99, .b = 0x99 };
    pub const base07 = Color{ .r = 0xc1, .g = 0xc1, .b = 0xc1 };
    pub const base08 = Color{ .r = 0x5f, .g = 0x87, .b = 0x87 }; // teal
    pub const base09 = Color{ .r = 0xaa, .g = 0xaa, .b = 0xaa };
    pub const base0A = Color{ .r = 0x55, .g = 0x66, .b = 0x77 }; // dark steel
    pub const base0B = Color{ .r = 0x77, .g = 0x99, .b = 0xbb }; // steel blue
    pub const base0C = Color{ .r = 0xaa, .g = 0xaa, .b = 0xaa };
    pub const base0D = Color{ .r = 0x88, .g = 0x88, .b = 0x88 };
    pub const base0E = Color{ .r = 0x99, .g = 0x99, .b = 0x99 };
    pub const base0F = Color{ .r = 0x44, .g = 0x44, .b = 0x44 };

    // ANSI color mapping using Black Metal Immortal
    pub const black = base01;
    pub const red = base08;       // teal-ish
    pub const green = base0B;     // steel blue
    pub const yellow = base0A;    // dark steel
    pub const blue = base0D;      // grey
    pub const magenta = base0E;   // light grey
    pub const cyan = base0C;      // grey
    pub const white = base05;     // light

    // Bright variants (Base16 standard mapping)
    pub const bright_black = base03;
    pub const bright_red = base09;
    pub const bright_green = base01;
    pub const bright_yellow = base02;
    pub const bright_blue = base04;
    pub const bright_magenta = base06;
    pub const bright_cyan = base0F;
    pub const bright_white = base07;

    /// Look up standard ANSI color by index (0-15).
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
            @as(f32, @floatFromInt(self.r)) * (1.0 / 255.0),
            @as(f32, @floatFromInt(self.g)) * (1.0 / 255.0),
            @as(f32, @floatFromInt(self.b)) * (1.0 / 255.0),
        };
    }

    pub fn toFloatsFast(color: Color) [3]f32 {
        const inv = 1.0 / 255.0;
        return .{
            @as(f32, @floatFromInt(color.r)) * inv,
            @as(f32, @floatFromInt(color.g)) * inv,
            @as(f32, @floatFromInt(color.b)) * inv,
        };
    }
};

pub const Attributes = packed struct {
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    strikethrough: bool = false,
    dim: bool = false,
    inverse: bool = false,
    blink: bool = false,
    _padding: u1 = 0,
};

pub const Cell = struct {
    char: u21 = ' ',
    fg: Color = Color.default_fg,
    bg: Color = Color.default_bg,
    attrs: Attributes = .{},

    pub const blank = Cell{};
};
