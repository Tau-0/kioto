const std = @import("std");

const assert = std.debug.assert;

// Circular doubly-linked intrusive list
pub fn IntrusiveList(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Node = struct {
            left: ?*Node = null, // to head
            right: ?*Node = null, // to tail

            pub fn isLinked(self: *const Node) bool {
                return !self.isUnlinked();
            }

            pub fn isUnlinked(self: *const Node) bool {
                return self.left == null and self.right == null;
            }

            pub fn linkAfter(self: *Node, target: *Node) void {
                assert(self.isUnlinked());
                self.left = target;
                self.right = target.right;

                assert(target.right != null);
                var after_target: *Node = target.right.?;
                after_target.left = self;
                target.right = self;
            }

            pub fn linkBefore(self: *Node, target: *Node) void {
                assert(self.isUnlinked());
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

            pub fn asItem(self: *Node) *T {
                return @alignCast(@fieldParentPtr("node", self));
            }
        };

        // Sentinel <-> Head <-> ... <-> Tail <-> Sentinel
        // Sentinel->Left == Tail
        // Sentinel->Right == Head
        sentinel: Node = .{},

        pub fn init(self: *Self) void {
            comptime assert(@hasField(T, "node") and @FieldType(T, "node") == Self.Node);
            self.sentinel.left = &self.sentinel;
            self.sentinel.right = &self.sentinel;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.sentinel.left == &self.sentinel;
        }

        pub fn nonEmpty(self: *const Self) bool {
            return self.sentinel.left != &self.sentinel;
        }

        fn backNode(self: *const Self) *Node {
            return self.sentinel.left.?;
        }

        fn frontNode(self: *const Self) *Node {
            return self.sentinel.right.?;
        }

        pub fn back(self: *const Self) ?*T {
            if (self.isEmpty()) {
                return null;
            }
            return self.backUnsafe();
        }

        pub fn front(self: *const Self) ?*T {
            if (self.isEmpty()) {
                return null;
            }
            return self.frontUnsafe();
        }

        pub fn backUnsafe(self: *const Self) *T {
            assert(self.nonEmpty());
            return self.backNode().asItem();
        }

        pub fn frontUnsafe(self: *const Self) *T {
            assert(self.nonEmpty());
            return self.frontNode().asItem();
        }

        // Move all nodes from rhs to lhs
        // Post-condition: rhs is empty
        pub fn concatByMoving(lhs: *Self, rhs: *Self) void {
            if (rhs.isEmpty()) {
                return;
            }

            var rhs_head: *Node = rhs.frontNode();
            var rhs_tail: *Node = rhs.backNode();
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

        pub fn popBack(self: *Self) ?*T {
            if (self.isEmpty()) {
                return null;
            }
            return self.popBackUnsafe();
        }

        pub fn popFront(self: *Self) ?*T {
            if (self.isEmpty()) {
                return null;
            }
            return self.popFrontUnsafe();
        }

        pub fn popBackUnsafe(self: *Self) *T {
            assert(self.nonEmpty());
            var node: *Node = self.backNode();
            node.unlink();
            return node.asItem();
        }

        pub fn popFrontUnsafe(self: *Self) *T {
            assert(self.nonEmpty());
            var node: *Node = self.frontNode();
            node.unlink();
            return node.asItem();
        }

        pub fn length(self: *const Self) usize {
            var size: usize = 0;
            var it: *Node = self.frontNode();
            while (it != &self.sentinel) : (it = it.right.?) {
                size += 1;
            }
            return size;
        }
    };
}

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

test "basic" {
    const T = struct {
        data: u32,
        node: IntrusiveList(@This()).Node = .{},
    };
    var list: IntrusiveList(T) = .{};
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
    try testing.expect(list.length() == 5);

    // Traverse forwards.
    {
        var it = &list.frontUnsafe().node;
        var value: u32 = 1;
        while (it != &list.sentinel) : (it = it.right.?) {
            const l: *T = it.asItem();
            try testing.expect(l.data == value);
            value += 1;
        }
    }

    // Traverse backwards.
    {
        var it = &list.backUnsafe().node;
        var value: u32 = 5;
        while (it != &list.sentinel) : (it = it.left.?) {
            const l: *T = it.asItem();
            try testing.expect(l.data == value);
            value -= 1;
        }
    }

    _ = list.popFront(); // {2, 3, 4, 5}
    try testing.expect(list.length() == 4);
    _ = list.popBack(); // {2, 3, 4}
    try testing.expect(list.length() == 3);
    three.node.unlink(); // {2, 4}
    try testing.expect(list.length() == 2);

    try testing.expect(list.frontUnsafe().data == 2);
    try testing.expect(list.backUnsafe().data == 4);
}

test "concatenation" {
    const T = struct {
        data: u32,
        node: IntrusiveList(@This()).Node = .{},
    };
    var list1: IntrusiveList(T) = .{};
    var list2: IntrusiveList(T) = .{};
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
    try testing.expect(list1.length() == 2);
    try testing.expect(list2.length() == 3);

    list1.concatByMoving(&list2);
    try testing.expect(list1.length() == 5);
    try testing.expect(list2.length() == 0);

    try testing.expect(list1.back() == &five);
    try testing.expect(list2.isEmpty());

    // Traverse forwards.
    {
        var it = &list1.frontUnsafe().node;
        var value: u32 = 1;
        while (it != &list1.sentinel) : (it = it.right.?) {
            const l: *T = it.asItem();
            try testing.expect(l.data == value);
            value += 1;
        }
    }

    // Traverse backwards.
    {
        var it = &list1.backUnsafe().node;
        var value: u32 = 5;
        while (it != &list1.sentinel) : (it = it.left.?) {
            const l: *T = it.asItem();
            try testing.expect(l.data == value);
            value -= 1;
        }
    }

    // Swap them back, this verifies that concatenating to an empty list works.
    list2.concatByMoving(&list1);
    try testing.expect(list1.length() == 0);
    try testing.expect(list2.length() == 5);

    // Traverse forwards.
    {
        var it = &list2.frontUnsafe().node;
        var value: u32 = 1;
        while (it != &list2.sentinel) : (it = it.right.?) {
            const l: *T = it.asItem();
            try testing.expect(l.data == value);
            value += 1;
        }
    }

    // Traverse backwards.
    {
        var it = &list2.backUnsafe().node;
        var value: u32 = 5;
        while (it != &list2.sentinel) : (it = it.left.?) {
            const l: *T = it.asItem();
            try testing.expect(l.data == value);
            value -= 1;
        }
    }
}
