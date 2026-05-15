const std = @import("std");

pub const Kind = enum {
    directory,
    file,
    symlink,
    other,
};

pub const Entry = struct {
    name: []u8,
    kind: Kind,
    size: u64,
    full_path: []u8,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, kind: Kind, size: u64, full_path: []const u8) !Entry {
        const name_dup = try allocator.dupe(u8, name);
        errdefer allocator.free(name_dup);
        const path_dup = try allocator.dupe(u8, full_path);
        return Entry{
            .name = name_dup,
            .kind = kind,
            .size = size,
            .full_path = path_dup,
        };
    }

    pub fn deinit(self: *Entry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.full_path);
    }
};

pub const DIR = opaque {};
pub const dirent = extern struct {
    d_ino: std.posix.ino_t,
    d_off: std.posix.off_t,
    d_reclen: c_ushort,
    d_type: u8,
    d_name: [256]u8,
};

pub const Stat = extern struct {
    st_dev: std.posix.dev_t,
    st_ino: std.posix.ino_t,
    st_nlink: std.posix.nlink_t,
    st_mode: std.posix.mode_t,
    st_uid: std.posix.uid_t,
    st_gid: std.posix.gid_t,
    __pad0: c_int = 0,
    st_rdev: std.posix.dev_t,
    st_size: std.posix.off_t,
    st_blksize: std.posix.blksize_t,
    st_blocks: std.posix.blkcnt_t,
    st_atim: std.posix.timespec,
    st_mtim: std.posix.timespec,
    st_ctim: std.posix.timespec,
    __unused: [3]c_long = [3]c_long{ 0, 0, 0 },
};

pub extern "c" fn opendir(name: [*:0]const u8) ?*DIR;
pub extern "c" fn readdir(dirp: *DIR) ?*dirent;
pub extern "c" fn closedir(dirp: *DIR) c_int;
pub extern "c" fn stat(path: [*:0]const u8, buf: *Stat) c_int;

pub fn readDirectory(allocator: std.mem.Allocator, path: []const u8) !std.ArrayListUnmanaged(Entry) {
    var entries: std.ArrayListUnmanaged(Entry) = .empty;
    errdefer {
        for (entries.items) |*e| e.deinit(allocator);
        entries.deinit(allocator);
    }

    var path_buf: [4096:0]u8 = undefined;
    const path_len = @min(path.len, path_buf.len - 1);
    @memcpy(path_buf[0..path_len], path[0..path_len]);
    path_buf[path_len] = 0;

    const dir = opendir(&path_buf) orelse return entries;
    defer _ = closedir(dir);

    var parent_path_buf: [4096:0]u8 = undefined;
    const parent_path = std.fs.path.dirname(path) orelse ".";
    const parent_len = @min(parent_path.len, parent_path_buf.len - 1);
    @memcpy(parent_path_buf[0..parent_len], parent_path[0..parent_len]);
    parent_path_buf[parent_len] = 0;

    const parent_entry = try Entry.init(
        allocator,
        "..",
        .directory,
        0,
        parent_path_buf[0..parent_len :0],
    );
    try entries.append(allocator, parent_entry);

    while (readdir(dir)) |dirent_ptr| {
        const name = std.mem.sliceTo(&dirent_ptr.d_name, 0);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) {
            continue;
        }

        const kind = switch (dirent_ptr.d_type) {
            4 => Kind.directory,
            8 => Kind.file,
            10 => Kind.symlink,
            else => Kind.other,
        };

        var size: u64 = 0;
        if (kind == .file) {
            const joined = std.fs.path.join(allocator, &[_][]const u8{ path, name }) catch continue;
            defer allocator.free(joined);
            var stat_buf: Stat = undefined;
            var stat_path_buf: [4096:0]u8 = undefined;
            const copy_len = @min(joined.len, stat_path_buf.len - 1);
            @memcpy(stat_path_buf[0..copy_len], joined[0..copy_len]);
            stat_path_buf[copy_len] = 0;
            if (stat(&stat_path_buf, &stat_buf) == 0) {
                size = @intCast(stat_buf.st_size);
            }
        }

        const joined = std.fs.path.join(allocator, &[_][]const u8{ path, name }) catch continue;
        defer allocator.free(joined);

        const entry = try Entry.init(
            allocator,
            name,
            kind,
            size,
            joined,
        );
        try entries.append(allocator, entry);
    }

    sortEntries(entries.items);

    return entries;
}

pub const SearchResult = struct {
    name: []u8,
    full_path: []u8,
    kind: Kind,
    size: u64,
    depth: u32,

    pub fn deinit(self: *SearchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.full_path);
    }
};

