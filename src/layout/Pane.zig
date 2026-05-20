const std = @import("std");
const Terminal = @import("../terminal/Terminal.zig").Terminal;
const Pty = @import("../pty/Pty.zig").Pty;
const FileExplorer = @import("../fileexplorer/FileExplorer.zig").FileExplorer;

pub const Pane = struct {
    terminal: Terminal,
    pty: Pty,
    id: u32,
    focused: bool = false,
    file_explorer: ?*FileExplorer = null,
    is_history_pane: bool = false,

    x: f32 = 0.0,
    y: f32 = 0.0,
    width: f32 = 0.0,
    height: f32 = 0.0,
    cols: u32 = 0,
    rows: u32 = 0,

    cmd_buf: [4096]u8 = undefined,
    cmd_len: usize = 0,

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

    pub fn deinit(self: *Pane, allocator: std.mem.Allocator) void {
        self.terminal.deinit();
        if (self.file_explorer) |explorer| {
            explorer.deinit();
            allocator.destroy(explorer);
        }
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

    pub fn initExplorer(self: *Pane, allocator: std.mem.Allocator, start_path: []const u8) !void {
        const explorer = try allocator.create(FileExplorer);
        explorer.* = try FileExplorer.init(allocator, start_path);
        self.file_explorer = explorer;
    }

    pub fn hasExplorer(self: *const Pane) bool {
        return self.file_explorer != null and self.file_explorer.?.visible;
    }

    pub fn trackInput(self: *Pane, ch: u8) void {
        if (ch >= 0x20 and ch < 0x7F) {
            if (self.cmd_len < self.cmd_buf.len) {
                self.cmd_buf[self.cmd_len] = ch;
                self.cmd_len += 1;
            }
        } else if (ch == 0x08 and self.cmd_len > 0) {
            self.cmd_len -= 1;
        } else if (ch == 0x03 or ch == 0x15) {
            self.cmd_len = 0;
        }
    }

    pub fn resetTracking(self: *Pane) void {
        self.cmd_len = 0;
    }

    pub fn commitCommand(self: *Pane) void {
        if (self.cmd_len == 0) return;
        const cmd = self.terminal.allocator.dupe(u8, self.cmd_buf[0..self.cmd_len]) catch return;
        if (self.terminal.command_history.items.len >= self.terminal.max_history) {
            const oldest = self.terminal.command_history.items[0];
            self.terminal.allocator.free(oldest);
            _ = self.terminal.command_history.orderedRemove(0);
        }
        self.terminal.command_history.append(self.terminal.allocator, cmd) catch {
            self.terminal.allocator.free(cmd);
        };
        self.cmd_len = 0;
    }
};
