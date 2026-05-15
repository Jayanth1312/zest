const std = @import("std");
const Entry = @import("Entry.zig");
const Cell = @import("../terminal/Cell.zig");
const Grid = @import("../terminal/Grid.zig");

pub const SearchMode = enum {
    both,
    files_only,
    dirs_only,
};

pub const FileExplorer = struct {
    allocator: std.mem.Allocator,
    current_path: []u8,
    path_buf: [4096]u8 = undefined,
    path_len: usize = 0,
    entries: std.ArrayListUnmanaged(Entry.Entry) = .empty,
    selected_index: usize = 0,
    scroll_offset: usize = 0,
    visible: bool = false,
    searching: bool = false,
    search_mode: SearchMode = .both,
    search_buf: [256]u8 = undefined,
    search_len: usize = 0,
    filtered_indices: std.ArrayListUnmanaged(usize) = .empty,
    search_results: std.ArrayListUnmanaged(Entry.SearchResult) = .empty,
    search_results_ready: bool = false,
    search_worker: ?*Entry.SearchWorker = null,
    search_thread: ?std.Thread = null,
    search_version: u32 = 0,
    saved_grid: ?[]Cell.Cell = null,
    saved_rows: u32 = 0,
    saved_cols: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, start_path: []const u8) !FileExplorer {
        var explorer = FileExplorer{
            .allocator = allocator,
            .current_path = "",
        };
        const path_copy = try allocator.dupe(u8, start_path);
        explorer.current_path = path_copy;
        try explorer.refresh();
        return explorer;
    }

    pub fn deinit(self: *FileExplorer) void {
        self.cancelBackgroundSearch();
        self.allocator.free(self.current_path);
        for (self.entries.items) |*e| e.deinit(self.allocator);
        self.entries.deinit(self.allocator);
        self.filtered_indices.deinit(self.allocator);
        for (self.search_results.items) |*r| r.deinit(self.allocator);
        self.search_results.deinit(self.allocator);
        if (self.saved_grid) |grid| {
            self.allocator.free(grid);
        }
    }

    fn saveGrid(self: *FileExplorer, grid: *Grid.Grid, cols: u32, rows: u32) void {
        if (self.saved_grid) |old| {
            self.allocator.free(old);
        }
        const total = @as(usize, cols) * @as(usize, rows);
        self.saved_grid = self.allocator.alloc(Cell.Cell, total) catch return;
        self.saved_cols = cols;
        self.saved_rows = rows;
        @memcpy(self.saved_grid.?[0..total], grid.cells[0..total]);
    }

    fn restoreGrid(self: *FileExplorer, grid: *Grid.Grid) void {
        if (self.saved_grid) |saved| {
            const total = @as(usize, self.saved_cols) * @as(usize, self.saved_rows);
            if (total <= grid.cells.len) {
                @memcpy(grid.cells[0..total], saved[0..total]);
            }
            self.allocator.free(saved);
            self.saved_grid = null;
        }
    }

    pub fn refresh(self: *FileExplorer) !void {
        for (self.entries.items) |*e| e.deinit(self.allocator);
        self.entries.clearRetainingCapacity();

        self.entries = try Entry.readDirectory(self.allocator, self.current_path);
        self.selected_index = 0;
        self.scroll_offset = 0;
        self.searching = false;
        self.search_len = 0;
        self.filtered_indices.clearRetainingCapacity();
    }

    pub fn navigateUp(self: *FileExplorer, visible_rows: usize) void {
        const count = self.getVisibleCount();
        if (count == 0) return;
        if (self.selected_index > 0) {
            self.selected_index -= 1;
        } else {
            self.selected_index = count - 1;
        }
        self.ensureVisible(visible_rows);
    }

    pub fn navigateDown(self: *FileExplorer, visible_rows: usize) void {
        const count = self.getVisibleCount();
        if (count == 0) return;
        if (self.selected_index < count - 1) {
            self.selected_index += 1;
        } else {
            self.selected_index = 0;
        }
        self.ensureVisible(visible_rows);
    }

    fn getVisibleCount(self: *FileExplorer) usize {
        if (self.searching and self.search_len > 0) {
            if (self.search_results_ready) {
                return self.search_results.items.len;
            }
            return self.filtered_indices.items.len;
        }
        if (self.searching) {
            return 0;
        }
        return self.entries.items.len;
    }

    fn getEntryAt(self: *FileExplorer, idx: usize) ?*Entry.Entry {
        if (self.searching and self.search_len > 0) {
            return self.getFilteredEntryAt(idx);
        }
        if (idx >= self.entries.items.len) return null;
        return &self.entries.items[idx];
    }

    fn getFilteredEntryAt(self: *FileExplorer, idx: usize) ?*Entry.Entry {
        if (idx >= self.filtered_indices.items.len) return null;
        const entry_idx = self.filtered_indices.items[idx];
        if (entry_idx >= self.entries.items.len) return null;
        return &self.entries.items[entry_idx];
    }

    fn getSearchResultAt(self: *FileExplorer, idx: usize) ?*Entry.SearchResult {
        if (!self.searching or self.search_len == 0) return null;
        if (idx >= self.search_results.items.len) return null;
        return &self.search_results.items[idx];
    }

    fn ensureVisible(self: *FileExplorer, visible_rows: usize) void {
        if (visible_rows == 0) return;
        if (self.selected_index < self.scroll_offset) {
            self.scroll_offset = self.selected_index;
        } else if (self.selected_index >= self.scroll_offset + visible_rows) {
            self.scroll_offset = self.selected_index - visible_rows + 1;
        }
    }

    fn selectDirPath(self: *FileExplorer, path: []const u8) !void {
        const new_path = try self.allocator.dupe(u8, path);
        self.allocator.free(self.current_path);
        self.current_path = new_path;
        try self.refresh();
    }

    pub fn selectEntry(self: *FileExplorer) !?[]const u8 {
        if (self.searching and self.search_len > 0) {
            if (self.search_results_ready) {
                const result = self.getSearchResultAt(self.selected_index) orelse return null;
                if (result.kind == .directory) {
                    try self.selectDirPath(result.full_path);
                    self.cancelSearch();
                    return null;
                }
                return result.full_path;
            } else {
                const entry = self.getFilteredEntryAt(self.selected_index) orelse return null;
                if (std.mem.eql(u8, entry.name, "..")) {
                    try self.goBack();
                    return null;
                }
                if (entry.kind == .directory) {
                    try self.selectDirPath(entry.full_path);
                    self.cancelSearch();
                    return null;
                }
                return entry.full_path;
            }
        }

        const count = self.getVisibleCount();
        if (count == 0) return null;
        if (self.selected_index >= count) return null;

        const entry = self.getEntryAt(self.selected_index) orelse return null;

        if (std.mem.eql(u8, entry.name, "..")) {
            try self.goBack();
            return null;
        }

        if (entry.kind == .directory) {
            try self.selectDirPath(entry.full_path);
            return null;
        }

        return entry.full_path;
    }

    pub fn goBack(self: *FileExplorer) !void {
        var parent_buf: [4096]u8 = undefined;
        const parent = std.fs.path.dirname(self.current_path);
        if (parent) |p| {
            if (p.len == 0) return;
            const copy_len = @min(p.len, parent_buf.len);
            @memcpy(parent_buf[0..copy_len], p[0..copy_len]);

            self.allocator.free(self.current_path);
            const new_path = try self.allocator.dupe(u8, parent_buf[0..copy_len]);
            self.current_path = new_path;
            try self.refresh();
        }
    }

    pub fn toggle(self: *FileExplorer, grid: *Grid.Grid, pane_cols: u32, pane_rows: u32) void {
        if (self.visible) {
            self.restoreGrid(grid);
            self.visible = false;
        } else {
            self.visible = true;
            self.refresh() catch {};
            self.render(grid, pane_cols, pane_rows);
        }
    }

    pub fn close(self: *FileExplorer, grid: *Grid.Grid) void {
        if (self.visible) {
            self.restoreGrid(grid);
            self.visible = false;
        }
    }

    pub fn startSearch(self: *FileExplorer, mode: SearchMode) void {
        self.searching = true;
        self.search_mode = mode;
        self.search_len = 0;
        self.selected_index = 0;
        self.scroll_offset = 0;
        self.applyFilter();
    }

    pub fn addSearchChar(self: *FileExplorer, ch: u8) void {
        if (self.search_len < self.search_buf.len - 1) {
            self.search_buf[self.search_len] = ch;
            self.search_len += 1;
            self.applyFilter();
        }
    }

    pub fn removeSearchChar(self: *FileExplorer) void {
        if (self.search_len > 0) {
            self.search_len -= 1;
            self.applyFilter();
        }
    }

    pub fn cancelSearch(self: *FileExplorer) void {
        self.cancelBackgroundSearch();
        self.searching = false;
        self.search_len = 0;
        self.selected_index = 0;
        self.scroll_offset = 0;
        self.filtered_indices.clearRetainingCapacity();
        for (self.search_results.items) |*r| r.deinit(self.allocator);
        self.search_results.clearRetainingCapacity();
        self.search_results_ready = false;
    }

    fn cancelBackgroundSearch(self: *FileExplorer) void {
        if (self.search_worker) |worker| {
            worker.cancel();
        }
        if (self.search_thread) |thread| {
            thread.join();
            self.search_thread = null;
        }
        if (self.search_worker) |worker| {
            worker.deinit();
            self.allocator.destroy(worker);
            self.search_worker = null;
        }
    }

    fn startBackgroundSearch(self: *FileExplorer) void {
        if (self.search_len == 0) return;
        if (self.search_thread != null) return;

        const query = self.search_buf[0..self.search_len];
        const worker = Entry.SearchWorker.init(
            self.allocator,
            self.current_path,
            query,
            10,
            self.search_version,
        ) catch return;
        const worker_ptr = self.allocator.create(Entry.SearchWorker) catch {
            var w = worker;
            w.deinit();
            return;
        };
        worker_ptr.* = worker;
        self.search_worker = worker_ptr;

        const thread = std.Thread.spawn(.{}, Entry.SearchWorker.search, .{worker_ptr}) catch {
            worker_ptr.deinit();
            self.allocator.destroy(worker_ptr);
            self.search_worker = null;
            return;
        };
        self.search_thread = thread;
    }

    pub fn updateSearch(self: *FileExplorer) void {
        if (self.search_worker) |worker| {
            if (worker.isDone()) {
                if (self.search_thread) |thread| {
                    thread.join();
                    self.search_thread = null;
                }
                if (worker.version == self.search_version) {
                    self.mergeSearchResults(worker);
                    self.search_results_ready = true;
                }
                worker.deinit();
                self.allocator.destroy(worker);
                self.search_worker = null;

                if (!self.search_results_ready and self.search_len > 0) {
                    self.startBackgroundSearch();
                }
            }
        }
    }

    fn mergeSearchResults(self: *FileExplorer, worker: *Entry.SearchWorker) void {
        for (self.search_results.items) |*r| r.deinit(self.allocator);
        self.search_results.clearRetainingCapacity();

        for (worker.results.items) |result| {
            const keep = switch (self.search_mode) {
                .both => true,
                .files_only => result.kind == .file,
                .dirs_only => result.kind == .directory,
            };
            if (!keep) continue;

            const name_dup = self.allocator.dupe(u8, result.name) catch continue;
            const path_dup = self.allocator.dupe(u8, result.full_path) catch continue;
            self.search_results.append(self.allocator, .{
                .name = name_dup,
                .full_path = path_dup,
                .kind = result.kind,
                .size = result.size,
                .depth = result.depth,
            }) catch continue;
        }

        sortSearchResults(self.search_results.items);
    }

    fn sortSearchResults(items: []Entry.SearchResult) void {
        std.sort.block(Entry.SearchResult, items, {}, struct {
            fn lessThan(_: void, a: Entry.SearchResult, b: Entry.SearchResult) bool {
                const a_is_dir = a.kind == .directory;
                const b_is_dir = b.kind == .directory;
                if (a_is_dir and !b_is_dir) return true;
                if (!a_is_dir and b_is_dir) return false;
                return std.ascii.lessThanIgnoreCase(a.name, b.name);
            }
        }.lessThan);
    }

    pub fn getSelectedPath(self: *FileExplorer) ?[]const u8 {
        if (self.searching and self.search_len > 0) {
            if (self.search_results_ready) {
                const result = self.getSearchResultAt(self.selected_index) orelse return null;
                return result.full_path;
            } else {
                const entry = self.getFilteredEntryAt(self.selected_index) orelse return null;
                return entry.full_path;
            }
        }
        const count = self.getVisibleCount();
        if (count == 0) return null;
        if (self.selected_index >= count) return null;
        const entry = self.getEntryAt(self.selected_index) orelse return null;
        return entry.full_path;
    }

    pub fn getSelectedKind(self: *FileExplorer) ?Entry.Kind {
        if (self.searching and self.search_len > 0) {
            if (self.search_results_ready) {
                const result = self.getSearchResultAt(self.selected_index) orelse return null;
                return result.kind;
            } else {
                const entry = self.getFilteredEntryAt(self.selected_index) orelse return null;
                return entry.kind;
            }
        }
        const count = self.getVisibleCount();
        if (count == 0) return null;
        if (self.selected_index >= count) return null;
        const entry = self.getEntryAt(self.selected_index) orelse return null;
        return entry.kind;
    }

    fn applyFilter(self: *FileExplorer) void {
        for (self.search_results.items) |*r| r.deinit(self.allocator);
        self.search_results.clearRetainingCapacity();
        self.search_results_ready = false;
        self.filtered_indices.clearRetainingCapacity();
        if (self.search_len == 0) return;

        const query = self.search_buf[0..self.search_len];

        for (self.entries.items, 0..) |entry, i| {
            const name_matches = std.ascii.indexOfIgnoreCase(entry.name, query) != null;
            const kind_matches = switch (self.search_mode) {
                .both => true,
                .files_only => entry.kind == .file,
                .dirs_only => entry.kind == .directory,
            };
            if (name_matches and kind_matches) {
                self.filtered_indices.append(self.allocator, i) catch continue;
            }
        }

        self.search_version += 1;
        self.startBackgroundSearch();

        self.selected_index = 0;
        self.scroll_offset = 0;
    }

    pub fn render(self: *FileExplorer, grid: *Grid.Grid, pane_cols: u32, pane_rows: u32) void {
        if (!self.visible) return;

        self.updateSearch();

        if (self.saved_grid == null) {
            self.saveGrid(grid, pane_cols, pane_rows);
        }

        const cols = pane_cols;
        const rows = pane_rows;

        const bg = Cell.Color.base01;
        const fg = Cell.Color.base05;
        const dir_color = Cell.Color.base08;
        const selected_bg = Cell.Color.base08;
        const selected_fg = Cell.Color.base00;
        const dim_fg = Cell.Color.base04;
        const symlink_color = Cell.Color.base0B;
        const search_fg = Cell.Color.base0A;

        const header_rows: u32 = 3;
        const footer_rows: u32 = 1;
        const list_start_row: u32 = header_rows;
        const visible_rows: usize = @intCast(if (rows > header_rows + footer_rows) rows - header_rows - footer_rows else 0);

        for (0..rows) |row| {
            for (0..cols) |col| {
                grid.setCellAt(@intCast(col), @intCast(row), .{
                    .char = ' ',
                    .fg = fg,
                    .bg = bg,
                });
            }
        }

        const path_display = self.formatPathForDisplay();
        const path_col = @min(path_display.len, cols);
        for (0..path_col) |i| {
            grid.setCellAt(@intCast(i), 0, .{
                .char = @as(u21, path_display[i]),
                .fg = Cell.Color.base00,
                .bg = Cell.Color.base08,
                .attrs = .{ .bold = true },
            });
        }

        if (self.searching) {
            const mode_prefix = switch (self.search_mode) {
                .both => "/ ",
                .files_only => "@ ",
                .dirs_only => "# ",
            };
            for (0..mode_prefix.len) |i| {
                if (i < cols) {
                    grid.setCellAt(@intCast(i), 1, .{
                        .char = @as(u21, mode_prefix[i]),
                        .fg = search_fg,
                        .bg = bg,
                        .attrs = .{ .bold = true },
                    });
                }
            }
            for (0..self.search_len) |i| {
                const col = mode_prefix.len + i;
                if (col < cols) {
                    grid.setCellAt(@intCast(col), 1, .{
                        .char = @as(u21, self.search_buf[i]),
                        .fg = search_fg,
                        .bg = bg,
                        .attrs = .{ .underline = true },
                    });
                }
            }
            const cursor_col = mode_prefix.len + self.search_len;
            if (cursor_col < cols) {
                grid.setCellAt(@intCast(cursor_col), 1, .{
                    .char = ' ',
                    .fg = search_fg,
                    .bg = search_fg,
                });
            }
        } else {
            const count = self.entries.items.len;
            var count_buf: [32]u8 = undefined;
            const count_str = std.fmt.bufPrint(&count_buf, "{d} items", .{count}) catch "";
            const count_start = if (cols > count_str.len + 1) cols - count_str.len - 1 else 0;
            for (0..count_str.len) |i| {
                const col = count_start + i;
                if (col < cols) {
                    grid.setCellAt(@intCast(col), 1, .{
                        .char = @as(u21, count_str[i]),
                        .fg = dim_fg,
                        .bg = bg,
                    });
                }
            }
        }

        for (0..cols) |col| {
            grid.setCellAt(@intCast(col), 2, .{
                .char = ' ',
                .fg = Cell.Color.base03,
                .bg = Cell.Color.base03,
            });
        }

        var display_row: u32 = 0;
        var ei: usize = self.scroll_offset;
        const count = self.getVisibleCount();

        if (self.searching and self.search_len > 0) {
            if (self.search_results_ready and self.search_results.items.len > 0) {
                while (ei < self.search_results.items.len and display_row < visible_rows) : (ei += 1) {
                    const result = &self.search_results.items[ei];
                    const is_selected = ei == self.selected_index;

                    const entry_fg = switch (result.kind) {
                        .directory => if (is_selected) selected_fg else dir_color,
                        .symlink => if (is_selected) selected_fg else symlink_color,
                        else => if (is_selected) selected_fg else fg,
                    };
                    const entry_bg = if (is_selected) selected_bg else bg;

                    const icon = switch (result.kind) {
                        .directory => " DIR ",
                        .symlink => " LNK ",
                        .file => " FILE",
                        else => " ??? ",
                    };

                    var col: u32 = 0;
                    for (icon) |ch| {
                        if (col < cols) {
                            grid.setCellAt(col, list_start_row + display_row, .{
                                .char = @as(u21, ch),
                                .fg = entry_fg,
                                .bg = entry_bg,
                                .attrs = if (is_selected) .{ .bold = true } else .{},
                            });
                            col += 1;
                        }
                    }

                    if (result.depth > 0) {
                        var depth_col: u32 = 0;
                        while (depth_col < result.depth and col < cols) : (depth_col += 1) {
                            grid.setCellAt(col, list_start_row + display_row, .{
                                .char = ' ',
                                .fg = dim_fg,
                                .bg = bg,
                            });
                            col += 1;
                        }
                    }

                    for (result.name) |ch| {
                        if (col < cols) {
                            grid.setCellAt(col, list_start_row + display_row, .{
                                .char = @as(u21, ch),
                                .fg = entry_fg,
                                .bg = entry_bg,
                                .attrs = if (is_selected) .{ .bold = true } else .{},
                            });
                            col += 1;
                        } else {
                            break;
                        }
                    }

                    // Show truncated parent path after name with some spacing
                    if (col + 2 < cols) {
                        col += 2; // gap between name and path
                        var path_buf: [256]u8 = undefined;
                        const path_str = formatParentPath(result.full_path, result.name, &path_buf, cols -| col);
                        const path_color = if (is_selected) Cell.Color.base01 else Cell.Color.base03;
                        for (path_str) |ch| {
                            if (col < cols) {
                                grid.setCellAt(col, list_start_row + display_row, .{
                                    .char = @as(u21, ch),
                                    .fg = path_color,
                                    .bg = entry_bg,
                                });
                                col += 1;
                            } else break;
                        }
                    }

                    display_row += 1;
                }
            } else {
                while (ei < self.filtered_indices.items.len and display_row < visible_rows) : (ei += 1) {
                    const entry_idx = self.filtered_indices.items[ei];
                    if (entry_idx >= self.entries.items.len) break;
                    const entry = &self.entries.items[entry_idx];
                    const is_selected = ei == self.selected_index;

                    const entry_fg = switch (entry.kind) {
                        .directory => if (is_selected) selected_fg else dir_color,
                        .symlink => if (is_selected) selected_fg else symlink_color,
                        else => if (is_selected) selected_fg else fg,
                    };
                    const entry_bg = if (is_selected) selected_bg else bg;

                    const icon = switch (entry.kind) {
                        .directory => " DIR ",
                        .symlink => " LNK ",
                        .file => " FILE",
                        else => " ??? ",
                    };

                    var col: u32 = 0;
                    for (icon) |ch| {
                        if (col < cols) {
                            grid.setCellAt(col, list_start_row + display_row, .{
                                .char = @as(u21, ch),
                                .fg = entry_fg,
                                .bg = entry_bg,
                                .attrs = if (is_selected) .{ .bold = true } else .{},
                            });
                            col += 1;
                        }
                    }

                    var size_buf: [16]u8 = undefined;
                    const size_str = Entry.formatSize(entry.size, &size_buf) catch "     ";
                    for (size_str) |ch| {
                        if (col < cols) {
                            grid.setCellAt(col, list_start_row + display_row, .{
                                .char = @as(u21, ch),
                                .fg = dim_fg,
                                .bg = entry_bg,
                            });
                            col += 1;
                        }
                    }

                    for (entry.name) |ch| {
                        if (col < cols) {
                            grid.setCellAt(col, list_start_row + display_row, .{
                                .char = @as(u21, ch),
                                .fg = entry_fg,
                                .bg = entry_bg,
                                .attrs = if (is_selected) .{ .bold = true } else .{},
                            });
                            col += 1;
                        } else {
                            break;
                        }
                    }

                    // Show truncated parent path after name with some spacing
                    if (col + 2 < cols) {
                        col += 2; // gap between name and path
                        var path_buf: [256]u8 = undefined;
                        const path_str = formatParentPath(entry.full_path, entry.name, &path_buf, cols -| col);
                        const path_color = if (is_selected) Cell.Color.base01 else Cell.Color.base03;
                        for (path_str) |ch| {
                            if (col < cols) {
                                grid.setCellAt(col, list_start_row + display_row, .{
                                    .char = @as(u21, ch),
                                    .fg = path_color,
                                    .bg = entry_bg,
                                });
                                col += 1;
                            } else break;
                        }
                    }

                    display_row += 1;
                }
            }
        } else {
            while (ei < count and display_row < visible_rows) : (ei += 1) {
                const entry = &self.entries.items[ei];
                const is_selected = ei == self.selected_index;

                const entry_fg = switch (entry.kind) {
                    .directory => if (is_selected) selected_fg else dir_color,
                    .symlink => if (is_selected) selected_fg else symlink_color,
                    else => if (is_selected) selected_fg else fg,
                };
                const entry_bg = if (is_selected) selected_bg else bg;

                const icon = switch (entry.kind) {
                    .directory => if (std.mem.eql(u8, entry.name, "..")) " .. " else " DIR ",
                    .symlink => " LNK ",
                    .file => " FILE",
                    else => " ??? ",
                };

                var col: u32 = 0;
                for (icon) |ch| {
                    if (col < cols) {
                        grid.setCellAt(col, list_start_row + display_row, .{
                            .char = @as(u21, ch),
                            .fg = entry_fg,
                            .bg = entry_bg,
                            .attrs = if (is_selected) .{ .bold = true } else .{},
                        });
                        col += 1;
                    }
                }

                var size_buf: [16]u8 = undefined;
                const size_str = Entry.formatSize(entry.size, &size_buf) catch "     ";
                for (size_str) |ch| {
                    if (col < cols) {
                        grid.setCellAt(col, list_start_row + display_row, .{
                            .char = @as(u21, ch),
                            .fg = dim_fg,
                            .bg = entry_bg,
                        });
                        col += 1;
                    }
                }

                for (entry.name) |ch| {
                    if (col < cols) {
                        grid.setCellAt(col, list_start_row + display_row, .{
                            .char = @as(u21, ch),
                            .fg = entry_fg,
                            .bg = entry_bg,
                            .attrs = if (is_selected) .{ .bold = true } else .{},
                        });
                        col += 1;
                    } else {
                        break;
                    }
                }

                display_row += 1;
            }
        }

        if (count == 0) {
            const empty_text = if (self.searching and self.search_len > 0) "(no matches)" else "(empty)";
            for (0..empty_text.len) |ci| {
                if (ci < cols) {
                    grid.setCellAt(@intCast(ci), list_start_row, .{
                        .char = @as(u21, empty_text[ci]),
                        .fg = dim_fg,
                        .bg = bg,
                    });
                }
            }
        }

        for (0..cols) |col| {
            grid.setCellAt(@intCast(col), @intCast(rows - 1), .{
                .char = ' ',
                .fg = Cell.Color.base00,
                .bg = Cell.Color.base08,
            });
        }
        const help_text = " Up/Down  Enter open  Backspace up  / @ # search  Esc close";
        const help_start = if (cols > help_text.len) (cols - help_text.len) / 2 else 0;
        for (0..help_text.len) |hi| {
            const col = help_start + hi;
            if (col < cols) {
                grid.setCellAt(@intCast(col), @intCast(rows - 1), .{
                    .char = @as(u21, help_text[hi]),
                    .fg = Cell.Color.base00,
                    .bg = Cell.Color.base08,
                });
            }
        }
    }

    /// Returns a truncated parent directory string for display beside a search result.
    /// If the parent path is longer than max_cols, it trims leading segments and prepends "…".
    fn formatParentPath(full_path: []const u8, name: []const u8, buf: []u8, max_cols: u32) []const u8 {
        if (max_cols == 0 or buf.len == 0) return "";

        // Derive parent by stripping the trailing name (and the preceding '/')
        var parent = full_path;
        if (full_path.len > name.len) {
            const candidate = full_path[0 .. full_path.len - name.len];
            // Strip trailing separator
            if (candidate.len > 0 and candidate[candidate.len - 1] == '/') {
                parent = candidate[0 .. candidate.len - 1];
            } else {
                parent = candidate;
            }
        }
        if (parent.len == 0) parent = "/";

        const limit = @min(max_cols, @as(u32, @intCast(buf.len)));

        if (parent.len <= limit) {
            @memcpy(buf[0..parent.len], parent);
            return buf[0..parent.len];
        }

        // Path is too long: find a '/' such that the suffix fits with a "…" prefix
        // We want: "…" + parent[cut..] to fit within `limit` chars
        // "…" costs 3 bytes (UTF-8 U+2026) but we're writing ASCII chars here, so use "..." (3 chars)
        const prefix = "...";
        const avail = if (limit > prefix.len) limit - @as(u32, prefix.len) else 0;
        if (avail == 0) {
            const copy = @min(prefix.len, buf.len);
            @memcpy(buf[0..copy], prefix[0..copy]);
            return buf[0..copy];
        }

        // Walk forward until the suffix length fits within avail
        var cut: usize = parent.len -| avail;
        // snap cut to next '/' boundary
        while (cut < parent.len and parent[cut] != '/') cut += 1;

        const suffix = if (cut < parent.len) parent[cut..] else parent[parent.len - avail ..];
        const total = prefix.len + suffix.len;
        if (total > buf.len) {
            // shouldn't happen but guard anyway
            const copy = @min(prefix.len, buf.len);
            @memcpy(buf[0..copy], prefix[0..copy]);
            return buf[0..copy];
        }
        @memcpy(buf[0..prefix.len], prefix);
        @memcpy(buf[prefix.len .. prefix.len + suffix.len], suffix);
        return buf[0..total];
    }

    fn formatPathForDisplay(self: *FileExplorer) []const u8 {
        const home = std.c.getenv("HOME") orelse "";
        const home_str = std.mem.span(home);
        if (home_str.len > 0 and std.mem.startsWith(u8, self.current_path, home_str)) {
            const after = self.current_path[home_str.len..];
            self.path_buf[0] = '~';
            const copy_len = @min(after.len, self.path_buf.len - 2);
            @memcpy(self.path_buf[1..1 + copy_len], after[0..copy_len]);
            self.path_buf[1 + copy_len] = 0;
            self.path_len = 1 + copy_len;
            return self.path_buf[0..self.path_len];
        }
        const copy_len = @min(self.current_path.len, self.path_buf.len - 1);
        @memcpy(self.path_buf[0..copy_len], self.current_path[0..copy_len]);
        self.path_buf[copy_len] = 0;
        self.path_len = copy_len;
        return self.path_buf[0..copy_len];
    }

    pub fn handleClick(self: *FileExplorer, _col: u32, row: u32, pane_rows: u32) ?usize {
        _ = _col;
        if (!self.visible) return null;
        const header_rows: u32 = 3;
        const footer_rows: u32 = 1;
        if (row < header_rows or row >= pane_rows - footer_rows) return null;

        const entry_idx = self.scroll_offset + (row - header_rows);
        const count = self.getVisibleCount();
        if (entry_idx < count) {
            self.selected_index = entry_idx;
            return entry_idx;
        }
        return null;
    }
};