pub const SearchWorker = struct {
    allocator: std.mem.Allocator,
    root_path: []u8,
    query: []u8,
    results: std.ArrayListUnmanaged(SearchResult),
    done: std.atomic.Value(bool),
    cancelled: std.atomic.Value(bool),
    max_depth: u32,
    version: u32,

    pub fn init(allocator: std.mem.Allocator, root_path: []const u8, query: []const u8, max_depth: u32, version: u32) !SearchWorker {
        const owned_root = try allocator.dupe(u8, root_path);
        errdefer allocator.free(owned_root);
        const owned_query = try allocator.dupe(u8, query);
        return .{
            .allocator = allocator,
            .root_path = owned_root,
            .query = owned_query,
            .results = .empty,
            .done = std.atomic.Value(bool).init(false),
            .cancelled = std.atomic.Value(bool).init(false),
            .max_depth = max_depth,
            .version = version,
        };
    }

    pub fn deinit(self: *SearchWorker) void {
        self.allocator.free(self.root_path);
        self.allocator.free(self.query);
        for (self.results.items) |*r| r.deinit(self.allocator);
        self.results.deinit(self.allocator);
    }

    pub fn cancel(self: *SearchWorker) void {
        self.cancelled.store(true, .release);
    }

    pub fn isDone(self: *SearchWorker) bool {
        return self.done.load(.acquire);
    }

    pub fn search(self: *SearchWorker) void {
        self.searchDir(self.root_path, 0) catch {};
        self.done.store(true, .release);
    }

    fn searchDir(self: *SearchWorker, dir_path: []const u8, depth: u32) !void {
        if (depth > self.max_depth) return;
        if (self.cancelled.load(.acquire)) return;

        var path_buf: [4096:0]u8 = undefined;
        const path_len = @min(dir_path.len, path_buf.len - 1);
        @memcpy(path_buf[0..path_len], dir_path[0..path_len]);
        path_buf[path_len] = 0;

        const dir = opendir(&path_buf) orelse return;
        defer _ = closedir(dir);

        var subdirs: std.ArrayListUnmanaged([:0]u8) = .empty;
        defer {
            for (subdirs.items) |sd| self.allocator.free(sd);
            subdirs.deinit(self.allocator);
        }

        while (readdir(dir)) |dirent_ptr| {
            if (self.cancelled.load(.acquire)) return;
            const name = std.mem.sliceTo(&dirent_ptr.d_name, 0);
            if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;

            const name_matches = std.ascii.indexOfIgnoreCase(name, self.query) != null;

            const kind = switch (dirent_ptr.d_type) {
                4 => Kind.directory,
                8 => Kind.file,
                10 => Kind.symlink,
                else => Kind.other,
            };

            if (name_matches) {
                const joined = try std.fs.path.join(self.allocator, &[_][]const u8{ dir_path, name });
                errdefer self.allocator.free(joined);

                const name_dup = try self.allocator.dupe(u8, name);
                errdefer self.allocator.free(name_dup);

                const result = SearchResult{
                    .name = name_dup,
                    .full_path = joined,
                    .kind = kind,
                    .size = 0,
                    .depth = depth,
                };

                try self.results.append(self.allocator, result);
            }

            if (kind == .directory and depth < self.max_depth) {
                const subdir_path = try std.fs.path.join(self.allocator, &[_][]const u8{ dir_path, name });
                errdefer self.allocator.free(subdir_path);

                const subdir_z = try self.allocator.dupeZ(u8, subdir_path);
                self.allocator.free(subdir_path);
                try subdirs.append(self.allocator, subdir_z);
            }
        }

        for (subdirs.items) |sd| {
            if (self.cancelled.load(.acquire)) return;
            self.searchDir(sd, depth + 1) catch continue;
        }
    }

pub fn getResults(self: *SearchWorker) []const SearchResult {
        return self.results.items;
    }
};

fn sortEntries(entries: []Entry) void {
    std.sort.block(Entry, entries, {}, struct {
        fn lessThan(_: void, a: Entry, b: Entry) bool {
            const a_is_dir = a.kind == .directory;
            const b_is_dir = b.kind == .directory;
            if (a_is_dir and !b_is_dir) return true;
            if (!a_is_dir and b_is_dir) return false;
            return std.ascii.lessThanIgnoreCase(a.name, b.name);
        }
    }.lessThan);
}

pub fn formatSize(size: u64, buf: []u8) ![]const u8 {
    if (size < 1024) {
        return try std.fmt.bufPrint(buf, "{d:>5}B ", .{size});
    } else if (size < 1024 * 1024) {
        const kb = @as(f64, @floatFromInt(size)) / 1024.0;
        return try std.fmt.bufPrint(buf, "{d:>5.1}K ", .{kb});
    } else if (size < 1024 * 1024 * 1024) {
        const mb = @as(f64, @floatFromInt(size)) / (1024.0 * 1024.0);
        return try std.fmt.bufPrint(buf, "{d:>5.1}M ", .{mb});
    } else {
        const gb = @as(f64, @floatFromInt(size)) / (1024.0 * 1024.0 * 1024.0);
        return try std.fmt.bufPrint(buf, "{d:>5.1}G ", .{gb});
    }
}