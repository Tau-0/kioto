const std = @import("std");

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

        pub fn init(self: *Self) void {
            self.wait_queue.init();
        }

        pub fn deinit(self: *Self) void {
            std.debug.assert(self.wait_queue.isEmpty());
        }

        pub fn send(self: *Self, value: T) void {
            self.guard.lock();
            if (self.wait_queue.nonEmpty() and self.state == .OnlyReceivers) {
                var awaiter: *ChannelAwaiter = self.wait_queue.popFrontUnsafe();
                awaiter.setValue(value);
                self.guard.unlock();
                awaiter.submit();
                return;
            }

            var awaiter: ChannelAwaiter = .{ .state = self, .guard = &self.guard };
            awaiter.setValue(value);
            self.state = .OnlySenders;
            FiberApi.suspendFiber(awaiter.awaiter());
        }

        pub fn receive(self: *Self) T {
            self.guard.lock();
            if (self.wait_queue.nonEmpty() and self.state == .OnlySenders) {
                var awaiter: *ChannelAwaiter = self.wait_queue.popFrontUnsafe();
                self.guard.unlock();
                const value: T = awaiter.getValue();
                awaiter.submit();
                return value;
            }

            var awaiter: ChannelAwaiter = .{ .state = self, .guard = &self.guard };
            self.state = .OnlyReceivers;
            FiberApi.suspendFiber(awaiter.awaiter());
            return awaiter.getValue();
        }
    };
}

pub fn UnbufferedChannel(comptime T: type) type {
    return struct {
        const Self = @This();

        state: State(T) = .{},

        pub fn init(self: *Self) void {
            self.state.init();
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

const Allocator = std.mem.Allocator;
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const Task = @import("../../task/task.zig").Task;
const WaitGroup = @import("../../threads/wait_group.zig").WaitGroup;

const TestRunnable = struct {
    chan: *UnbufferedChannel(i32) = undefined,
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
        self.chan.send(0);
        self.ping_pong();
    }

    fn second(self: *TestRunnable) void {
        self.ping_pong();
        const last_value: i32 = self.chan.receive();
        testing.expect(last_value == 20) catch |err| std.debug.panic("Test failed: {}\n", .{err});
    }

    fn ping_pong(self: *TestRunnable) void {
        for (0..10) |_| {
            const value: i32 = self.chan.receive();
            self.chan.send(value + 1);
        }
    }
};

test "ping-pong" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ConcurrentRuntime = .{};
    rt.init(6, allocator);
    defer rt.deinit();

    rt.allowTimers().start();
    defer rt.stop();

    var channel: UnbufferedChannel(i32) = .{};
    channel.init();
    defer channel.deinit();

    var wg: WaitGroup = .{};

    var first: TestRunnable = .{ .chan = &channel, .wg = &wg, .is_first = true };
    var second: TestRunnable = .{ .chan = &channel, .wg = &wg };

    wg.add(2);
    try FiberApi.spawn(rt.runtime(), second.task(), allocator);
    try FiberApi.spawn(rt.runtime(), first.task(), allocator);
    wg.wait();
}
