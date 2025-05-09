const std = @import("std");

const Allocator = std.mem.Allocator;
const Awaiter = @import("../core/awaiter.zig").Awaiter;
const Fiber = @import("../core/fiber.zig").Fiber;
const FiberApi = @import("../api.zig");
const List = @import("../../containers/intrusive_list.zig").IntrusiveList;
const Spinlock = @import("../../threads/spinlock.zig").Spinlock;

fn State(comptime T: type) type {
    return struct {
        const Self = @This();

        const WaitQueue = List(ChannelAwaiter);

        const QueueState = enum {
            OnlyReceivers,
            OnlySenders,
        };

        const ChannelAwaiter = struct {
            state: *Self = undefined,
            fiber: *Fiber = undefined,
            guard: *Spinlock = undefined,
            value: ?T = null,
            node: WaitQueue.Node = .{},

            pub fn afterSuspend(self: *ChannelAwaiter, fiber: *Fiber) void {
                self.fiber = fiber;
                self.state.wait_queue.pushBack(&self.node);
                self.guard.unlock();
            }

            pub fn awaiter(self: *ChannelAwaiter) Awaiter {
                return Awaiter.init(self);
            }

            pub fn submit(self: *ChannelAwaiter) void {
                self.fiber.submitTask();
            }

            pub fn setValue(self: *ChannelAwaiter, value: T) void {
                std.debug.assert(self.value == null);
                self.value = value;
            }

            pub fn getValue(self: *const ChannelAwaiter) T {
                std.debug.assert(self.value != null);
                return self.value.?;
            }
        };

        wait_queue: List(ChannelAwaiter) = .{},
        guard: Spinlock = .{},
        state: QueueState = .OnlyReceivers,
        buffer: []T = undefined,
        message_queue: std.fifo.LinearFifo(T, .Slice) = undefined,
        capacity: usize = 0,
        allocator: Allocator = undefined,

        pub fn init(self: *Self, capacity: usize, allocator: Allocator) !void {
            std.debug.assert(capacity > 0);

            self.buffer = try allocator.alloc(T, capacity);
            self.message_queue = std.fifo.LinearFifo(T, .Slice).init(self.buffer[0..]);

            self.wait_queue.init();
            self.capacity = capacity;
            self.allocator = allocator;
        }

        pub fn deinit(self: *Self) void {
            std.debug.assert(self.wait_queue.isEmpty());
            std.debug.assert(self.message_queue.count == 0);
            self.allocator.free(self.buffer);
        }

        pub fn send(self: *Self, value: T) void {
            self.guard.lock();
            if (self.wait_queue.nonEmpty() and self.state == .OnlyReceivers) {
                var awaiter: *ChannelAwaiter = self.wait_queue.popFrontUnsafe();
                awaiter.setValue(value);
                self.guard.unlock();
                awaiter.submit();
            } else if (self.message_queue.count < self.capacity) {
                self.message_queue.writeItemAssumeCapacity(value);
                self.guard.unlock();
            } else {
                var awaiter: ChannelAwaiter = .{ .state = self, .guard = &self.guard };
                awaiter.setValue(value);
                self.state = .OnlySenders;
                FiberApi.suspendFiber(awaiter.awaiter());
            }
        }

        pub fn receive(self: *Self) T {
            self.guard.lock();
            if (self.message_queue.count != 0) {
                const value: T = self.message_queue.readItem().?;
                if (self.wait_queue.nonEmpty() and self.state == .OnlySenders) {
                    var awaiter: *ChannelAwaiter = self.wait_queue.popFrontUnsafe();
                    self.message_queue.writeItemAssumeCapacity(awaiter.getValue());
                    self.guard.unlock();
                    awaiter.submit();
                } else {
                    self.guard.unlock();
                }
                return value;
            } else {
                var awaiter: ChannelAwaiter = .{ .state = self, .guard = &self.guard };
                self.state = .OnlyReceivers;
                FiberApi.suspendFiber(awaiter.awaiter());
                return awaiter.getValue();
            }
        }
    };
}

pub fn BufferedChannel(comptime T: type) type {
    return struct {
        const Self = @This();

        state: State(T) = .{},

        pub fn init(self: *Self, capacity: usize, allocator: Allocator) !void {
            try self.state.init(capacity, allocator);
        }

        pub fn deinit(self: *Self) void {
            self.state.deinit();
        }

        pub fn send(self: *Self, value: T) void {
            self.state.send(value);
        }

        pub fn receive(self: *Self) T {
            return self.state.receive();
        }
    };
}

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const ConcurrentRuntime = @import("../../runtime/concurrent/concurrent_runtime.zig").ConcurrentRuntime;
const ManualRuntime = @import("../../runtime/manual/manual_runtime.zig").ManualRuntime;

const Runtime = @import("../../runtime/runtime.zig").Runtime;
const Task = @import("../../task/task.zig").Task;
const WaitGroup = @import("../../threads/wait_group.zig").WaitGroup;

const TestRunnable = struct {
    chan_first: *BufferedChannel(usize) = undefined,
    chan_second: *BufferedChannel(usize) = undefined,
    wg: *WaitGroup = undefined,
    is_first: bool = false,

    pub fn task(self: *TestRunnable) Task {
        return Task.init(self);
    }

    pub fn run(self: *TestRunnable) void {
        if (self.is_first) {
            self.first();
        } else {
            self.second();
        }
        self.wg.done();
    }

    fn first(self: *TestRunnable) void {
        produce(self.chan_first, 1);
        self.consume(self.chan_second);
    }

    fn second(self: *TestRunnable) void {
        self.consume(self.chan_first);
        produce(self.chan_second, 2);
    }

    fn produce(chan: *BufferedChannel(usize), mult: usize) void {
        for (0..10) |i| {
            chan.send(i * mult);
        }
    }

    fn consume(self: *TestRunnable, chan: *BufferedChannel(usize)) void {
        for (0..10) |i| {
            const value: usize = chan.receive();
            const expected = if (self.is_first) i * 2 else i;
            testing.expect(value == expected) catch |err| std.debug.panic("Test failed: {}\n", .{err});
        }
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ConcurrentRuntime = .{};
    rt.init(1, allocator);
    defer rt.deinit();

    rt.allowTimers().start();
    defer rt.stop();

    var channel_first: BufferedChannel(usize) = .{};
    try channel_first.init(1, allocator);
    defer channel_first.deinit();

    var channel_second: BufferedChannel(usize) = .{};
    try channel_second.init(2, allocator);
    defer channel_second.deinit();

    var wg: WaitGroup = .{};

    var first: TestRunnable = .{ .chan_first = &channel_first, .chan_second = &channel_second, .wg = &wg, .is_first = true };
    var second: TestRunnable = .{ .chan_first = &channel_first, .chan_second = &channel_second, .wg = &wg };

    wg.add(2);
    try FiberApi.spawn(rt.runtime(), second.task(), allocator);
    try FiberApi.spawn(rt.runtime(), first.task(), allocator);

    wg.wait();
}
