const std = @import("std");

const Awaiter = @import("../core/awaiter.zig").Awaiter;
const Fiber = @import("../core/fiber.zig").Fiber;
const FiberApi = @import("../api.zig");
const List = @import("../../containers/intrusive_list.zig").IntrusiveList;
const Spinlock = @import("../../threads/spinlock.zig").Spinlock;

const WaitQueue = List(MutexAwaiter);

const MutexAwaiter = struct {
    const Self = @This();

    mutex: *Mutex = undefined,
    guard: *Spinlock = undefined,
    fiber: *Fiber = undefined,
    node: WaitQueue.Node = .{},

    pub fn afterSuspend(self: *Self, fiber: *Fiber) void {
        self.fiber = fiber;
        self.mutex.wait_queue.pushBack(&self.node);
        self.guard.unlock();
    }

    pub fn awaiter(self: *Self) Awaiter {
        return Awaiter.init(self);
    }

    pub fn submit(self: *Self) void {
        self.fiber.submitTask();
    }
};

pub const Mutex = struct {
    const Self = @This();

    wait_queue: WaitQueue = .{},
    guard: Spinlock = .{},
    locked: bool = false,

    pub fn init(self: *Self) void {
        self.wait_queue.init();
    }

    pub fn lock(self: *Self) void {
        self.guard.lock();
        if (!self.locked) {
            self.locked = true;
            self.guard.unlock();
            return;
        }

        var awaiter: MutexAwaiter = .{ .mutex = self, .guard = &self.guard };
        FiberApi.suspendFiber(awaiter.awaiter());
    }

    pub fn tryLock(self: *Self) bool {
        self.guard.lock();
        defer self.guard.unlock();
        if (self.locked) {
            return false;
        }

        self.locked = true;
        return true;
    }

    pub fn unlock(self: *Self) void {
        self.guard.lock();
        std.debug.assert(self.locked);
        var to_wake = self.wait_queue.popFront();
        if (to_wake == null) {
            self.locked = false;
            self.guard.unlock();
        } else {
            self.guard.unlock();
            to_wake.?.submit();
        }
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const ConcurrentRuntime = @import("../../runtime/concurrent/concurrent_runtime.zig").ConcurrentRuntime;
const ManualRuntime = @import("../../runtime/manual/manual_runtime.zig").ManualRuntime;

const Allocator = std.mem.Allocator;
const Runnable = @import("../../task/task.zig").Runnable;
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const WaitGroup = @import("../../threads/wait_group.zig").WaitGroup;

const Task = struct {
    counter: *i64 = undefined,
    mutex: *Mutex = undefined,
    wg: *WaitGroup = undefined,

    pub fn runnable(self: *Task) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *Task) void {
        for (0..10_000) |_| {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.counter.* += 1;
        }
        self.wg.done();
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ManualRuntime = ManualRuntime.init(allocator);
    defer rt.deinit();

    var mutex: Mutex = .{};
    mutex.init();

    var wg: WaitGroup = .{};
    var counter: i64 = 0;
    var task: Task = .{ .counter = &counter, .mutex = &mutex, .wg = &wg };

    wg.add(1);
    try FiberApi.spawn(rt.runtime(), task.runnable(), allocator);
    try testing.expect(rt.runAll() == 1);
    wg.wait();

    try testing.expect(counter == 10_000);
}

test "stress" {
    std.testing.log_level = .debug;

    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ConcurrentRuntime = ConcurrentRuntime.init(6, allocator);
    defer rt.deinit();

    rt.start();
    defer rt.stop();

    var mutex: Mutex = .{};
    mutex.init();

    var wg: WaitGroup = .{};
    var counter: i64 = 0;
    var task: Task = .{ .counter = &counter, .mutex = &mutex, .wg = &wg };

    for (0..6) |_| {
        wg.add(1);
        try FiberApi.spawn(rt.runtime(), task.runnable(), allocator);
    }

    wg.wait();
    try testing.expect(counter == 60_000);
}
