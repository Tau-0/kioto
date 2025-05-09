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
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const Task = @import("../../task/task.zig").Task;
const WaitGroup = @import("../../threads/wait_group.zig").WaitGroup;

const TestRunnable = struct {
    wg: *WaitGroup = undefined,

    pub fn task(self: *TestRunnable) Task {
        return Task.init(self);
    }

    pub fn run(self: *TestRunnable) void {
        sleepFor(.{ .microseconds = 1 * std.time.us_per_s });
        self.wg.done();
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ConcurrentRuntime = .{};
    rt.init(2, allocator);
    defer rt.deinit();

    rt.allowTimers().start();
    defer rt.stop();

    var wg: WaitGroup = .{};
    var task: TestRunnable = .{ .wg = &wg };

    wg.add(2);
    try spawn(rt.runtime(), task.task(), allocator);
    try spawn(rt.runtime(), task.task(), allocator);
    wg.wait();
}
