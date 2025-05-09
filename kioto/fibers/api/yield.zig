const std = @import("std");

const suspendFiber = @import("suspend.zig").suspendFiber;

const Awaiter = @import("../core/awaiter.zig").Awaiter;
const Fiber = @import("../core/fiber.zig").Fiber;

const YieldAwaiter = struct {
    const Self = @This();

    // Awaiter interface
    pub fn afterSuspend(_: *Self, fiber: *Fiber) void {
        fiber.submitTask();
    }

    pub fn awaiter(self: *Self) Awaiter {
        return Awaiter.init(self);
    }
};

pub fn yield() void {
    var awaiter: YieldAwaiter = .{};
    suspendFiber(awaiter.awaiter());
}

////////////////////////////////////////////////////////////////////////////////

const spawn = @import("spawn.zig").spawn;
const testing = std.testing;

const Allocator = std.mem.Allocator;
const ConcurrentRuntime = @import("../../runtime/concurrent/concurrent_runtime.zig").ConcurrentRuntime;
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const Task = @import("../../task/task.zig").Task;
const WaitGroup = @import("../../threads/wait_group.zig").WaitGroup;

const TestRunnable = struct {
    x: *i32 = undefined,
    wg: *WaitGroup = undefined,

    pub fn task(self: *TestRunnable) Task {
        return Task.init(self);
    }

    pub fn run(self: *TestRunnable) void {
        self.action();
        yield();
        self.action();
        yield();
        self.action();
        self.wg.done();
    }

    fn action(self: *TestRunnable) void {
        std.debug.print("{}\n", .{self.x.*});
        self.x.* += 1;
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ConcurrentRuntime = .{};
    rt.init(1, allocator);
    defer rt.deinit();

    rt.start();
    defer rt.stop();

    var wg: WaitGroup = .{};
    var x: i32 = 0;
    var task: TestRunnable = .{ .x = &x, .wg = &wg };

    wg.add(2);
    try spawn(rt.runtime(), task.task(), allocator);
    try spawn(rt.runtime(), task.task(), allocator);
    wg.wait();
}
