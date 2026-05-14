const std = @import("std");

pub const Command = enum {
    splitHorizontal,
    splitVertical,
    closePane,
    focusUp,
    focusDown,
    focusLeft,
    focusRight,
    none,
};

pub const KeyBindings = struct {
    pub fn handleDirectShortcut(keyval: u32, ctrl: bool, shift: bool, alt: bool) Command {
        if (ctrl and shift and !alt) {
            return switch (keyval) {
                'h', 'H' => .splitHorizontal,
                'j', 'J' => .splitVertical,
                'w', 'W' => .closePane,
                0xFF51 => .focusLeft,
                0xFF52 => .focusUp,
                0xFF53 => .focusRight,
                0xFF54 => .focusDown,
                else => .none,
            };
        }
        return .none;
    }
};