const std = @import("std");

const assert = std.debug.assert;

// Circular doubly-linked intrusive list
pub const IntrusiveList = struct {
    const Self = @This();

    pub const Node = struct {
        left: ?*Node = null, // to head
        right: ?*Node = null, // to tail

        pub fn isLinked(self: *const Node) bool {
            return self.left != null;
        }

        pub fn linkAfter(self: *Node, target: *Node) void {
            assert(!self.isLinked());
            self.left = target;
            self.right = target.right;

            assert(target.right != null);
            var after_target: *Node = target.right.?;
            after_target.left = self;
            target.right = self;
        }

        pub fn linkBefore(self: *Node, target: *Node) void {
            assert(!self.isLinked());
            self.left = target.left;
            self.right = target;

            assert(target.left != null);
            var before_target: *Node = target.left.?;
            before_target.right = self;
            target.left = self;
        }

        pub fn unlink(self: *Node) void {
            assert(self.isLinked());

            self.left.?.right = self.right;
            self.right.?.left = self.left;

            self.left = null;
            self.right = null;
        }

        pub fn as(self: *Node, comptime T: type) *T {
            return @fieldParentPtr("node", self);
        }
    };

    // Sentinel <-> Head <-> ... <-> Tail <-> Sentinel
    // Sentinel->Left == Tail
    // Sentinel->Right == Head
    sentinel: Node = .{},

    pub fn init(self: *Self) void {
        self.sentinel.left = &self.sentinel;
        self.sentinel.right = &self.sentinel;
    }

    pub fn isEmpty(self: *const Self) bool {
        return self.sentinel.left == &self.sentinel;
    }

    pub fn nonEmpty(self: *const Self) bool {
        return self.sentinel.left != &self.sentinel;
    }

    pub fn back(self: *Self) ?*Node {
        if (self.isEmpty()) {
            return null;
        }
        return self.backUnsafe();
    }

    pub fn front(self: *Self) ?*Node {
        if (self.isEmpty()) {
            return null;
        }
        return self.frontUnsafe();
    }

    pub fn backUnsafe(self: *Self) *Node {
        assert(self.nonEmpty());
        return self.sentinel.left.?;
    }

    pub fn frontUnsafe(self: *Self) *Node {
        assert(self.nonEmpty());
        return self.sentinel.right.?;
    }

    // Move all nodes from rhs to lhs
    // Post-condition: rhs is empty
    pub fn concatByMoving(lhs: *Self, rhs: *Self) void {
        if (rhs.isEmpty()) {
            return;
        }

        var rhs_head: *Node = rhs.frontUnsafe();
        var rhs_tail: *Node = rhs.backUnsafe();
        rhs_head.left = lhs.sentinel.left;
        rhs_tail.right = &lhs.sentinel;

        var old_tail: *Node = lhs.sentinel.left.?;
        lhs.sentinel.left = rhs_tail;
        old_tail.right = rhs_head;

        rhs.init();
    }

    pub fn pushBack(self: *Self, new_node: *Node) void {
        new_node.linkAfter(self.sentinel.left.?);
    }

    pub fn pushFront(self: *Self, new_node: *Node) void {
        new_node.linkBefore(self.sentinel.right.?);
    }

    pub fn popBack(self: *Self) ?*Node {
        var node: *Node = self.back() orelse return null;
        node.unlink();
        return node;
    }

    pub fn popFront(self: *Self) ?*Node {
        var node: *Node = self.front() orelse return null;
        node.unlink();
        return node;
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

test "basic" {
    const T = struct {
        data: u32,
        node: IntrusiveList.Node = .{},
    };
    var list: IntrusiveList = .{};
    list.init();

    var one: T = .{ .data = 1 };
    var two: T = .{ .data = 2 };
    var three: T = .{ .data = 3 };
    var four: T = .{ .data = 4 };
    var five: T = .{ .data = 5 };

    list.pushBack(&two.node); // {2}
    list.pushBack(&five.node); // {2, 5}
    list.pushFront(&one.node); // {1, 2, 5}
    four.node.linkAfter(&two.node); // {1, 2, 4, 5}
    three.node.linkBefore(&four.node); // {1, 2, 3, 4, 5}

    // Traverse forwards.
    {
        var it = list.front();
        var value: u32 = 1;
        while (it) |node| : (it = node.right) {
            if (it == &list.sentinel) {
                break;
            }
            const l: *T = @fieldParentPtr("node", node);
            try testing.expect(l.data == value);
            value += 1;
        }
    }

    // Traverse backwards.
    {
        var it = list.back();
        var value: u32 = 5;
        while (it) |node| : (it = node.left) {
            if (it == &list.sentinel) {
                break;
            }
            const l: *T = @fieldParentPtr("node", node);
            try testing.expect(l.data == value);
            value -= 1;
        }
    }

    _ = list.popFront(); // {2, 3, 4, 5}
    _ = list.popBack(); // {2, 3, 4}
    three.node.unlink(); // {2, 4}

    try testing.expect(@as(*T, @fieldParentPtr("node", list.frontUnsafe())).data == 2);
    try testing.expect(@as(*T, @fieldParentPtr("node", list.backUnsafe())).data == 4);
}

test "concatenation" {
    const T = struct {
        data: u32,
        node: IntrusiveList.Node = .{},
    };
    var list1: IntrusiveList = .{};
    var list2: IntrusiveList = .{};
    list1.init();
    list2.init();

    var one: T = .{ .data = 1 };
    var two: T = .{ .data = 2 };
    var three: T = .{ .data = 3 };
    var four: T = .{ .data = 4 };
    var five: T = .{ .data = 5 };

    list1.pushBack(&one.node);
    list1.pushBack(&two.node);
    list2.pushBack(&three.node);
    list2.pushBack(&four.node);
    list2.pushBack(&five.node);

    list1.concatByMoving(&list2);

    try testing.expect(list1.back() == &five.node);
    try testing.expect(list2.isEmpty());

    // Traverse forwards.
    {
        var it = list1.front();
        var value: u32 = 1;
        while (it) |node| : (it = node.right) {
            if (it == &list1.sentinel) {
                break;
            }
            const l: *T = @fieldParentPtr("node", node);
            try testing.expect(l.data == value);
            value += 1;
        }
    }

    // Traverse backwards.
    {
        var it = list1.back();
        var value: u32 = 5;
        while (it) |node| : (it = node.left) {
            if (it == &list1.sentinel) {
                break;
            }
            const l: *T = @fieldParentPtr("node", node);
            try testing.expect(l.data == value);
            value -= 1;
        }
    }

    // Swap them back, this verifies that concatenating to an empty list works.
    list2.concatByMoving(&list1);

    // Traverse forwards.
    {
        var it = list2.front();
        var value: u32 = 1;
        while (it) |node| : (it = node.right) {
            if (it == &list2.sentinel) {
                break;
            }
            const l: *T = @fieldParentPtr("node", node);
            try testing.expect(l.data == value);
            value += 1;
        }
    }

    // Traverse backwards.
    {
        var it = list2.back();
        var value: u32 = 5;
        while (it) |node| : (it = node.left) {
            if (it == &list2.sentinel) {
                break;
            }
            const l: *T = @fieldParentPtr("node", node);
            try testing.expect(l.data == value);
            value -= 1;
        }
    }
}
