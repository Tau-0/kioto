const std = @import("std");

const Awaiter = @import("../core/awaiter.zig").Awaiter;
const Fiber = @import("../core/fiber.zig").Fiber;
const FiberApi = @import("../api.zig");
const List = @import("../../containers/intrusive_list.zig").IntrusiveList;
const Spinlock = @import("../../threads/spinlock.zig").Spinlock;

const WaitQueue = List(EventAwaiter);

const EventAwaiter = struct {
    const Self = @This();

    event: *Event = undefined,
    guard: *Spinlock = undefined,
    fiber: *Fiber = undefined,
    node: WaitQueue.Node = .{},

    pub fn afterSuspend(self: *Self, fiber: *Fiber) void {
        self.fiber = fiber;
        self.event.wait_queue.pushBack(&self.node);
        self.guard.unlock();
    }

    pub fn awaiter(self: *Self) Awaiter {
        return Awaiter.init(self);
    }

    pub fn submit(self: *Self) void {
        self.fiber.submitTask();
    }
};

pub const Event = struct {
    const Self = @This();

    wait_queue: WaitQueue = .{},
    guard: Spinlock = .{},
    fired: bool = false,

    pub fn init(self: *Self) void {
        self.wait_queue.init();
    }

    pub fn wait(self: *Self) void {
        self.guard.lock();
        if (self.fired) {
            self.guard.unlock();
            return;
        }

        var awaiter: EventAwaiter = .{ .event = self, .guard = &self.guard };
        FiberApi.suspendFiber(awaiter.awaiter());
    }

    pub fn fire(self: *Self) void {
        var to_wake: WaitQueue = .{};
        to_wake.init();
        {
            self.guard.lock();
            defer self.guard.unlock();
            self.fired = true;
            to_wake.concatByMoving(&self.wait_queue);
        }

        while (to_wake.nonEmpty()) {
            to_wake.popFrontUnsafe().submit();
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

const TaskA = struct {
    x: *i32 = undefined,
    wg: *WaitGroup = undefined,
    event: *Event = undefined,

    pub fn runnable(self: *TaskA) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *TaskA) void {
        self.event.wait();
        testing.expect(self.event.fired) catch |err| std.debug.panic("Test failed: {}", .{err});
        testing.expect(self.x.* == 10) catch |err| std.debug.panic("Test failed: {}", .{err});
        self.wg.done();
    }
};

const TaskB = struct {
    x: *i32 = undefined,
    wg: *WaitGroup = undefined,
    event: *Event = undefined,

    pub fn runnable(self: *TaskB) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *TaskB) void {
        testing.expect(!self.event.fired) catch |err| std.debug.panic("Test failed: {}", .{err});
        testing.expect(self.x.* == 0) catch |err| std.debug.panic("Test failed: {}", .{err});
        FiberApi.sleepFor(.{ .microseconds = 1 * std.time.us_per_s });
        testing.expect(!self.event.fired) catch |err| std.debug.panic("Test failed: {}", .{err});
        testing.expect(self.x.* == 0) catch |err| std.debug.panic("Test failed: {}", .{err});

        self.x.* = 10;
        self.event.fire();
        self.wg.done();
    }
};

test "manual" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ManualRuntime = ManualRuntime.init(allocator);
    defer rt.deinit();

    var event: Event = .{};
    event.init();

    var wg: WaitGroup = .{};
    var x: i32 = 0;
    var taskA: TaskA = .{ .x = &x, .wg = &wg, .event = &event };
    var taskB: TaskB = .{ .x = &x, .wg = &wg, .event = &event };

    wg.add(6);
    try FiberApi.spawn(rt.runtime(), taskA.runnable(), allocator);
    try FiberApi.spawn(rt.runtime(), taskA.runnable(), allocator);
    try FiberApi.spawn(rt.runtime(), taskA.runnable(), allocator);
    try FiberApi.spawn(rt.runtime(), taskA.runnable(), allocator);
    try FiberApi.spawn(rt.runtime(), taskA.runnable(), allocator);
    try FiberApi.spawn(rt.runtime(), taskB.runnable(), allocator);

    try testing.expect(rt.executor.tasks.len == 6);
    try testing.expect(rt.runLimited(6) == 6);
    try testing.expect(rt.timers.tasks.count() == 1);
    try testing.expect(rt.setClockToNextDeadline() == 1);
    try testing.expect(rt.runOne());
    try testing.expect(rt.runAll() == 5);
    wg.wait();
}

test "concurrent" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ConcurrentRuntime = ConcurrentRuntime.init(6, allocator);
    defer rt.deinit();

    rt.allowTimers().start();
    defer rt.stop();

    var event: Event = .{};
    event.init();

    var wg: WaitGroup = .{};
    var x: i32 = 0;
    var taskA: TaskA = .{ .x = &x, .wg = &wg, .event = &event };
    var taskB: TaskB = .{ .x = &x, .wg = &wg, .event = &event };

    wg.add(6);
    try FiberApi.spawn(rt.runtime(), taskA.runnable(), allocator);
    try FiberApi.spawn(rt.runtime(), taskA.runnable(), allocator);
    try FiberApi.spawn(rt.runtime(), taskA.runnable(), allocator);
    try FiberApi.spawn(rt.runtime(), taskA.runnable(), allocator);
    try FiberApi.spawn(rt.runtime(), taskA.runnable(), allocator);
    try FiberApi.spawn(rt.runtime(), taskB.runnable(), allocator);
    wg.wait();
}

test "prefired" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ConcurrentRuntime = ConcurrentRuntime.init(6, allocator);
    defer rt.deinit();

    rt.allowTimers().start();
    defer rt.stop();

    var event: Event = .{};
    event.init();
    event.fire();

    var wg: WaitGroup = .{};
    var x: i32 = 10;
    var taskA: TaskA = .{ .x = &x, .wg = &wg, .event = &event };

    for (0..6) |_| {
        wg.add(1);
        try FiberApi.spawn(rt.runtime(), taskA.runnable(), allocator);
    }

    wg.wait();
}
