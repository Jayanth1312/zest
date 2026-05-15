const std = @import("std");

pub const Command = enum {
    splitHorizontal,
    splitVertical,
    closePane,
    focusUp,
    focusDown,
    focusLeft,
    focusRight,
    toggleExplorer,
    explorerUp,
    explorerDown,
    explorerSelect,
    explorerCtrlSelect,
    explorerBack,
    explorerSearch,
    explorerSearchFiles,
    explorerSearchDirs,
    explorerCancelSearch,
    explorerSearchChar,
    explorerSearchBackspace,
    none,
};

pub const KeyBindings = struct {
    pub fn handleDirectShortcut(keyval: u32, ctrl: bool, shift: bool, alt: bool) Command {
        if (ctrl and shift and !alt) {
            return switch (keyval) {
                'h', 'H' => .splitHorizontal,
                'j', 'J' => .splitVertical,
                'x', 'X' => .closePane,
                'e', 'E' => .toggleExplorer,
                0xFF51 => .focusLeft,
                0xFF52 => .focusUp,
                0xFF53 => .focusRight,
                0xFF54 => .focusDown,
                else => .none,
            };
        }
        return .none;
    }

    pub fn handleExplorerKey(keyval: u32, ctrl: bool, shift: bool, alt: bool) Command {
        _ = shift;
        _ = alt;
        if (ctrl and keyval == 0xFF0D) {
            return .explorerCtrlSelect;
        }
        return switch (keyval) {
            0xFF52, 0x6B => .explorerUp,
            0xFF54, 0x6A => .explorerDown,
            0xFF0D, 0xFF8D => .explorerSelect,
            0xFF08 => .explorerBack,
            0xFF1B => .explorerCancelSearch,
            0x2F => .explorerSearch,
            0x40 => .explorerSearchFiles,
            0x23 => .explorerSearchDirs,
            else => .none,
        };
    }

    pub fn handleExplorerChar(keyval: u32) ?u8 {
        if (keyval >= 0x20 and keyval < 0x7F) {
            return @intCast(keyval);
        }
        return null;
    }
};