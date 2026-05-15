/// zest Terminal — VTE state machine + ANSI parser.
/// Handles escape sequences, cursor movement, colors, scrolling, erase operations.
const std = @import("std");
const Grid = @import("Grid.zig");
const Cell = @import("Cell.zig");

pub const Pos = struct {
    col: u32,
    row: u32,
};

const ParserState = enum {
    ground,
    escape,
    csi_entry,
    csi_param,
    osc_string,
    charset,
};

pub const Terminal = struct {
    grid: Grid.Grid,
    cols: u32,
    rows: u32,
    cursor_col: u32,
    cursor_row: u32,
    saved_cursor_col: u32,
    saved_cursor_row: u32,
    scroll_top: u32,
    scroll_bottom: u32,
    current_fg: Cell.Color,
    current_bg: Cell.Color,
    current_attrs: Cell.Attributes,
    state: ParserState,
    params: [16]u16,
    param_count: u8,
    csi_private: bool,
    utf8_buf: [4]u8,
    utf8_len: u8,
    utf8_expected: u8,
    allocator: std.mem.Allocator,

    selection_start: ?Pos = null,
    selection_end: ?Pos = null,
    selection_active: bool = false,
    bracketed_paste_mode: bool = false,
    cursor_key_mode: bool = false,

    alt_screen_grid: ?Grid.Grid = null,
    using_alt_screen: bool = false,

    osc_buf: [256]u8 = undefined,
    osc_len: usize = 0,
    osc_num: u8 = 0,

    command_history: std.ArrayListUnmanaged([]u8) = .empty,
    max_history: usize = 200,

    pub fn init(allocator: std.mem.Allocator, cols: u32, rows: u32) !Terminal {
        return Terminal{
            .grid = try Grid.Grid.init(allocator, cols, rows),
            .cols = cols,
            .rows = rows,
            .cursor_col = 0,
            .cursor_row = 0,
            .saved_cursor_col = 0,
            .saved_cursor_row = 0,
            .scroll_top = 0,
            .scroll_bottom = rows - 1,
            .current_fg = Cell.Color.default_fg,
            .current_bg = Cell.Color.default_bg,
            .current_attrs = .{},
            .state = .ground,
            .params = std.mem.zeroes([16]u16),
            .param_count = 0,
            .csi_private = false,
            .utf8_buf = undefined,
            .utf8_len = 0,
            .utf8_expected = 0,
            .allocator = allocator,
            .osc_buf = undefined,
            .osc_len = 0,
            .osc_num = 0,
        };
    }

    pub fn deinit(self: *Terminal) void {
        self.grid.deinit();
        if (self.alt_screen_grid) |*alt| {
            alt.deinit();
        }
        for (self.command_history.items) |cmd| {
            self.allocator.free(cmd);
        }
        self.command_history.deinit(self.allocator);
    }

    /// Feed raw bytes from PTY into the parser.
    pub fn feed(self: *Terminal, data: []const u8) void {
        for (data) |byte| {
            self.processByte(byte);
        }
    }

    fn processByte(self: *Terminal, byte: u8) void {
        if (byte == 0x1B) {
            if (self.state == .osc_string) {
                self.finishOsc();
            }
            self.state = .escape;
            return;
        }

        switch (byte) {
            0x07 => {
                if (self.state == .osc_string) {
                    self.finishOsc();
                }
                return;
            },
            0x08 => {
                if (self.cursor_col > 0) self.cursor_col -= 1;
                return;
            },
            0x09 => {
                self.cursor_col = @min(self.cols - 1, (self.cursor_col + 8) & ~@as(u32, 7));
                return;
            },
            0x0A, 0x0B, 0x0C => {
                self.lineFeed();
                return;
            },
            0x0D => {
                self.cursor_col = 0;
                return;
            },
            else => {},
        }

        switch (self.state) {
            .ground => self.processGround(byte),
            .escape => self.processEscape(byte),
            .csi_entry => self.processCsiEntry(byte),
            .csi_param => self.processCsiParam(byte),
            .osc_string => self.processOsc(byte),
            .charset => {
                self.state = .ground;
            },
        }
    }

    fn processGround(self: *Terminal, byte: u8) void {
        if (byte >= 0x20 and byte < 0x7F) {
            self.putChar(byte);
        } else if (byte >= 0x80) {
            if (self.utf8_expected == 0) {
                // First byte of a UTF-8 sequence
                self.utf8_buf[0] = byte;
                self.utf8_len = 1;
                if (byte & 0xE0 == 0xC0) {
                    self.utf8_expected = 2;
                } else if (byte & 0xF0 == 0xE0) {
                    self.utf8_expected = 3;
                } else if (byte & 0xF8 == 0xF0) {
                    self.utf8_expected = 4;
                } else {
                    // Invalid, just print replacement or ignore
                    self.utf8_expected = 0;
                }
            } else {
                // Continuation byte
                self.utf8_buf[self.utf8_len] = byte;
                self.utf8_len += 1;
                if (self.utf8_len == self.utf8_expected) {
                    // Decode and putChar
                    const codepoint = std.unicode.utf8Decode(self.utf8_buf[0..self.utf8_len]) catch 0xFFFD;
                    self.putChar(codepoint);
                    self.utf8_expected = 0;
                }
            }
        }
    }

    fn processEscape(self: *Terminal, byte: u8) void {
        switch (byte) {
            '[' => {
                self.state = .csi_entry;
                self.param_count = 0;
                self.csi_private = false;
                @memset(&self.params, 0);
            },
            ']' => {
                self.state = .osc_string;
                self.osc_len = 0;
                self.osc_num = 0;
            },
            'P', '_', '^', 'X' => {
                self.state = .osc_string;
                self.osc_len = 0;
            },
            'D' => {
                self.lineFeed();
                self.state = .ground;
            },
            'E' => {
                self.cursor_col = 0;
                self.lineFeed();
                self.state = .ground;
            },
            'M' => {
                self.reverseIndex();
                self.state = .ground;
            },
            '7' => {
                self.saved_cursor_col = self.cursor_col;
                self.saved_cursor_row = self.cursor_row;
                self.state = .ground;
            },
            '8' => {
                self.cursor_col = self.saved_cursor_col;
                self.cursor_row = self.saved_cursor_row;
                self.state = .ground;
            },
            '(', ')', '*', '+' => {
                self.state = .charset;
            },
            '\\', 'c' => {
                self.state = .ground;
            },
            else => {
                self.state = .ground;
            },
        }
    }

    fn processCsiEntry(self: *Terminal, byte: u8) void {
        if (byte >= 0x20 and byte <= 0x3F) {
            if (byte == '?') {
                self.csi_private = true;
            } else if (byte >= '0' and byte <= '9') {
                self.params[0] = self.params[0] * 10 + @as(u16, byte - '0');
                self.param_count = @max(self.param_count, 1);
            }
            self.state = .csi_param;
        } else if (byte >= 0x40 and byte <= 0x7E) {
            // dispatch
            self.param_count = 0;
            self.dispatchCsi(byte);
        }
    }

    fn processCsiParam(self: *Terminal, byte: u8) void {
        if (byte >= 0x20 and byte <= 0x3F) {
            if (byte >= '0' and byte <= '9') {
                const idx = if (self.param_count == 0) 0 else self.param_count - 1;
                self.params[@min(idx, 15)] = self.params[@min(idx, 15)] * 10 + @as(u16, byte - '0');
                if (self.param_count == 0) self.param_count = 1;
            } else if (byte == ';') {
                if (self.param_count < 16) self.param_count += 1;
            }
        } else if (byte >= 0x40 and byte <= 0x7E) {
            self.dispatchCsi(byte);
        }
    }

    fn processOsc(self: *Terminal, byte: u8) void {
        if (self.osc_len < self.osc_buf.len) {
            self.osc_buf[self.osc_len] = byte;
            self.osc_len += 1;
        }
    }

    fn finishOsc(self: *Terminal) void {
        self.state = .ground;
        if (self.osc_len == 0) return;

        // Parse OSC number (e.g., "0;" for title, "1;" for icon)
        var num_end: usize = 0;
        while (num_end < self.osc_len and self.osc_buf[num_end] != ';') : (num_end += 1) {}
        if (num_end >= self.osc_len) return;

        self.osc_num = std.fmt.parseInt(u8, self.osc_buf[0..num_end], 10) catch return;
        const payload = self.osc_buf[num_end + 1 .. self.osc_len];

        // OSC 0, 1, 2: set window/icon title (we just ignore for now)
        _ = self.osc_num;
        _ = payload;
    }

    fn dispatchCsi(self: *Terminal, cmd: u8) void {
        self.state = .ground;
        const p0 = if (self.param_count > 0) self.params[0] else 0;
        const p1 = if (self.param_count > 1) self.params[1] else 0;

        if (self.csi_private) {
            switch (cmd) {
                'h' => { // DECSET
                    switch (p0) {
                        1 => self.cursor_key_mode = true,
                        2004 => self.bracketed_paste_mode = true,
                        1049 => self.enterAltScreen(),
                        else => {},
                    }
                },
                'l' => { // DECRST
                    switch (p0) {
                        1 => self.cursor_key_mode = false,
                        2004 => self.bracketed_paste_mode = false,
                        1049 => self.exitAltScreen(),
                        else => {},
                    }
                },
                else => {},
            }
            return;
        }

        switch (cmd) {
            'A' => { // CUU — Cursor Up
                const n = if (p0 == 0) 1 else p0;
                self.cursor_row -|= @as(u32, n);
                if (self.cursor_row < self.scroll_top) self.cursor_row = self.scroll_top;
            },
            'B' => { // CUD — Cursor Down
                const n = if (p0 == 0) 1 else p0;
                self.cursor_row = @min(self.cursor_row + @as(u32, n), self.scroll_bottom);
            },
            'C' => { // CUF — Cursor Forward
                const n = if (p0 == 0) 1 else p0;
                self.cursor_col = @min(self.cursor_col + @as(u32, n), self.cols - 1);
            },
            'D' => { // CUB — Cursor Back
                const n = if (p0 == 0) 1 else p0;
                self.cursor_col -|= @as(u32, n);
            },
            'G' => { // CHA — Cursor Horizontal Absolute
                const col = if (p0 == 0) 1 else p0;
                self.cursor_col = @min(@as(u32, col) -| 1, self.cols - 1);
            },
            'H', 'f' => { // CUP — Cursor Position
                const row = if (p0 == 0) 1 else p0;
                const col = if (p1 == 0) 1 else p1;
                self.cursor_row = @min(@as(u32, row) -| 1, self.rows - 1);
                self.cursor_col = @min(@as(u32, col) -| 1, self.cols - 1);
            },
            'J' => { // ED — Erase in Display
                switch (p0) {
                    0 => self.eraseCursorToEnd(),
                    1 => self.eraseStartToCursor(),
                    2, 3 => self.grid.clear(self.currentFillCell()),
                    else => {},
                }
            },
            'K' => { // EL — Erase in Line
                switch (p0) {
                    0 => self.eraseCursorToEol(),
                    1 => self.eraseBolToCursor(),
                    2 => self.eraseEntireLine(),
                    else => {},
                }
            },
            'L' => { // IL — Insert Lines
                const n = if (p0 == 0) 1 else @as(u32, p0);
                self.insertLines(n);
            },
            'M' => { // DL — Delete Lines
                const n = if (p0 == 0) 1 else @as(u32, p0);
                self.deleteLines(n);
            },
            'P' => { // DCH — Delete Characters
                const n = if (p0 == 0) 1 else @as(u32, p0);
                self.deleteChars(n);
            },
            'd' => { // VPA — Vertical Position Absolute
                const row = if (p0 == 0) 1 else p0;
                self.cursor_row = @min(@as(u32, row) -| 1, self.rows - 1);
            },
            'm' => self.handleSgr(), // SGR — Select Graphic Rendition
            'r' => { // DECSTBM — Set Scrolling Region
                const top = if (p0 == 0) 1 else p0;
                const bot = if (p1 == 0) @as(u16, @intCast(self.rows)) else p1;
                self.scroll_top = @as(u32, top) -| 1;
                self.scroll_bottom = @min(@as(u32, bot) -| 1, self.rows - 1);
                self.cursor_col = 0;
                self.cursor_row = self.scroll_top;
            },
            '@' => { // ICH — Insert Characters
                const n = if (p0 == 0) 1 else @as(u32, p0);
                self.insertChars(n);
            },
            else => {}, // Unhandled
        }
    }

    fn handleSgr(self: *Terminal) void {
        if (self.param_count == 0) {
            self.resetAttrs();
            return;
        }
        var i: u8 = 0;
        while (i < self.param_count) : (i += 1) {
            const p = self.params[i];
            switch (p) {
                0 => self.resetAttrs(),
                1 => self.current_attrs.bold = true,
                2 => self.current_attrs.dim = true,
                3 => self.current_attrs.italic = true,
                4 => self.current_attrs.underline = true,
                7 => self.current_attrs.inverse = true,
                5 => self.current_attrs.blink = true,
                9 => self.current_attrs.strikethrough = true,
                22 => {
                    self.current_attrs.bold = false;
                    self.current_attrs.dim = false;
                },
                23 => self.current_attrs.italic = false,
                24 => self.current_attrs.underline = false,
                27 => self.current_attrs.inverse = false,
                25 => self.current_attrs.blink = false,
                29 => self.current_attrs.strikethrough = false,
                30...37 => self.current_fg = Cell.Color.ansi(@intCast(p - 30)),
                38 => {
                    if (i + 1 < self.param_count and self.params[i + 1] == 5 and i + 2 < self.param_count) {
                        // 256-color: ESC[38;5;Nm
                        self.current_fg = color256(self.params[i + 2]);
                        i += 2;
                    } else if (i + 1 < self.param_count and self.params[i + 1] == 2 and i + 4 < self.param_count) {
                        // 24-bit: ESC[38;2;R;G;Bm
                        self.current_fg = Cell.Color{
                            .r = @intCast(self.params[i + 2]),
                            .g = @intCast(self.params[i + 3]),
                            .b = @intCast(self.params[i + 4]),
                        };
                        i += 4;
                    }
                },
                39 => self.current_fg = Cell.Color.default_fg,
                40...47 => self.current_bg = Cell.Color.ansi(@intCast(p - 40)),
                48 => {
                    if (i + 1 < self.param_count and self.params[i + 1] == 5 and i + 2 < self.param_count) {
                        self.current_bg = color256(self.params[i + 2]);
                        i += 2;
                    } else if (i + 1 < self.param_count and self.params[i + 1] == 2 and i + 4 < self.param_count) {
                        self.current_bg = Cell.Color{
                            .r = @intCast(self.params[i + 2]),
                            .g = @intCast(self.params[i + 3]),
                            .b = @intCast(self.params[i + 4]),
                        };
                        i += 4;
                    }
                },
                49 => self.current_bg = Cell.Color.default_bg,
                90...97 => self.current_fg = Cell.Color.ansi(@intCast(p - 90 + 8)),
                100...107 => self.current_bg = Cell.Color.ansi(@intCast(p - 100 + 8)),
                else => {},
            }
        }
    }

    fn resetAttrs(self: *Terminal) void {
        self.current_fg = Cell.Color.default_fg;
        self.current_bg = Cell.Color.default_bg;
        self.current_attrs = .{};
    }

    pub fn isWide(char: u21) bool {
        if (char >= 0x1100 and (char <= 0x115F or char == 0x2329 or char == 0x232A or (char >= 0x2E80 and char <= 0xA4CF and char != 0x303F) or (char >= 0xAC00 and char <= 0xD7A3) or (char >= 0xF900 and char <= 0xFAFF) or (char >= 0xFE10 and char <= 0xFE19) or (char >= 0xFE30 and char <= 0xFE6F) or (char >= 0xFF00 and char <= 0xFF60) or (char >= 0xFFE0 and char <= 0xFFE6) or (char >= 0x20000 and char <= 0x2FFFD) or (char >= 0x30000 and char <= 0x3FFFD))) return true;
        if (char >= 0x1F300 and char <= 0x1F9FF) return true;
        return false;
    }

    pub fn isEmoji(char: u21) bool {
        if (char >= 0x1F600 and char <= 0x1F64F) return true;
        if (char >= 0x1F300 and char <= 0x1F5FF) return true;
        if (char >= 0x1F680 and char <= 0x1F6FF) return true;
        if (char >= 0x1F900 and char <= 0x1F9FF) return true;
        if (char >= 0x1FA00 and char <= 0x1FA6F) return true;
        if (char >= 0x1FA70 and char <= 0x1FAFF) return true;
        if (char >= 0x2600 and char <= 0x26FF) return true;
        if (char >= 0x2700 and char <= 0x27BF) return true;
        if (char >= 0xFE00 and char <= 0xFE0F) return true;
        if (char >= 0x1F1E0 and char <= 0x1F1FF) return true;
        if (char >= 0x1F004 and char <= 0x1F004) return true;
        if (char >= 0x1F0CF and char <= 0x1F0CF) return true;
        if (char >= 0x1F170 and char <= 0x1F171) return true;
        if (char >= 0x1F17E and char <= 0x1F17F) return true;
        if (char >= 0x1F18E and char <= 0x1F18E) return true;
        if (char >= 0x1F191 and char <= 0x1F19A) return true;
        if (char >= 0x1F201 and char <= 0x1F202) return true;
        if (char >= 0x1F21A and char <= 0x1F21A) return true;
        if (char >= 0x1F22F and char <= 0x1F22F) return true;
        if (char >= 0x1F232 and char <= 0x1F23A) return true;
        if (char >= 0x1F250 and char <= 0x1F251) return true;
        if (char >= 0x1F300 and char <= 0x1F320) return true;
        if (char >= 0x1F32D and char <= 0x1F335) return true;
        if (char >= 0x1F337 and char <= 0x1F37C) return true;
        if (char >= 0x1F37E and char <= 0x1F393) return true;
        if (char >= 0x1F3A0 and char <= 0x1F3CA) return true;
        if (char >= 0x1F3CF and char <= 0x1F3D3) return true;
        if (char >= 0x1F3E0 and char <= 0x1F3F0) return true;
        if (char >= 0x1F3F4 and char <= 0x1F3F4) return true;
        if (char >= 0x1F3F8 and char <= 0x1F43E) return true;
        if (char >= 0x1F440 and char <= 0x1F440) return true;
        if (char >= 0x1F442 and char <= 0x1F4FC) return true;
        if (char >= 0x1F4FF and char <= 0x1F53D) return true;
        if (char >= 0x1F54B and char <= 0x1F54E) return true;
        if (char >= 0x1F550 and char <= 0x1F567) return true;
        if (char >= 0x1F57A and char <= 0x1F57A) return true;
        if (char >= 0x1F595 and char <= 0x1F596) return true;
        if (char >= 0x1F5A4 and char <= 0x1F5A4) return true;
        if (char >= 0x1F5FB and char <= 0x1F64F) return true;
        if (char >= 0x1F680 and char <= 0x1F6C5) return true;
        if (char >= 0x1F6CC and char <= 0x1F6CC) return true;
        if (char >= 0x1F6D0 and char <= 0x1F6D2) return true;
        if (char >= 0x1F6D5 and char <= 0x1F6D7) return true;
        if (char >= 0x1F6EB and char <= 0x1F6EC) return true;
        if (char >= 0x1F6F4 and char <= 0x1F6FC) return true;
        if (char >= 0x1F7E0 and char <= 0x1F7EB) return true;
        if (char >= 0x1F90C and char <= 0x1F93A) return true;
        if (char >= 0x1F93C and char <= 0x1F945) return true;
        if (char >= 0x1F947 and char <= 0x1F9FF) return true;
        if (char >= 0x1FA70 and char <= 0x1FA7C) return true;
        if (char >= 0x1FA80 and char <= 0x1FA88) return true;
        if (char >= 0x1FA90 and char <= 0x1FABD) return true;
        if (char >= 0x1FABF and char <= 0x1FAC5) return true;
        if (char >= 0x1FACE and char <= 0x1FADB) return true;
        if (char >= 0x1FAE0 and char <= 0x1FAE8) return true;
        if (char >= 0x1FAF0 and char <= 0x1FAF8) return true;
        return false;
    }

    fn putChar(self: *Terminal, char: u21) void {
        const wide = isWide(char);
        if (self.cursor_col >= self.cols or (wide and self.cursor_col >= self.cols - 1)) {
            self.cursor_col = 0;
            self.lineFeed();
        }
        self.grid.setCellAt(self.cursor_col, self.cursor_row, .{
            .char = char,
            .fg = self.current_fg,
            .bg = self.current_bg,
            .attrs = self.current_attrs,
        });
        if (wide) {
            self.cursor_col += 1;
            // Place a special character or just advance to mark the second half
            self.grid.setCellAt(self.cursor_col, self.cursor_row, .{
                .char = 0, // 0 as a placeholder for wide-char right half
                .fg = self.current_fg,
                .bg = self.current_bg,
                .attrs = self.current_attrs,
            });
        }
        self.cursor_col += 1;
    }

    fn lineFeed(self: *Terminal) void {
        if (self.cursor_row >= self.scroll_bottom) {
            self.scrollUp(1);
        } else {
            self.cursor_row += 1;
        }
    }

    fn reverseIndex(self: *Terminal) void {
        if (self.cursor_row <= self.scroll_top) {
            self.scrollDown(1);
        } else {
            self.cursor_row -= 1;
        }
    }

    fn scrollUp(self: *Terminal, count: u32) void {
        self.grid.scrollRegionUp(self.scroll_top, self.scroll_bottom, count, self.currentFillCell());
    }

    fn scrollDown(self: *Terminal, count: u32) void {
        self.grid.scrollRegionDown(self.scroll_top, self.scroll_bottom, count, self.currentFillCell());
    }

    fn currentFillCell(self: *Terminal) Cell.Cell {
        return .{
            .char = ' ',
            .fg = self.current_fg,
            .bg = self.current_bg,
            .attrs = .{},
        };
    }

    fn eraseCursorToEnd(self: *Terminal) void {
        self.eraseCursorToEol();
        const fill = self.currentFillCell();
        var row = self.cursor_row + 1;
        while (row < self.rows) : (row += 1) {
            const phys_row = self.grid.row_indices[@as(usize, row)];
            const start = @as(usize, phys_row) * self.grid.cols;
            @memset(self.grid.cells[start .. start + self.grid.cols], fill);
        }
    }

    fn eraseStartToCursor(self: *Terminal) void {
        self.eraseBolToCursor();
        const fill = self.currentFillCell();
        var row: u32 = 0;
        while (row < self.cursor_row) : (row += 1) {
            const phys_row = self.grid.row_indices[@as(usize, row)];
            const start = @as(usize, phys_row) * self.grid.cols;
            @memset(self.grid.cells[start .. start + self.grid.cols], fill);
        }
    }

    fn eraseCursorToEol(self: *Terminal) void {
        const fill = self.currentFillCell();
        const phys_row = self.grid.row_indices[@as(usize, self.cursor_row)];
        const start = @as(usize, phys_row) * self.grid.cols + @as(usize, self.cursor_col);
        const end = @as(usize, phys_row) * self.grid.cols + @as(usize, self.grid.cols);
        @memset(self.grid.cells[start..end], fill);
    }

    fn eraseBolToCursor(self: *Terminal) void {
        const fill = self.currentFillCell();
        const phys_row = self.grid.row_indices[@as(usize, self.cursor_row)];
        const start = @as(usize, phys_row) * self.grid.cols;
        const end = start + @as(usize, self.cursor_col) + 1;
        @memset(self.grid.cells[start..end], fill);
    }

    fn eraseEntireLine(self: *Terminal) void {
        const phys_row = self.grid.row_indices[@as(usize, self.cursor_row)];
        const start = @as(usize, phys_row) * self.grid.cols;
        @memset(self.grid.cells[start .. start + self.grid.cols], Cell.Cell.blank);
    }

    fn insertLines(self: *Terminal, count: u32) void {
        if (self.cursor_row < self.scroll_top or self.cursor_row > self.scroll_bottom) return;
        self.grid.scrollRegionDown(self.cursor_row, self.scroll_bottom, count, self.currentFillCell());
    }

    fn deleteLines(self: *Terminal, count: u32) void {
        if (self.cursor_row < self.scroll_top or self.cursor_row > self.scroll_bottom) return;
        self.grid.scrollRegionUp(self.cursor_row, self.scroll_bottom, count, self.currentFillCell());
    }

    fn deleteChars(self: *Terminal, count: u32) void {
        const n = @min(count, self.cols - self.cursor_col);
        var col = self.cursor_col;
        while (col + n < self.cols) : (col += 1) {
            const cell = self.grid.cellAt(col + n, self.cursor_row);
            self.grid.setCellAt(col, self.cursor_row, cell);
        }
        col = self.cols - n;
        while (col < self.cols) : (col += 1) {
            self.grid.setCellAt(col, self.cursor_row, self.currentFillCell());
        }
    }

    fn insertChars(self: *Terminal, count: u32) void {
        const n = @min(count, self.cols - self.cursor_col);
        var col: u32 = n;
        while (col > 0) {
            col -= 1;
            const src = self.cursor_col + col;
            const dst = src + n;
            if (dst < self.cols) {
                const cell = self.grid.cellAt(src, self.cursor_row);
                self.grid.setCellAt(dst, self.cursor_row, cell);
            }
        }
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            self.grid.setCellAt(self.cursor_col + i, self.cursor_row, self.currentFillCell());
        }
    }

    pub fn resize(self: *Terminal, new_cols: u32, new_rows: u32) !void {
        var new_grid = try Grid.Grid.init(self.allocator, new_cols, new_rows);
        const copy_cols = @min(self.cols, new_cols);
        const copy_rows = @min(self.rows, new_rows);
        var row: u32 = 0;
        while (row < copy_rows) : (row += 1) {
            var col: u32 = 0;
            while (col < copy_cols) : (col += 1) {
                new_grid.setCellAt(col, row, self.grid.cellAt(col, row));
            }
        }
        self.grid.deinit();
        self.grid = new_grid;

        if (self.alt_screen_grid) |*alt| {
            const old_alt_cols = alt.cols;
            const old_alt_rows = alt.rows;
            var new_alt = Grid.Grid.init(self.allocator, new_cols, new_rows) catch {
                self.cols = new_cols;
                self.rows = new_rows;
                self.cursor_col = @min(self.cursor_col, new_cols -| 1);
                self.cursor_row = @min(self.cursor_row, new_rows -| 1);
                self.scroll_top = 0;
                self.scroll_bottom = new_rows - 1;
                return;
            };
            const ac = @min(old_alt_cols, new_cols);
            const ar = @min(old_alt_rows, new_rows);
            var r: u32 = 0;
            while (r < ar) : (r += 1) {
                var c: u32 = 0;
                while (c < ac) : (c += 1) {
                    new_alt.setCellAt(c, r, alt.cellAt(c, r));
                }
            }
            alt.deinit();
            self.alt_screen_grid = new_alt;
        }

        self.cols = new_cols;
        self.rows = new_rows;
        self.cursor_col = @min(self.cursor_col, new_cols -| 1);
        self.cursor_row = @min(self.cursor_row, new_rows -| 1);
        self.scroll_top = 0;
        self.scroll_bottom = new_rows - 1;
    }

    fn enterAltScreen(self: *Terminal) void {
        if (self.using_alt_screen) return;
        self.using_alt_screen = true;
        if (self.alt_screen_grid == null) {
            self.alt_screen_grid = Grid.Grid.init(self.allocator, self.cols, self.rows) catch return;
        }
        // Save current grid to alt_screen_grid
        const copy_cols = @min(self.cols, self.alt_screen_grid.?.cols);
        const copy_rows = @min(self.rows, self.alt_screen_grid.?.rows);
        var row: u32 = 0;
        while (row < copy_rows) : (row += 1) {
            var col: u32 = 0;
            while (col < copy_cols) : (col += 1) {
                self.alt_screen_grid.?.setCellAt(col, row, self.grid.cellAt(col, row));
            }
        }
        // Clear the current (now alt) screen
        self.grid.clear(.{
            .char = ' ',
            .fg = self.current_fg,
            .bg = self.current_bg,
            .attrs = .{},
        });
        self.cursor_col = 0;
        self.cursor_row = 0;
    }

    fn exitAltScreen(self: *Terminal) void {
        if (!self.using_alt_screen) return;
        self.using_alt_screen = false;
        // Restore the saved screen
        if (self.alt_screen_grid) |alt| {
            const copy_cols = @min(self.cols, alt.cols);
            const copy_rows = @min(self.rows, alt.rows);
            var row: u32 = 0;
            while (row < copy_rows) : (row += 1) {
                var col: u32 = 0;
                while (col < copy_cols) : (col += 1) {
                    self.grid.setCellAt(col, row, alt.cellAt(col, row));
                }
            }
        }
        self.cursor_col = 0;
        self.cursor_row = 0;
    }

    pub fn getSelectedText(self: *Terminal, allocator: std.mem.Allocator) !?[]const u8 {
        const start = self.selection_start orelse return null;
        const end = self.selection_end orelse return null;

        var r0 = start.row;
        var c0 = start.col;
        var r1 = end.row;
        var c1 = end.col;

        if (r0 > r1 or (r0 == r1 and c0 > c1)) {
            std.mem.swap(u32, &r0, &r1);
            std.mem.swap(u32, &c0, &c1);
        }

        var list = std.ArrayListUnmanaged(u8).empty;
        defer list.deinit(allocator);

        var r = r0;
        while (r <= r1) : (r += 1) {
            const start_col = if (r == r0) c0 else 0;
            const end_col = if (r == r1) c1 else self.cols - 1;

            var c_idx = start_col;
            while (c_idx <= end_col) : (c_idx += 1) {
                const cell = self.grid.cellAt(c_idx, r);
                if (cell.char != 0 and cell.char <= 0x10FFFF) {
                    var buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(cell.char, &buf) catch continue;
                    try list.appendSlice(allocator, buf[0..len]);
                } else if (c_idx <= end_col) {
                    try list.append(allocator, ' ');
                }
            }
            if (r < r1) try list.append(allocator, '\n');
        }

        try list.append(allocator, 0);
        const slice = try list.toOwnedSlice(allocator);
        return slice[0 .. slice.len - 1 :0];
    }
};

/// Convert 256-color palette index to RGB.
fn color256(idx: u16) Cell.Color {
    if (idx < 16) return Cell.Color.ansi(@intCast(idx));
    if (idx < 232) {
        // 6x6x6 color cube
        const ci = idx - 16;
        const ri = ci / 36;
        const gi = (ci % 36) / 6;
        const bi = ci % 6;
        return Cell.Color{
            .r = if (ri == 0) 0 else @intCast(55 + ri * 40),
            .g = if (gi == 0) 0 else @intCast(55 + gi * 40),
            .b = if (bi == 0) 0 else @intCast(55 + bi * 40),
        };
    }
    // Grayscale ramp
    const level: u8 = @intCast(8 + (idx - 232) * 10);
    return Cell.Color{ .r = level, .g = level, .b = level };
}
