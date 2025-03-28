const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;

// Unbounded blocking MPMC queue
pub fn BlockingQueue(comptime T: type) type {
    return struct {
        const List = std.DoublyLinkedList(T);
        pub const Self = @This();
        pub const Node = List.Node;

        buffer: List = .{},
        mutex: std.Thread.Mutex = .{},
        has_values: std.Thread.Condition = .{},
        is_open: bool = true,
        allocator: std.mem.Allocator = undefined,

        pub fn init(allocator: std.mem.Allocator) Self {
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
            debug.assert(!self.isEmpty());
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

fn producer(q: *BlockingQueue(u64)) void {
    for (0..10) |i| {
        q.put(i) catch |err| debug.print("Error: {}\n", .{err});
        debug.print("Produced: {}\n", .{i});
    }
}

fn consumer(q: *BlockingQueue(u64)) void {
    while (q.take()) |elem| {
        debug.print("Consumed: {}\n", .{elem});
    }
}

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch unreachable;

    const alloc = gpa.allocator();
    var queue = BlockingQueue(u64).init(alloc);
    defer queue.deinit();

    var prod = try std.Thread.spawn(.{}, producer, .{&queue});
    var cons = try std.Thread.spawn(.{}, consumer, .{&queue});

    std.time.sleep(1 * std.time.ns_per_s);
    queue.close();

    prod.join();
    cons.join();
}
