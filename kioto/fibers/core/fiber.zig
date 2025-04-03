const std = @import("std");

const Allocator = std.mem.Allocator;
const Coroutine = @import("coroutine.zig").Coroutine;
const Runnable = @import("../../task/task.zig").Runnable;
const ThreadPool = @import("../../runtime/thread_pool.zig").ThreadPool;

threadlocal var current_fiber: ?*Fiber = null;

pub const Fiber = struct {
    coro: Coroutine = undefined,
    scheduler: *ThreadPool = undefined,

    pub fn init(scheduler: *ThreadPool, task: Runnable, allocator: Allocator) !Fiber {
        return .{
            .coro = try Coroutine.init(task, allocator),
            .scheduler = scheduler,
        };
    }

    pub fn deinit(self: *Fiber) void {
        self.coro.deinit();
    }

    pub fn submit(self: *Fiber) !void {
        try self.scheduler.submit(self.runnable());
    }

    pub fn resumeFiber(self: *Fiber) void {
        const caller: ?*Fiber = current_fiber;
        current_fiber = self;
        self.coro.resumeCoro();
        current_fiber = caller;
        if (self.isCompleted()) {
            // delete this;
            // return;
        }
    }

    pub fn suspendFiber(_: *Fiber) void {
        Coroutine.suspendCoro();
    }

    pub fn current() ?*Fiber {
        return current_fiber;
    }

    pub fn isCompleted(self: *const Fiber) bool {
        return self.coro.isCompleted();
    }

    // Runnable impl
    fn runnable(self: *Fiber) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *Fiber) void {
        self.resumeFiber();
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const WaitGroup = @import("../../threads/wait_group.zig").WaitGroup;

const TaskA = struct {
    wg: *WaitGroup,

    pub fn runnable(self: *TaskA) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *TaskA) void {
        std.debug.print("2\n", .{});
        // Fiber.current().?.suspendFiber();
        std.debug.print("5\n", .{});
        self.wg.done();
    }
};

const TaskB = struct {
    wg: *WaitGroup,

    pub fn runnable(self: *TaskB) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *TaskB) void {
        std.debug.print("1\n", .{});
        // Fiber.current().?.suspendFiber();
        std.debug.print("4\n", .{});
        self.wg.done();
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();

    var tp: ThreadPool = try ThreadPool.init(1, allocator);
    try tp.start();
    defer tp.deinit();
    defer tp.stop();

    var wg: WaitGroup = .{};

    var t1: TaskA = .{ .wg = &wg };
    var fiber1 = try Fiber.init(&tp, t1.runnable(), allocator);

    var t2: TaskB = .{ .wg = &wg };
    var fiber2 = try Fiber.init(&tp, t2.runnable(), allocator);

    defer testing.expect(!gpa.detectLeaks()) catch @panic("TEST FAIL");
    defer fiber1.deinit();
    defer fiber2.deinit();
    defer testing.expect(fiber1.isCompleted()) catch @panic("TEST FAIL");
    defer testing.expect(fiber2.isCompleted()) catch @panic("TEST FAIL");

    wg.add(2);
    try fiber1.submit();
    try fiber2.submit();
    wg.wait();
}
