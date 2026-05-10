/// zest PTY — POSIX Pseudo-terminal abstraction.
const std = @import("std");
const os = std.os;
const bindings = @import("../gl.zig");
const pty_c = bindings.pty;

extern var environ: [*:null]?[*:0]u8;
const libc = struct {
    extern "c" fn write(fd: c_int, buf: [*]const u8, count: usize) isize;
    extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
    extern "c" fn execvp(file: [*:0]const u8, argv: [*c]const ?[*:0]const u8) c_int;
    extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;
    extern "c" fn exit(status: c_int) noreturn;
};

const builtin = @import("builtin");
const ConPty = if (builtin.os.tag == .windows) @import("ConPty.zig").ConPty else struct {};

pub const Pty = if (builtin.os.tag == .windows) struct {
    backend: ConPty,

    pub fn spawn(cols: u16, rows: u16) !Pty {
        return Pty{ .backend = try ConPty.spawn(cols, rows) };
    }

    pub fn read(self: *Pty, buf: []u8) !usize {
        return self.backend.read(buf);
    }

    pub fn write(self: *Pty, buf: []const u8) !void {
        return self.backend.write(buf);
    }

    pub fn resize(self: *Pty, cols: u16, rows: u16) void {
        _ = self; _ = cols; _ = rows; // Resize logic for ConPty
    }
} else struct {
    fd: std.posix.fd_t,
    pid: std.posix.pid_t,

    /// Spawn a new shell process connected to a pseudo-terminal.
    pub fn spawn(cols: u16, rows: u16) !Pty {
        var master_fd: c_int = -1;
        var win_size = pty_c.winsize{
            .ws_col = cols,
            .ws_row = rows,
            .ws_xpixel = 0,
            .ws_ypixel = 0,
        };

        var term: pty_c.termios = undefined;
        _ = pty_c.tcgetattr(0, &term); // Get current TTY defaults
        
        // IUTF8 is usually 0x4000 on Linux, might differ on BSD/macOS
        if (builtin.os.tag == .linux) {
            term.c_iflag |= 0x00004000; 
        }

        const pid = pty_c.forkpty(&master_fd, null, &term, &win_size);
        if (pid < 0) return error.ForkPtyFailed;

        if (pid == 0) {
            // Child process: execute shell
            const shell = libc.getenv("SHELL") orelse "/bin/sh";
            const argv = [_]?[*:0]const u8{ shell, null };
            _ = libc.setenv("TERM", "xterm-256color", 1);
            _ = libc.execvp(shell, &argv[0]);
            libc.exit(1);
            unreachable;
        }

        // Parent process
        // Set master FD to non-blocking
        var flags = pty_c.fcntl(master_fd, pty_c.F_GETFL);
        flags |= pty_c.O_NONBLOCK;
        _ = pty_c.fcntl(master_fd, pty_c.F_SETFL, flags);

        return Pty{
            .fd = master_fd,
            .pid = pid,
        };
    }

    /// Read available data from the PTY into the provided buffer.
    /// Returns the number of bytes read, or 0 if would block.
    pub fn read(self: *Pty, buf: []u8) !usize {
        const amt = std.posix.read(self.fd, buf) catch |err| {
            if (err == error.WouldBlock) return 0;
            return err;
        };
        return amt;
    }

    /// Write data to the PTY (input to the shell).
    pub fn write(self: *Pty, buf: []const u8) !void {
        var written: usize = 0;
        while (written < buf.len) {
            const amt = libc.write(self.fd, buf[written..].ptr, buf.len - written);
            if (amt < 0) {
                const errno = std.c._errno().*;
                if (errno == @intFromEnum(std.posix.E.AGAIN)) continue;
                return error.WriteFailed;
            }
            written += @intCast(amt);
        }
    }

    /// Notify the PTY of a terminal resize.
    pub fn resize(self: *Pty, cols: u16, rows: u16) void {
        var win_size = pty_c.winsize{
            .ws_col = cols,
            .ws_row = rows,
            .ws_xpixel = 0,
            .ws_ypixel = 0,
        };
        _ = pty_c.ioctl(self.fd, pty_c.TIOCSWINSZ, &win_size);
    }
};
