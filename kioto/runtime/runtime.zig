const std = @import("std");

const time = @import("time.zig");

const Runnable = @import("../task/task.zig").Runnable;

// Interface, any implementation of Runtime should implement (type T here):
// - fn runtime(self: *T) Runtime
// - fn submitTask(self: *T, runnable: Runnable) void
// - fn submitTimer(self: *T, runnable: Runnable, delay: time.Duration) void
pub const Runtime = struct {
    impl: *anyopaque = undefined,
    submit_task_fn: *const fn (ptr: *anyopaque, runnable: Runnable) void = undefined,
    submit_timer_fn: *const fn (ptr: *anyopaque, runnable: Runnable, delay: time.Duration) void = undefined,

    pub fn init(impl: anytype) Runtime {
        const T = @TypeOf(impl);

        const Impl = struct {
            pub fn submitTask(ptr: *anyopaque, runnable: Runnable) void {
                const self: T = @ptrCast(@alignCast(ptr));
                self.submitTask(runnable);
            }

            pub fn submitTimer(ptr: *anyopaque, runnable: Runnable, delay: time.Duration) void {
                const self: T = @ptrCast(@alignCast(ptr));
                self.submitTimer(runnable, delay);
            }
        };

        return .{
            .impl = impl,
            .submit_task_fn = Impl.submitTask,
            .submit_timer_fn = Impl.submitTimer,
        };
    }

    pub fn submitTask(self: Runtime, runnable: Runnable) void {
        self.submit_task_fn(self.impl, runnable);
    }

    pub fn submitTimer(self: Runtime, runnable: Runnable, delay: time.Duration) void {
        self.submit_timer_fn(self.impl, runnable, delay);
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const Concurrent = @import("concurrent/concurrent_runtime.zig").ConcurrentRuntime;
const Manual = @import("manual/manual_runtime.zig").ManualRuntime;

const TestRunnable = struct {
    x: i32 = undefined,

    pub fn runnable(self: *TestRunnable) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *TestRunnable) void {
        std.debug.print("{}\n", .{self.x});
    }
};

test "concurrent" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var runtime: Concurrent = Concurrent.init(2, allocator);
    defer runtime.deinit();

    runtime.allowTimers().start();
    defer runtime.stop();

    var task1: TestRunnable = .{ .x = 100 };
    var task2: TestRunnable = .{ .x = 200 };
    var task3: TestRunnable = .{ .x = 300 };

    runtime.runtime().submitTask(task1.runnable());
    runtime.runtime().submitTask(task2.runnable());

    runtime.runtime().submitTimer(task3.runnable(), .{ .microseconds = 1 * std.time.us_per_s });
    runtime.runtime().submitTimer(task3.runnable(), .{ .microseconds = 1 * std.time.us_per_s });
    runtime.runtime().submitTimer(task3.runnable(), .{ .microseconds = 2 * std.time.us_per_s });

    std.Thread.sleep(3 * std.time.ns_per_s);
}

test "manual" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var manual: Manual = Manual.init(allocator);
    defer manual.deinit();

    var task1: TestRunnable = .{ .x = 100 };
    var task2: TestRunnable = .{ .x = 200 };
    var task3: TestRunnable = .{ .x = 300 };

    manual.runtime().submitTask(task1.runnable());
    manual.runtime().submitTask(task2.runnable());

    manual.runtime().submitTimer(task3.runnable(), .{ .microseconds = 1000 });
    manual.runtime().submitTimer(task3.runnable(), .{ .microseconds = 1000 });
    manual.runtime().submitTimer(task3.runnable(), .{ .microseconds = 2000 });

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
