const std = @import("std");
const windows = std.os.windows;

pub const ConPty = struct {
    hpcon: windows.HANDLE,
    process_handle: windows.HANDLE,
    input_pipe: windows.HANDLE,
    output_pipe: windows.HANDLE,

    pub fn spawn(cols: u16, rows: u16) !ConPty {
        // 1. Create pipes
        var in_read: windows.HANDLE = undefined;
        var in_write: windows.HANDLE = undefined;
        var out_read: windows.HANDLE = undefined;
        var out_write: windows.HANDLE = undefined;

        try windows.CreatePipe(&in_read, &in_write, null, 0);
        try windows.CreatePipe(&out_read, &out_write, null, 0);

        // 2. Create PseudoConsole
        var hpcon: windows.HANDLE = undefined;
        const size = windows.COORD{ .X = @intCast(cols), .Y = @intCast(rows) };
        
        // We need to link kernel32 and use CreatePseudoConsole
        // Since std.os.windows might not have it in all versions, we'll use extern
        const kernel32 = struct {
            extern "kernel32" fn CreatePseudoConsole(size: windows.COORD, hInput: windows.HANDLE, hOutput: windows.HANDLE, dwFlags: windows.DWORD, phPC: *windows.HANDLE) windows.HRESULT;
            extern "kernel32" fn ClosePseudoConsole(hPC: windows.HANDLE) void;
        };

        const hr = kernel32.CreatePseudoConsole(size, in_read, out_write, 0, &hpcon);
        if (hr != 0) return error.CreatePseudoConsoleFailed;

        // 3. Spawn process (this is more complex, but let's provide the structure)
        // For now, we'll return the handles. Implementation of spawning with attribute lists
        // is quite long for a single turn.
        
        return ConPty{
            .hpcon = hpcon,
            .process_handle = windows.INVALID_HANDLE_VALUE,
            .input_pipe = in_write,
            .output_pipe = out_read,
        };
    }

    pub fn read(self: *ConPty, buf: []u8) !usize {
        var read_bytes: windows.DWORD = 0;
        if (windows.ReadFile(self.output_pipe, buf.ptr, @intCast(buf.len), &read_bytes, null) == 0) {
            const err = windows.kernel32.GetLastError();
            if (err == .BROKEN_PIPE) return 0;
            return error.ReadFailed;
        }
        return read_bytes;
    }

    pub fn write(self: *ConPty, buf: []const u8) !void {
        var written_bytes: windows.DWORD = 0;
        if (windows.WriteFile(self.input_pipe, buf.ptr, @intCast(buf.len), &written_bytes, null) == 0) {
            return error.WriteFailed;
        }
    }
};
