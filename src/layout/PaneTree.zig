const std = @import("std");
const Pane = @import("Pane.zig").Pane;

pub const Direction = enum { horizontal, vertical };
pub const NavDir = enum { up, down, left, right };

pub const NodeTag = enum { leaf, split };

pub const SplitNode = struct {
    direction: Direction,
    ratio: f32,
    first: Node,
    second: Node,
};

pub const Node = struct {
    tag: NodeTag,
    pane: ?*Pane = null,
    split: ?*SplitNode = null,

    pub fn initLeaf(pane: *Pane) Node {
        return Node{ .tag = .leaf, .pane = pane };
    }

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        if (self.tag == .split) {
            if (self.split) |s| {
                s.first.deinit(allocator);
                s.second.deinit(allocator);
                allocator.destroy(s);
            }
        }
    }

    pub fn findFocused(self: *Node) ?*Pane {
        switch (self.tag) {
            .leaf => {
                if (self.pane) |p| {
                    if (p.focused) return p;
                }
                return null;
            },
            .split => {
                if (self.split) |s| {
                    if (s.first.findFocused()) |pane| return pane;
                    if (s.second.findFocused()) |pane| return pane;
                }
                return null;
            },
        }
    }

    pub fn findPaneAt(self: *Node, px: f32, py: f32) ?*Pane {
        switch (self.tag) {
            .leaf => {
                if (self.pane) |p| {
                    if (px >= p.x and px < p.x + p.width and py >= p.y and py < p.y + p.height) {
                        return p;
                    }
                }
                return null;
            },
            .split => {
                if (self.split) |s| {
                    if (s.first.findPaneAt(px, py)) |pane| return pane;
                    if (s.second.findPaneAt(px, py)) |pane| return pane;
                }
                return null;
            },
        }
    }

    pub fn collectPanes(self: *Node, list: *std.ArrayListUnmanaged(*Pane), allocator: std.mem.Allocator) !void {
        switch (self.tag) {
            .leaf => {
                if (self.pane) |p| {
                    try list.append(allocator, p);
                }
            },
            .split => {
                if (self.split) |s| {
                    try s.first.collectPanes(list, allocator);
                    try s.second.collectPanes(list, allocator);
                }
            },
        }
    }

    pub fn calculateBounds(self: *Node, x: f32, y: f32, width: f32, height: f32, border_size: f32) void {
        switch (self.tag) {
            .leaf => {
                if (self.pane) |p| {
                    p.x = x;
                    p.y = y;
                    p.width = width;
                    p.height = height;
                }
            },
            .split => {
                if (self.split) |s| {
                    if (s.direction == .horizontal) {
                        const first_width = (width - border_size) * s.ratio;
                        const second_width = width - border_size - first_width;
                        s.first.calculateBounds(x, y, first_width, height, border_size);
                        s.second.calculateBounds(x + first_width + border_size, y, second_width, height, border_size);
                    } else {
                        const first_height = (height - border_size) * s.ratio;
                        const second_height = height - border_size - first_height;
                        s.first.calculateBounds(x, y, width, first_height, border_size);
                        s.second.calculateBounds(x, y + first_height + border_size, width, second_height, border_size);
                    }
                }
            },
        }
    }

    pub fn collectSplitLines(self: *Node, x: f32, y: f32, width: f32, height: f32, list: *std.ArrayListUnmanaged(SplitLine), allocator: std.mem.Allocator) !void {
        switch (self.tag) {
            .leaf => {},
            .split => {
                if (self.split) |s| {
                    if (s.direction == .horizontal) {
                        const first_width = (width - 1.5) * s.ratio;
                        const split_x = x + first_width;
                        try list.append(allocator, .{
                            .x = split_x,
                            .y = y,
                            .width = 1.5,
                            .height = height,
                            .is_horizontal = false,
                        });
                        const second_width = width - 1.5 - first_width;
                        try s.first.collectSplitLines(x, y, first_width, height, list, allocator);
                        try s.second.collectSplitLines(x + first_width + 1.5, y, second_width, height, list, allocator);
                    } else {
                        const first_height = (height - 1.5) * s.ratio;
                        const split_y = y + first_height;
                        try list.append(allocator, .{
                            .x = x,
                            .y = split_y,
                            .width = width,
                            .height = 1.5,
                            .is_horizontal = true,
                        });
                        const second_height = height - 1.5 - first_height;
                        try s.first.collectSplitLines(x, y, width, first_height, list, allocator);
                        try s.second.collectSplitLines(x, y + first_height + 1.5, width, second_height, list, allocator);
                    }
                }
            },
        }
    }
};

