const std = @import("std");

const suspendFiber = @import("suspend.zig").suspendFiber;

const Awaiter = @import("../core/awaiter.zig").Awaiter;
const Duration = @import("../../runtime/time.zig").Duration;
const Fiber = @import("../core/fiber.zig").Fiber;

const SleepAwaiter = struct {
    const Self = @This();

    delay: Duration = undefined,

    // Awaiter interface
    pub fn afterSuspend(self: *Self, fiber: *Fiber) void {
        fiber.submitTimer(self.delay);
    }

    pub fn awaiter(self: *Self) Awaiter {
        return Awaiter.init(self);
    }
};

pub fn sleepFor(delay: Duration) void {
    var awaiter: SleepAwaiter = .{ .delay = delay };
    suspendFiber(awaiter.awaiter());
}

////////////////////////////////////////////////////////////////////////////////

const spawn = @import("spawn.zig").spawn;
const testing = std.testing;

const Allocator = std.mem.Allocator;
const ConcurrentRuntime = @import("../../runtime/concurrent/concurrent_runtime.zig").ConcurrentRuntime;
const Runnable = @import("../../task/task.zig").Runnable;
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const WaitGroup = @import("../../threads/wait_group.zig").WaitGroup;

const TestRunnable = struct {
    x: i32 = undefined,
    wg: *WaitGroup = undefined,

    pub fn runnable(self: *TestRunnable) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *TestRunnable) void {
        sleepFor(.{ .microseconds = 1 * std.time.us_per_s });
        std.debug.print("{}\n", .{self.x});
        self.wg.done();
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ConcurrentRuntime = ConcurrentRuntime.init(2, allocator);
    defer rt.deinit();

    rt.allowTimers().start();
    defer rt.stop();

    var wg: WaitGroup = .{};
    const x: i32 = 0;
    var task: TestRunnable = .{ .x = x, .wg = &wg };

    wg.add(2);
    try spawn(rt.runtime(), task.runnable(), allocator);
    try spawn(rt.runtime(), task.runnable(), allocator);
    wg.wait();
}
