const CUInt = u32;

pub const GdkModifierType = CUInt;
pub const GDK_SHIFT_MASK: CUInt = 1 << 0;
pub const GDK_CONTROL_MASK: CUInt = 1 << 2;
pub const GDK_ALT_MASK: CUInt = 1 << 3;
pub const GDK_SUPER_MASK: CUInt = 1 << 26;

pub const GDK_KEY_BackSpace: CUInt = 0xff08;
pub const GDK_KEY_Tab: CUInt = 0xff09;
pub const GDK_KEY_Return: CUInt = 0xff0d;
pub const GDK_KEY_Escape: CUInt = 0xff1b;
pub const GDK_KEY_Home: CUInt = 0xff50;
pub const GDK_KEY_Left: CUInt = 0xff51;
pub const GDK_KEY_Up: CUInt = 0xff52;
pub const GDK_KEY_Right: CUInt = 0xff53;
pub const GDK_KEY_Down: CUInt = 0xff54;
pub const GDK_KEY_Page_Up: CUInt = 0xff55;
pub const GDK_KEY_Page_Down: CUInt = 0xff56;
pub const GDK_KEY_End: CUInt = 0xff57;
pub const GDK_KEY_Insert: CUInt = 0xff63;
pub const GDK_KEY_KP_Enter: CUInt = 0xff8d;
pub const GDK_KEY_Delete: CUInt = 0xffff;
pub const GDK_KEY_F1: CUInt = 0xffbe;
pub const GDK_KEY_F2: CUInt = 0xffbf;
pub const GDK_KEY_F3: CUInt = 0xffc0;
pub const GDK_KEY_F4: CUInt = 0xffc1;
pub const GDK_KEY_F5: CUInt = 0xffc2;
pub const GDK_KEY_F6: CUInt = 0xffc3;
pub const GDK_KEY_F7: CUInt = 0xffc4;
pub const GDK_KEY_F8: CUInt = 0xffc5;
pub const GDK_KEY_F9: CUInt = 0xffc6;
pub const GDK_KEY_F10: CUInt = 0xffc7;
pub const GDK_KEY_F11: CUInt = 0xffc8;
pub const GDK_KEY_F12: CUInt = 0xffc9;
pub const GDK_KEY_ISO_Left_Tab: CUInt = 0xfe20;

pub const Mods = struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,
};

pub fn translateMods(state: GdkModifierType) Mods {
    return .{
        .shift = (state & GDK_SHIFT_MASK) != 0,
        .ctrl = (state & GDK_CONTROL_MASK) != 0,
        .alt = (state & GDK_ALT_MASK) != 0,
        .super = (state & GDK_SUPER_MASK) != 0,
    };
}

pub fn keyToSequence(keyval: CUInt, mods: Mods) ?[]const u8 {
    const is_ctrl = mods.ctrl;
    const is_shift = mods.shift;
    const is_alt = mods.alt;

    if (is_ctrl and is_shift) return null;

    if (is_ctrl and !is_alt and keyval >= 'a' and keyval <= 'z') {
        const buf = &ctrl_buf;
        buf[0] = @intCast(keyval - 'a' + 1);
        return buf[0..1];
    }
    if (is_ctrl and !is_alt and keyval >= 'A' and keyval <= 'Z') {
        const buf = &ctrl_buf;
        buf[0] = @intCast(keyval - 'A' + 1);
        return buf[0..1];
    }

    if (is_alt) {
        switch (keyval) {
            GDK_KEY_Return, GDK_KEY_KP_Enter => return "\x1B\r",
            GDK_KEY_BackSpace => return "\x1B\x08",
            GDK_KEY_Tab => return "\x1B\t",
            GDK_KEY_ISO_Left_Tab => return "\x1B\t",
            GDK_KEY_Escape => return "\x1B\x1B",
            GDK_KEY_Up => return "\x1B\x1B[A",
            GDK_KEY_Down => return "\x1B\x1B[B",
            GDK_KEY_Right => return "\x1B\x1B[C",
            GDK_KEY_Left => return "\x1B\x1B[D",
            GDK_KEY_Home => return "\x1B\x1B[1~",
            GDK_KEY_End => return "\x1B\x1B[4~",
            GDK_KEY_Page_Up => return "\x1B\x1B[5~",
            GDK_KEY_Page_Down => return "\x1B\x1B[6~",
            GDK_KEY_Insert => return "\x1B\x1B[2~",
            GDK_KEY_Delete => return "\x1B\x1B[3~",
            GDK_KEY_F1 => return "\x1B\x1BOP",
            GDK_KEY_F2 => return "\x1B\x1BOQ",
            GDK_KEY_F3 => return "\x1B\x1BOR",
            GDK_KEY_F4 => return "\x1B\x1BOS",
            GDK_KEY_F5 => return "\x1B\x1B[15~",
            GDK_KEY_F6 => return "\x1B\x1B[17~",
            GDK_KEY_F7 => return "\x1B\x1B[18~",
            GDK_KEY_F8 => return "\x1B\x1B[19~",
            GDK_KEY_F9 => return "\x1B\x1B[20~",
            GDK_KEY_F10 => return "\x1B\x1B[21~",
            GDK_KEY_F11 => return "\x1B\x1B[23~",
            GDK_KEY_F12 => return "\x1B\x1B[24~",
            else => return null,
        }
    }

    switch (keyval) {
        GDK_KEY_Return, GDK_KEY_KP_Enter => return "\r",
        GDK_KEY_BackSpace => return "\x08",
        GDK_KEY_Tab => return "\t",
        GDK_KEY_ISO_Left_Tab => return "\t",
        GDK_KEY_Escape => return "\x1B",
        GDK_KEY_Up => return "\x1B[A",
        GDK_KEY_Down => return "\x1B[B",
        GDK_KEY_Right => return "\x1B[C",
        GDK_KEY_Left => return "\x1B[D",
        GDK_KEY_Home => return "\x1B[1~",
        GDK_KEY_End => return "\x1B[4~",
        GDK_KEY_Page_Up => return "\x1B[5~",
        GDK_KEY_Page_Down => return "\x1B[6~",
        GDK_KEY_Insert => return "\x1B[2~",
        GDK_KEY_Delete => return "\x1B[3~",
        GDK_KEY_F1 => return "\x1BOP",
        GDK_KEY_F2 => return "\x1BOQ",
        GDK_KEY_F3 => return "\x1BOR",
        GDK_KEY_F4 => return "\x1BOS",
        GDK_KEY_F5 => return "\x1B[15~",
        GDK_KEY_F6 => return "\x1B[17~",
        GDK_KEY_F7 => return "\x1B[18~",
        GDK_KEY_F8 => return "\x1B[19~",
        GDK_KEY_F9 => return "\x1B[20~",
        GDK_KEY_F10 => return "\x1B[21~",
        GDK_KEY_F11 => return "\x1B[23~",
        GDK_KEY_F12 => return "\x1B[24~",
        else => return null,
    }
}

var ctrl_buf: [1]u8 = undefined;