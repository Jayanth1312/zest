const std = @import("std");

pub const ParseError = error{
    FileNotFound,
    ParseError,
};

extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern fn fread(buf: *anyopaque, size: usize, count: usize, file: *anyopaque) usize;
extern fn fclose(file: *anyopaque) c_int;
extern fn fseek(file: *anyopaque, offset: c_long, whence: c_int) c_int;
extern fn ftell(file: *anyopaque) c_long;

const SEEK_END: c_int = 2;
const SEEK_SET: c_int = 0;

pub fn parseFile(allocator: std.mem.Allocator, path_str: []const u8) !std.StringHashMap([]u8) {
    const path = allocator.dupeZ(u8, path_str) catch return error.ParseError;
    defer allocator.free(path);

    const file = fopen(path, "r") orelse return error.FileNotFound;
    errdefer _ = fclose(file);

    if (fseek(file, 0, SEEK_END) != 0) return error.ParseError;
    const size = ftell(file);
    if (size < 0) return error.ParseError;
    if (fseek(file, 0, SEEK_SET) != 0) return error.ParseError;

    const content = allocator.alloc(u8, @intCast(size)) catch return error.ParseError;
    defer allocator.free(content);

    const bytes_read = fread(content.ptr, 1, @intCast(size), file);
    _ = fclose(file);

    return parseContent(allocator, content[0..@min(bytes_read, @as(usize, @intCast(size)))]);
}

pub fn parseContent(allocator: std.mem.Allocator, content: []const u8) std.StringHashMap([]u8) {
    var map = std.StringHashMap([]u8).init(allocator);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;
        if (trimmed[0] == '#') continue;

        const eq_pos = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const key = std.mem.trim(u8, trimmed[0..eq_pos], &std.ascii.whitespace);
        var value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], &std.ascii.whitespace);

        if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
            value = value[1 .. value.len - 1];
        }

        if (key.len > 0) {
            const key_owned = allocator.dupe(u8, key) catch continue;
            const val_owned = allocator.dupe(u8, value) catch {
                allocator.free(key_owned);
                continue;
            };
            map.put(key_owned, val_owned) catch {
                allocator.free(key_owned);
                allocator.free(val_owned);
            };
        }
    }

    return map;
}

pub fn deinitMap(map: *std.StringHashMap([]u8)) void {
    var it = map.iterator();
    while (it.next()) |entry| {
        map.allocator.free(entry.key_ptr.*);
        map.allocator.free(entry.value_ptr.*);
    }
    map.deinit();
}
