const std = @import("std");

const time = @import("../time.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Runnable = @import("../../task/task.zig").Runnable;
const ThreadPool = @import("thread_pool.zig").ThreadPool;
const TimerThread = @import("timer_thread.zig").TimerThread;

pub const MultiThreadedRuntime = struct {
    const Self = @This();

    pool: ThreadPool = undefined,
    timer_thread: ?TimerThread = null,
    allocator: Allocator = undefined,

    pub fn init(worker_count: usize, allocator: Allocator) Self {
        return .{
            .pool = ThreadPool.init(worker_count, allocator) catch unreachable,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.timer_thread != null) {
            self.timer_thread.?.deinit();
        }
        self.pool.deinit();
    }

    pub fn start(self: *Self) void {
        self.pool.start() catch unreachable;
        if (self.timer_thread != null) {
            self.timer_thread.?.start() catch unreachable;
        }
    }

    pub fn stop(self: *Self) void {
        if (self.timer_thread != null) {
            self.timer_thread.?.stop();
        }
        self.pool.stop();
    }

    pub fn allowTimers(self: *Self) *Self {
        self.timer_thread = TimerThread.init(&self.pool, self.allocator);
        return self;
    }

    // Runtime interface
    pub fn submitTask(self: *Self, runnable: Runnable) !void {
        try self.pool.submit(runnable);
    }

    pub fn submitTimer(self: *Self, runnable: Runnable, delay: time.Duration) !void {
        try self.timer_thread.?.submit(runnable, delay);
    }

    pub fn here(self: *const Self) bool {
        return self.pool.here();
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

    var runtime: MultiThreadedRuntime = MultiThreadedRuntime.init(2, allocator);
    defer runtime.deinit();

    runtime.allowTimers().start();
    defer runtime.stop();

    var task1: TestRunnable = .{ .x = 100 };
    var task2: TestRunnable = .{ .x = 200 };
    var task3: TestRunnable = .{ .x = 300 };

    try runtime.submitTask(task1.runnable());
    try runtime.submitTask(task2.runnable());

    try runtime.submitTimer(task3.runnable(), .{ .microseconds = 1 * std.time.us_per_s });
    try runtime.submitTimer(task3.runnable(), .{ .microseconds = 1 * std.time.us_per_s });
    try runtime.submitTimer(task3.runnable(), .{ .microseconds = 2 * std.time.us_per_s });

    std.Thread.sleep(3 * std.time.ns_per_s);
}
