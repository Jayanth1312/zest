const std = @import("std");
const Terminal = @import("../terminal/Terminal.zig").Terminal;
const Pty = @import("../pty/Pty.zig").Pty;

pub const Pane = struct {
    terminal: Terminal,
    pty: Pty,
    id: u32,
    focused: bool = false,

    x: f32 = 0.0,
    y: f32 = 0.0,
    width: f32 = 0.0,
    height: f32 = 0.0,
    cols: u32 = 0,
    rows: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, id: u32, cols: u32, rows: u32) !Pane {
        const terminal = try Terminal.init(allocator, cols, rows);
        const pty = try Pty.spawn(@intCast(cols), @intCast(rows));
        return Pane{
            .terminal = terminal,
            .pty = pty,
            .id = id,
            .cols = cols,
            .rows = rows,
        };
    }

    pub fn deinit(self: *Pane) void {
        self.terminal.deinit();
    }

    pub fn resize(self: *Pane, new_cols: u32, new_rows: u32) !void {
        if (new_cols == 0 or new_rows == 0) return;
        try self.terminal.resize(new_cols, new_rows);
        self.pty.resize(@intCast(new_cols), @intCast(new_rows));
        self.cols = new_cols;
        self.rows = new_rows;
    }

    pub fn feed(self: *Pane, data: []const u8) void {
        self.terminal.feed(data);
    }

    pub fn write(self: *Pane, data: []const u8) !void {
        try self.pty.write(data);
    }

    pub fn read(self: *Pane, buf: []u8) !usize {
        return try self.pty.read(buf);
    }
};
