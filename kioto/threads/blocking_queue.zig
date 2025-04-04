const std = @import("std");

const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const Condition = std.Thread.Condition;
const DoublyLinkedList = std.DoublyLinkedList;
const Mutex = std.Thread.Mutex;

// Unbounded blocking MPMC queue
pub fn BlockingQueue(comptime T: type) type {
    return struct {
        const List = DoublyLinkedList(T);
        pub const Self = @This();
        pub const Node = List.Node;

        buffer: List = .{},
        mutex: Mutex = .{},
        has_values: Condition = .{},
        is_open: bool = true,
        allocator: Allocator = undefined,

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            assert(self.isEmpty());
        }

        pub fn put(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (!self.is_open) {
                return;
            }

            var n: *Node = try self.allocator.create(Node);
            n.data = value;
            self.buffer.append(n);
            self.has_values.signal();
        }

        pub fn take(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            while (self.isEmpty() and self.is_open) {
                self.has_values.wait(&self.mutex);
            }

            if (self.isEmpty()) {
                return null;
            }
            return self.takeLocked();
        }

        fn takeLocked(self: *Self) T {
            assert(!self.isEmpty());
            const node: *Node = self.buffer.popFirst().?;
            const value: T = node.data;
            self.allocator.destroy(node);
            return value;
        }

        fn isEmpty(self: *Self) bool {
            return self.buffer.len == 0;
        }

        pub fn close(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.is_open = false;
            self.has_values.broadcast();
        }
    };
}

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const WaitGroup = @import("wait_group.zig").WaitGroup;

fn producer(q: *BlockingQueue(u64), wg: *WaitGroup) void {
    for (0..5) |i| {
        q.put(i) catch |err| std.debug.print("Error: {}\n", .{err});
        std.debug.print("Produced: {}\n", .{i});
        std.Thread.sleep(std.time.ns_per_s / 4);
    }
    q.close();
    wg.done();
}

fn consumer(q: *BlockingQueue(u64), wg: *WaitGroup) void {
    while (q.take()) |elem| {
        std.debug.print("Consumed: {}\n", .{elem});
    }
    wg.done();
}

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(!gpa.detectLeaks()) catch @panic("TEST FAIL");

    const alloc = gpa.allocator();
    var queue = BlockingQueue(u64).init(alloc);
    defer queue.deinit();

    var wg: WaitGroup = .{};
    wg.add(2);
    var cons = try std.Thread.spawn(.{}, consumer, .{ &queue, &wg });
    var prod = try std.Thread.spawn(.{}, producer, .{ &queue, &wg });
    wg.wait();

    prod.join();
    cons.join();
}
