/// zest RingBuffer — a circular buffer for raw PTY bytes.
const std = @import("std");

pub const RingBuffer = struct {
    buffer: []u8,
    head: usize,
    tail: usize,
    count: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !RingBuffer {
        const buffer = try allocator.alloc(u8, capacity);
        return RingBuffer{
            .buffer = buffer,
            .head = 0,
            .tail = 0,
            .count = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RingBuffer) void {
        self.allocator.free(self.buffer);
    }

    /// Write data into the ring buffer. Returns number of bytes written.
    pub fn write(self: *RingBuffer, data: []const u8) usize {
        const available = self.buffer.len - self.count;
        const to_write = @min(data.len, available);
        if (to_write == 0) return 0;

        const first_part = @min(to_write, self.buffer.len - self.head);
        @memcpy(self.buffer[self.head .. self.head + first_part], data[0..first_part]);

        if (first_part < to_write) {
            const second_part = to_write - first_part;
            @memcpy(self.buffer[0..second_part], data[first_part..to_write]);
            self.head = second_part;
        } else {
            self.head = (self.head + first_part) % self.buffer.len;
        }

        self.count += to_write;
        return to_write;
    }

    /// Read data from the ring buffer into the provided slice.
    pub fn read(self: *RingBuffer, out: []u8) usize {
        const to_read = @min(out.len, self.count);
        if (to_read == 0) return 0;

        const first_part = @min(to_read, self.buffer.len - self.tail);
        @memcpy(out[0..first_part], self.buffer[self.tail .. self.tail + first_part]);

        if (first_part < to_read) {
            const second_part = to_read - first_part;
            @memcpy(out[first_part..to_read], self.buffer[0..second_part]);
            self.tail = second_part;
        } else {
            self.tail = (self.tail + first_part) % self.buffer.len;
        }

        self.count -= to_read;
        return to_read;
    }
};
