const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Clock = @import("manual_clock.zig").ManualClock;
const Executor = @import("manual_executor.zig").ManualExecutor;
const Runnable = @import("../../task/task.zig").Runnable;
const TimerQueue = @import("timer_queue.zig").TimerQueue;

pub const ManualRuntime = struct {
    const TimePoint = Clock.TimePoint;
    const Duration = Clock.Duration;

    executor: Executor = undefined,
    timers: TimerQueue = undefined,
    clock: Clock = .{},
    allocator: Allocator = undefined,

    pub fn init(allocator: Allocator) ManualRuntime {
        return .{
            .executor = Executor.init(allocator),
            .timers = TimerQueue.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ManualRuntime) void {
        self.timers.deinit();
        self.executor.deinit();
    }

    // Runtime interface
    pub fn submitTask(self: *ManualRuntime, runnable: Runnable) !void {
        try self.executor.submit(runnable);
    }

    pub fn submitTimer(self: *ManualRuntime, runnable: Runnable, delay: Duration) !void {
        const deadline: TimePoint = .{ .microseconds = self.clock.now().microseconds + delay.microseconds };
        try self.timers.push(runnable, deadline);
    }

    // Tasks
    pub fn runOne(self: *ManualRuntime) bool {
        return self.executor.runOne();
    }

    pub fn runLimited(self: *ManualRuntime, limit: usize) usize {
        return self.executor.runLimited(limit);
    }

    pub fn runAll(self: *ManualRuntime) usize {
        return self.executor.runAll();
    }

    // Timers
    pub fn advanceClock(self: *ManualRuntime, delta: Duration) usize {
        self.clock.advance(delta);
        return self.submitReadyTimers();
    }

    pub fn setClockToNextDeadline(self: *ManualRuntime) usize {
        if (self.timers.isEmpty()) {
            return 0;
        }

        self.clock.set(self.timers.nextDeadline());
        return self.submitReadyTasks();
    }

    // Misc
    pub fn isEmpty(self: *const ManualRuntime) bool {
        return self.executor.isEmpty() and self.timers.isEmpty();
    }

    fn submitReadyTasks(self: *ManualRuntime) usize {
        var tasks: ArrayList(Runnable) = self.timers.takeReadyTasks(self.clock.now(), self.allocator) catch |err| std.debug.panic("Can not submit ready tasks; error: {}\n", .{err});
        defer tasks.deinit();
        for (tasks.items) |t| {
            self.submitTask(t) catch |err| std.debug.panic("Can not submit ready tasks; error: {}\n", .{err});
        }
        return tasks.items.len;
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const TestRunnable = struct {
    x: i32 = undefined,

    pub fn runnable(self: *TestRunnable) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *TestRunnable) void {
        std.debug.print("{}\n", .{self.x});
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var manual: ManualRuntime = ManualRuntime.init(allocator);
    defer manual.deinit();

    var task1: TestRunnable = .{ .x = 100 };
    var task2: TestRunnable = .{ .x = 200 };
    var task3: TestRunnable = .{ .x = 300 };

    try manual.submitTask(task1.runnable());
    try manual.submitTask(task2.runnable());

    try manual.submitTimer(task3.runnable(), .{ .microseconds = 1000 });
    try manual.submitTimer(task3.runnable(), .{ .microseconds = 1000 });
    try manual.submitTimer(task3.runnable(), .{ .microseconds = 2000 });

    testing.expect(manual.runOne()) catch @panic("TEST FAIL");
    testing.expect(manual.runOne()) catch @panic("TEST FAIL");

    testing.expect(manual.setClockToNextDeadline() == 2) catch @panic("TEST FAIL");
    testing.expect(manual.timers.tasks.count() == 1) catch @panic("TEST FAIL");

    testing.expect(manual.runAll() == 2) catch @panic("TEST FAIL");

    testing.expect(manual.setClockToNextDeadline() == 1) catch @panic("TEST FAIL");
    testing.expect(manual.timers.tasks.count() == 0) catch @panic("TEST FAIL");

    testing.expect(manual.runAll() == 1) catch @panic("TEST FAIL");
    testing.expect(manual.isEmpty()) catch @panic("TEST FAIL");
}
