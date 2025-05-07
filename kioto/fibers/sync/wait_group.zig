const std = @import("std");

const Awaiter = @import("../core/awaiter.zig").Awaiter;
const Fiber = @import("../core/fiber.zig").Fiber;
const FiberApi = @import("../api.zig");
const List = @import("../../containers/intrusive_list.zig").IntrusiveList;
const Spinlock = @import("../../threads/spinlock.zig").Spinlock;

const WaitQueue = List(WaitGroupAwaiter);

const WaitGroupAwaiter = struct {
    const Self = @This();

    wg: *WaitGroup = undefined,
    guard: *Spinlock = undefined,
    fiber: *Fiber = undefined,
    node: WaitQueue.Node = .{},

    pub fn afterSuspend(self: *Self, fiber: *Fiber) void {
        self.fiber = fiber;
        self.wg.wait_queue.pushBack(&self.node);
        self.guard.unlock();
    }

    pub fn awaiter(self: *Self) Awaiter {
        return Awaiter.init(self);
    }

    pub fn submit(self: *Self) void {
        self.fiber.submitTask();
    }
};

pub const WaitGroup = struct {
    const Self = @This();

    wait_queue: WaitQueue = .{},
    guard: Spinlock = .{},
    work: usize = 0,

    pub fn init(self: *Self) void {
        self.wait_queue.init();
    }

    pub fn add(self: *Self, n: usize) void {
        self.guard.lock();
        self.work += n;
        self.guard.unlock();
    }

    pub fn wait(self: *Self) void {
        self.guard.lock();
        if (self.work == 0) {
            self.guard.unlock();
            return;
        }

        var awaiter: WaitGroupAwaiter = .{ .wg = self, .guard = &self.guard };
        FiberApi.suspendFiber(awaiter.awaiter());
    }

    pub fn done(self: *Self) void {
        var to_wake: WaitQueue = .{};
        to_wake.init();
        {
            self.guard.lock();
            self.work -= 1;
            if (self.work == 0) {
                to_wake.concatByMoving(&self.wait_queue);
            }
            self.guard.unlock();
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
const Mutex = @import("mutex.zig").Mutex;
const Runnable = @import("../../task/task.zig").Runnable;
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const ThreadWaitGroup = @import("../../threads/wait_group.zig").WaitGroup;

const TaskWaiter = struct {
    twg: *ThreadWaitGroup = undefined,

    pub fn runnable(self: *TaskWaiter) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *TaskWaiter) void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
        defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
        const allocator = gpa.allocator();

        var rt: ConcurrentRuntime = ConcurrentRuntime.init(6, allocator);
        defer rt.deinit();

        rt.allowTimers().start();
        defer rt.stop();

        var x: i32 = 0;
        var mutex: Mutex = .{};
        var wg: WaitGroup = .{};
        mutex.init();
        wg.init();

        var task_worker: TaskWorker = .{ .x = &x, .mutex = &mutex, .wg = &wg };

        for (0..6) |_| {
            wg.add(1);
            FiberApi.spawn(rt.runtime(), task_worker.runnable(), allocator) catch |err| std.debug.panic("Test failed: {}", .{err});
        }

        wg.wait();
        testing.expect(x == 6) catch |err| std.debug.panic("Test failed: {}", .{err});

        self.twg.done();
    }
};

const TaskWorker = struct {
    x: *i32 = undefined,
    mutex: *Mutex = undefined,
    wg: *WaitGroup = undefined,

    pub fn runnable(self: *TaskWorker) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *TaskWorker) void {
        FiberApi.sleepFor(.{ .microseconds = 1 * std.time.us_per_s });
        self.mutex.lock();
        self.x.* += 1;
        self.mutex.unlock();
        self.wg.done();
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ConcurrentRuntime = ConcurrentRuntime.init(6, allocator);
    defer rt.deinit();

    rt.allowTimers().start();
    defer rt.stop();

    var wg: ThreadWaitGroup = .{};

    var task_waiter: TaskWaiter = .{ .twg = &wg };

    wg.add(1);
    try FiberApi.spawn(rt.runtime(), task_waiter.runnable(), allocator);
    wg.wait();
}
