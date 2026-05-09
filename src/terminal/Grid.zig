/// zest Grid — a 2D grid of terminal cells.
const std = @import("std");
const Cell = @import("Cell.zig");

pub const Grid = struct {
    cells: []Cell.Cell,
    row_indices: []u32,
    cols: u32,
    rows: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, cols: u32, rows: u32) !Grid {
        const total = @as(usize, cols) * @as(usize, rows);
        const cells = try allocator.alloc(Cell.Cell, total);
        @memset(cells, Cell.Cell.blank);

        const row_indices = try allocator.alloc(u32, rows);
        for (row_indices, 0..) |*ptr, i| {
            ptr.* = @intCast(i);
        }

        return Grid{
            .cells = cells,
            .row_indices = row_indices,
            .cols = cols,
            .rows = rows,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Grid) void {
        self.allocator.free(self.cells);
        self.allocator.free(self.row_indices);
    }

    pub fn cellAt(self: *const Grid, col: u32, row: u32) Cell.Cell {
        if (col >= self.cols or row >= self.rows) return Cell.Cell.blank;
        const phys_row = self.row_indices[@as(usize, row)];
        return self.cells[@as(usize, phys_row) * @as(usize, self.cols) + @as(usize, col)];
    }

    pub fn setCellAt(self: *Grid, col: u32, row: u32, cell: Cell.Cell) void {
        if (col >= self.cols or row >= self.rows) return;
        const phys_row = self.row_indices[@as(usize, row)];
        self.cells[@as(usize, phys_row) * @as(usize, self.cols) + @as(usize, col)] = cell;
    }

    /// Write an ASCII string into the grid starting at (col, row).
    pub fn writeString(self: *Grid, start_col: u32, row: u32, text: []const u8, fg: Cell.Color, bg: Cell.Color) void {
        var col = start_col;
        for (text) |byte| {
            if (col >= self.cols) break;
            self.setCellAt(col, row, .{
                .char = @as(u21, byte),
                .fg = fg,
                .bg = bg,
            });
            col += 1;
        }
    }

    /// Clear the entire grid.
    pub fn clear(self: *Grid, fill_cell: Cell.Cell) void {
        @memset(self.cells, fill_cell);
    }

    /// Scroll a specific region up by `count` rows.
    pub fn scrollRegionUp(self: *Grid, top: u32, bottom: u32, count: u32, fill_cell: Cell.Cell) void {
        if (top >= bottom or bottom >= self.rows) return;
        const n = @min(count, bottom - top + 1);
        
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const save = self.row_indices[top];
            var r = top;
            while (r < bottom) : (r += 1) {
                self.row_indices[r] = self.row_indices[r + 1];
            }
            self.row_indices[bottom] = save;
            
            // Clear the new row at the bottom
            const phys_row = save;
            const start = @as(usize, phys_row) * self.cols;
            @memset(self.cells[start .. start + self.cols], fill_cell);
        }
    }

    /// Scroll a specific region down by `count` rows.
    pub fn scrollRegionDown(self: *Grid, top: u32, bottom: u32, count: u32, fill_cell: Cell.Cell) void {
        if (top >= bottom or bottom >= self.rows) return;
        const n = @min(count, bottom - top + 1);
        
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const save = self.row_indices[bottom];
            var r = bottom;
            while (r > top) : (r -= 1) {
                self.row_indices[r] = self.row_indices[r - 1];
            }
            self.row_indices[top] = save;
            
            // Clear the new row at the top
            const phys_row = save;
            const start = @as(usize, phys_row) * self.cols;
            @memset(self.cells[start .. start + self.cols], fill_cell);
        }
    }
};
