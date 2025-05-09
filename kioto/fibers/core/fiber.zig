const std = @import("std");

const Allocator = std.mem.Allocator;
const Awaiter = @import("awaiter.zig").Awaiter;
const Coroutine = @import("coroutine.zig").Coroutine;
const Duration = @import("../../runtime/time.zig").Duration;
const IntrusiveTask = @import("../../task/intrusive_task.zig").IntrusiveTask;
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const Task = @import("../../task/task.zig").Task;

threadlocal var current_fiber: ?*Fiber = null;

pub const Fiber = struct {
    const Self = @This();

    coro: Coroutine = undefined,
    runtime: Runtime = undefined,
    hook: IntrusiveTask = .{},
    awaiter: ?Awaiter = null,
    allocator: Allocator = undefined,
    on_heap: bool = undefined,

    pub fn init(self: *Self, runtime: Runtime, task: Task, allocator: Allocator, on_heap: bool) !void {
        self.coro = try Coroutine.init(task, allocator);
        self.runtime = runtime;
        self.hook.init(Task.init(self));
        self.allocator = allocator;
        self.on_heap = on_heap;
    }

    pub fn deinit(self: *Fiber) void {
        self.coro.deinit();
        if (self.on_heap) {
            self.allocator.destroy(self);
        }
    }

    pub fn submitTask(self: *Fiber) void {
        self.runtime.submitTask(&self.hook);
    }

    pub fn submitTimer(self: *Fiber, delay: Duration) void {
        self.runtime.submitTimer(&self.hook, delay);
    }

    pub fn resumeFiber(self: *Fiber) void {
        const caller: ?*Fiber = current_fiber;
        current_fiber = self;
        self.coro.resumeCoro();
        current_fiber = caller;
        self.dispatch();
    }

    pub fn suspendFiber(self: *Fiber, awaiter: Awaiter) void {
        self.awaiter = awaiter;
        Coroutine.suspendCoro();
    }

    pub fn current() ?*Fiber {
        return current_fiber;
    }

    pub fn isCompleted(self: *const Fiber) bool {
        return self.coro.isCompleted();
    }

    pub fn getRuntime(self: *const Fiber) Runtime {
        return self.runtime;
    }

    fn dispatch(self: *Fiber) void {
        if (self.isCompleted()) {
            self.deinit();
        } else if (self.awaiter != null) {
            var awaiter: Awaiter = self.awaiter.?;
            self.awaiter = null;
            awaiter.afterSuspend(self);
        }
    }

    // Task impl
    pub fn run(self: *Fiber) void {
        self.resumeFiber();
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const ConcurrentRuntime = @import("../../runtime/concurrent/concurrent_runtime.zig").ConcurrentRuntime;
const WaitGroup = @import("../../threads/wait_group.zig").WaitGroup;

const TestRunnable = struct {
    wg: *WaitGroup,

    pub fn task(self: *TestRunnable) Task {
        return Task.init(self);
    }

    pub fn run(self: *TestRunnable) void {
        self.wg.done();
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer testing.expect(!gpa.detectLeaks()) catch @panic("TEST FAIL");

    var runtime: ConcurrentRuntime = .{};
    runtime.init(1, allocator);
    defer runtime.deinit();

    runtime.start();
    defer runtime.stop();

    var wg: WaitGroup = .{};

    var task: TestRunnable = .{ .wg = &wg };
    var fiber1: Fiber = .{};
    try fiber1.init(runtime.runtime(), task.task(), allocator, false);

    var fiber2: Fiber = .{};
    try fiber2.init(runtime.runtime(), task.task(), allocator, false);

    wg.add(2);
    fiber1.submitTask();
    fiber2.submitTask();
    wg.wait();
    try testing.expect(fiber1.isCompleted());
    try testing.expect(fiber2.isCompleted());
}