pub const PaneTree = struct {
    root: Node,
    allocator: std.mem.Allocator,
    next_id: u32,

    pub fn init(allocator: std.mem.Allocator, initial_pane: *Pane) !PaneTree {
        return PaneTree{
            .root = Node.initLeaf(initial_pane),
            .allocator = allocator,
            .next_id = 1,
        };
    }

    pub fn deinit(self: *PaneTree) void {
        self.root.deinit(self.allocator);
    }

    pub fn nextId(self: *PaneTree) u32 {
        const id = self.next_id;
        self.next_id += 1;
        return id;
    }

    pub fn splitFocused(self: *PaneTree, direction: Direction, ratio: f32) !bool {
        const focused = self.root.findFocused() orelse return false;
        std.debug.print("splitFocused: focused pane id={}\n", .{focused.id});
        const result = try self.splitNodeAtPath(&self.root, focused, direction, ratio);
        std.debug.print("splitFocused: result={}\n", .{result});
        return result;
    }

    pub fn splitPane(self: *PaneTree, target: *Pane, direction: Direction, ratio: f32) !*Pane {
        const new_pane_id = self.nextId();
        const new_pane = try self.allocator.create(Pane);
        errdefer self.allocator.destroy(new_pane);
        const init_cols = if (target.cols > 0) target.cols else 80;
        const init_rows = if (target.rows > 0) target.rows else 24;
        new_pane.* = try Pane.init(self.allocator, new_pane_id, init_cols, init_rows);
        new_pane.focused = false;
        target.focused = true;

        const split_node = try self.allocator.create(SplitNode);
        errdefer self.allocator.destroy(split_node);

        const first_child = Node.initLeaf(target);
        const second_child = Node.initLeaf(new_pane);

        split_node.* = SplitNode{
            .direction = direction,
            .ratio = ratio,
            .first = first_child,
            .second = second_child,
        };

        // Find and replace the target node in the tree
        try self.replacePaneInTree(&self.root, target, .{
            .tag = .split,
            .split = split_node,
        });

        return new_pane;
    }

    fn replacePaneInTree(self: *PaneTree, node: *Node, target: *Pane, replacement: Node) !void {
        switch (node.tag) {
            .leaf => {
                if (node.pane) |p| {
                    if (p == target) {
                        node.* = replacement;
                        return;
                    }
                }
            },
            .split => {
                if (node.split) |s| {
                    try self.replacePaneInTree(&s.first, target, replacement);
                    if (node.tag == .leaf) return;
                    try self.replacePaneInTree(&s.second, target, replacement);
                }
            },
        }
    }

    fn splitNodeAtPath(self: *PaneTree, node: *Node, target: *Pane, direction: Direction, ratio: f32) !bool {
        switch (node.tag) {
            .leaf => {
                if (node.pane) |p| {
                    if (p == target) {
                        const new_pane_id = self.nextId();
                        const new_pane = try self.allocator.create(Pane);
                        errdefer self.allocator.destroy(new_pane);
                        const init_cols = if (target.cols > 0) target.cols else 80;
                        const init_rows = if (target.rows > 0) target.rows else 24;
                        new_pane.* = try Pane.init(self.allocator, new_pane_id, init_cols, init_rows);
                        new_pane.focused = true;
                        target.focused = false;

                        const split_node = try self.allocator.create(SplitNode);
                        errdefer self.allocator.destroy(split_node);

                        const first_child = Node.initLeaf(target);
                        const second_child = Node.initLeaf(new_pane);

                        split_node.* = SplitNode{
                            .direction = direction,
                            .ratio = ratio,
                            .first = first_child,
                            .second = second_child,
                        };

                        node.* = Node{
                            .tag = .split,
                            .split = split_node,
                        };
                        return true;
                    }
                }
                return false;
            },
            .split => {
                if (node.split) |s| {
                    if (try self.splitNodeAtPath(&s.first, target, direction, ratio)) return true;
                    if (try self.splitNodeAtPath(&s.second, target, direction, ratio)) return true;
                }
                return false;
            },
        }
    }

    pub fn closeFocused(self: *PaneTree) !bool {
        const focused = self.root.findFocused() orelse return false;
        if (self.root.tag == .leaf) return false;
        return try self.closeNodeAtPath(&self.root, focused);
    }

    pub fn closePane(self: *PaneTree, target: *Pane) !bool {
        if (self.root.tag == .leaf) return false;
        return try self.closeNodeAtPath(&self.root, target);
    }

    fn closeNodeAtPath(self: *PaneTree, node: *Node, target: *Pane) !bool {
        if (node.tag != .split) return false;
        const s = node.split orelse return false;

        if (s.first.tag == .leaf) {
            if (s.first.pane) |fp| {
                if (fp == target) {
                    const survivor = s.second;
                    setFocusOnFirst(&s.second);
                    target.deinit(self.allocator);
                    self.allocator.destroy(target);
                    self.allocator.destroy(s);
                    node.* = survivor;
                    return true;
                }
            }
        }

        if (s.second.tag == .leaf) {
            if (s.second.pane) |scp| {
                if (scp == target) {
                    const survivor = s.first;
                    setFocusOnFirst(&s.first);
                    target.deinit(self.allocator);
                    self.allocator.destroy(target);
                    self.allocator.destroy(s);
                    node.* = survivor;
                    return true;
                }
            }
        }

        if (try self.closeNodeAtPath(&s.first, target)) return true;
        if (try self.closeNodeAtPath(&s.second, target)) return true;

        return false;
    }

    fn setFocusOnFirst(node: *Node) void {
        switch (node.tag) {
            .leaf => {
                if (node.pane) |p| {
                    p.focused = true;
                }
            },
            .split => {
                if (node.split) |s| {
                    setFocusOnFirst(&s.first);
                }
            },
        }
    }

    pub fn navigateFocus(self: *PaneTree, dir: NavDir) void {
        const focused = self.root.findFocused() orelse return;
        var panes: std.ArrayListUnmanaged(*Pane) = .empty;
        defer panes.deinit(self.allocator);
        self.root.collectPanes(&panes, self.allocator) catch return;

        if (panes.items.len <= 1) return;

        var best: ?*Pane = null;
        var best_dist: f32 = std.math.floatMax(f32);

        for (panes.items) |p| {
            if (p == focused) continue;
            const dist = switch (dir) {
                .up => distanceUp(focused, p),
                .down => distanceDown(focused, p),
                .left => distanceLeft(focused, p),
                .right => distanceRight(focused, p),
            };
            if (dist < best_dist) {
                best_dist = dist;
                best = p;
            }
        }

        if (best) |b| {
            focused.focused = false;
            b.focused = true;
        }
    }

    fn distanceUp(from: *Pane, to: *Pane) f32 {
        const from_cx = from.x + from.width / 2.0;
        const from_cy = from.y + from.height / 2.0;
        const to_cx = to.x + to.width / 2.0;
        const to_cy = to.y + to.height / 2.0;
        const dy = from_cy - to_cy;
        const dx = @abs(to_cx - from_cx);
        if (dy <= 0) return std.math.floatMax(f32);
        return dy + dx * 0.5;
    }

    fn distanceDown(from: *Pane, to: *Pane) f32 {
        const from_cx = from.x + from.width / 2.0;
        const from_cy = from.y + from.height / 2.0;
        const to_cx = to.x + to.width / 2.0;
        const to_cy = to.y + to.height / 2.0;
        const dy = to_cy - from_cy;
        const dx = @abs(to_cx - from_cx);
        if (dy <= 0) return std.math.floatMax(f32);
        return dy + dx * 0.5;
    }

    fn distanceLeft(from: *Pane, to: *Pane) f32 {
        const from_cx = from.x + from.width / 2.0;
        const from_cy = from.y + from.height / 2.0;
        const to_cx = to.x + to.width / 2.0;
        const to_cy = to.y + to.height / 2.0;
        const dx = from_cx - to_cx;
        const dy = @abs(to_cy - from_cy);
        if (dx <= 0) return std.math.floatMax(f32);
        return dx + dy * 0.5;
    }

    fn distanceRight(from: *Pane, to: *Pane) f32 {
        const from_cx = from.x + from.width / 2.0;
        const from_cy = from.y + from.height / 2.0;
        const to_cx = to.x + to.width / 2.0;
        const to_cy = to.y + to.height / 2.0;
        const dx = to_cx - from_cx;
        const dy = @abs(to_cy - from_cy);
        if (dx <= 0) return std.math.floatMax(f32);
        return dx + dy * 0.5;
    }

    pub fn equalize(self: *PaneTree) void {
        equalizeNode(&self.root);
    }

    fn equalizeNode(node: *Node) void {
        switch (node.tag) {
            .leaf => {},
            .split => {
                if (node.split) |s| {
                    s.ratio = 0.5;
                    equalizeNode(&s.first);
                    equalizeNode(&s.second);
                }
            },
        }
    }

    pub fn countPanes(self: *PaneTree) usize {
        var panes: std.ArrayListUnmanaged(*Pane) = .empty;
        defer panes.deinit(self.allocator);
        self.root.collectPanes(&panes, self.allocator) catch return 0;
        return panes.items.len;
    }

    pub fn collectSplitLines(self: *PaneTree, fb_width: i32, fb_height: i32, padding_x: f32, padding_y: f32, list: *std.ArrayListUnmanaged(SplitLine), allocator: std.mem.Allocator) !void {
        const avail_w = @as(f32, @floatFromInt(fb_width)) - (padding_x * 2.0);
        const avail_h = @as(f32, @floatFromInt(fb_height)) - (padding_y * 2.0);
        try self.root.collectSplitLines(padding_x, padding_y, avail_w, avail_h, list, allocator);
    }
};

pub const SplitLine = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    is_horizontal: bool,
};
