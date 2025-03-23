// TODO: refactoring

const std = @import("std");
const Allocator = std.mem.Allocator;

fn ListNode(comptime T: type) type {
    return struct {
        data: T,
        next: ?*ListNode(T),
        prev: ?*ListNode(T),

        fn init(self: *ListNode(T), data: T, prev: ?*ListNode(T), next: ?*ListNode(T)) *ListNode(T) {
            self.data = data;
            self.prev = prev;
            self.next = next;
            return self;
        }
    };
}

pub fn ListIterator(comptime T: type) type {
    return struct {
        left_ptr: ?*ListNode(T) = null,
        right_ptr: ?*ListNode(T) = null,

        pub fn init(self: *ListIterator(T), list: *List(T)) ListIterator(T) {
            self.left_ptr = list.head;
            self.right_ptr = list.tail;
            return self;
        }

        pub fn deinit(self: ListIterator(T)) !void {
            self.* = undefined;
        }

        pub fn next(self: *ListIterator(T)) ?T {
            if (self.left_ptr) |node| {
                self.left_ptr = node.next;
                return node.data;
            } else {
                return null;
            }
        }

        pub fn next_back(self: ListIterator(T)) ?T {
            if (self.right_ptr) |node| {
                self.right_ptr = node.prev;
                return node.data;
            } else {
                return null;
            }
        }
    };
}

pub fn List(comptime T: type) type {
    return struct {
        head: ?*ListNode(T) = null,
        tail: ?*ListNode(T) = null,
        len: usize = 0,
        alloc: Allocator,

        pub fn init(alloc: Allocator) List(T) {
            return .{
                .alloc = alloc,
            };
        }

        pub fn deinit(self: *List(T)) void {
            if (self.head == null) {
                return;
            }

            self.tail.?.next = null;

            while (self.head) |node| {
                const next = node.next;
                node.* = undefined;
                self.alloc.destroy(node);
                self.head = next;
            }

            self.* = undefined;
        }

        pub fn append(self: *List(T), val: T) !void {
            errdefer self.len -= 1;
            self.len += 1;
            if (self.head == null) {
                self.head = (try self.alloc.create(ListNode(T))).init(val, null, null);
                self.tail = self.head;
                return;
            }

            self.tail.?.next = (try self.alloc.create(ListNode(T))).init(val, self.tail, null);
            self.tail = self.tail.?.next;
        }

        pub fn appendLeft(self: *List(T), val: T) !void {
            errdefer self.len -= 1;
            self.len += 1;
            if (self.head == null) {
                self.head = (try self.alloc.create(ListNode(T))).init(val, null, null);
                self.tail = self.head;
            }

            self.head.?.prev = (try self.alloc.create(ListNode(T))).init(val, null, self.head);
            self.head = self.head.?.prev;
        }

        pub fn appendAll(self: *List(T), data: []const T) !void {
            for (data) |val| {
                try self.append(val);
            }
        }

        pub fn appendList(self: *List(T), other: *List(T)) !void {
            var ptr = other.head;
            while (ptr) |node| : (ptr = node.next) {
                try self.append(node.data);
            }
        }

        pub fn writeTo(self: *List(T), writer: anytype) !void {
            if (self.head == null) {
                return;
            }
            var ptr = self.head.?.next;
            try writer.print("{any}", .{self.head.?.data});

            while (ptr) |node| : (ptr = node.next) {
                try writer.print(", {any}", .{node.data});
                if (ptr == self.tail) break;
            }
            if (ptr.?.next) |node| {
                try writer.print(", {any}, ...", .{node.data});
            }
        }

        pub fn cycle(self: *List(T), pos: usize) !void {
            if (pos >= self.len) {
                return;
            }

            var ptr = self.head;
            for (0..pos) |_| {
                ptr = ptr.?.next;
            }

            self.tail.?.next = ptr;
        }

        pub fn pop(self: *List(T)) ?T {
            if (self.tail) |node| {
                const res = node.data;
                self.tail = node.prev;
                self.alloc.destroy(node);
                self.len -= 1;
                if (self.tail) |new_tail| {
                    new_tail.next = null;
                } else {
                    self.head = null;
                }
                return res;
            } else {
                return null;
            }
        }

        pub fn popLeft(self: *List(T)) ?T {
            if (self.head) |node| {
                const res = node.data;
                self.head = node.next;
                self.alloc.destroy(node);
                self.len -= 1;
                if (self.head) |new_head| {
                    new_head.prev = null;
                } else {
                    self.tail = null;
                }
                return res;
            } else {
                return null;
            }
        }

        pub fn iter(self: *List(T)) ListIterator(T) {
            const iter_t = ListIterator(T){};
            return iter_t.init(self);
        }

        pub fn isEmpty(self: *List(T)) bool {
            return self.len == 0;
        }
    };
}

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var my_list = List(i32).init(alloc);
    defer my_list.deinit();

    try my_list.appendAll(&[_]i32{ 1, 2, 3, 4, 5, 6, 7 });
    _ = my_list.pop();
    _ = my_list.popLeft();
    try my_list.writeTo(std.io.getStdOut().writer());
}
