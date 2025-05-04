const std = @import("std");

const Allocator = std.mem.Allocator;
const Coroutine = @import("coroutine.zig").Coroutine;
const Runnable = @import("../../task/task.zig").Runnable;
const Runtime = @import("../../runtime/runtime.zig").Runtime;

threadlocal var current_fiber: ?*Fiber = null;

pub const Fiber = struct {
    coro: Coroutine = undefined,
    runtime: Runtime = undefined,

    pub fn init(runtime: Runtime, task: Runnable, allocator: Allocator) !Fiber {
        return .{
            .coro = try Coroutine.init(task, allocator),
            .runtime = runtime,
        };
    }

    pub fn deinit(self: *Fiber) void {
        self.coro.deinit();
    }

    pub fn submit(self: *Fiber) void {
        self.runtime.submitTask(self.runnable());
    }

    pub fn resumeFiber(self: *Fiber) void {
        const caller: ?*Fiber = current_fiber;
        current_fiber = self;
        self.coro.resumeCoro();
        current_fiber = caller;
        self.dispatch();
    }

    pub fn suspendFiber(self: *Fiber) void {
        self.coro.suspendCoro();
    }

    pub fn current() ?*Fiber {
        return current_fiber;
    }

    pub fn isCompleted(self: *const Fiber) bool {
        return self.coro.isCompleted();
    }

    fn dispatch(self: *Fiber) void {
        if (self.isCompleted()) {
            self.deinit();
        }
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

const ConcurrentRuntime = @import("../../runtime/concurrent/concurrent_runtime.zig").ConcurrentRuntime;
const WaitGroup = @import("../../threads/wait_group.zig").WaitGroup;

const TaskA = struct {
    wg: *WaitGroup,

    pub fn runnable(self: *TaskA) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *TaskA) void {
        std.debug.print("2\n", .{});
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
        std.debug.print("4\n", .{});
        self.wg.done();
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer testing.expect(!gpa.detectLeaks()) catch @panic("TEST FAIL");

    var runtime: ConcurrentRuntime = ConcurrentRuntime.init(1, allocator);
    defer runtime.deinit();

    runtime.start();
    defer runtime.stop();

    var wg: WaitGroup = .{};

    var t1: TaskA = .{ .wg = &wg };
    var fiber1 = try Fiber.init(runtime.runtime(), t1.runnable(), allocator);

    var t2: TaskB = .{ .wg = &wg };
    var fiber2 = try Fiber.init(runtime.runtime(), t2.runnable(), allocator);

    wg.add(2);
    fiber1.submit();
    fiber2.submit();
    wg.wait();
    testing.expect(fiber1.isCompleted()) catch @panic("TEST FAIL");
    testing.expect(fiber2.isCompleted()) catch @panic("TEST FAIL");
}
