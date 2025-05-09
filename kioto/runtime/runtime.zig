const std = @import("std");

const time = @import("time.zig");

const IntrusiveTask = @import("../task/intrusive_task.zig").IntrusiveTask;

// Interface, any implementation of Runtime should implement (type T here):
// - fn runtime(self: *T) Runtime
// - fn submitTask(self: *T, task: *IntrusiveTask) void
// - fn submitTimer(self: *T, task: *IntrusiveTask, delay: time.Duration) void
pub const Runtime = struct {
    impl: *anyopaque = undefined,
    submit_task_fn: *const fn (ptr: *anyopaque, task: *IntrusiveTask) void = undefined,
    submit_timer_fn: *const fn (ptr: *anyopaque, task: *IntrusiveTask, delay: time.Duration) void = undefined,

    pub fn init(impl: anytype) Runtime {
        const T = @TypeOf(impl);

        const Impl = struct {
            pub fn submitTask(ptr: *anyopaque, task: *IntrusiveTask) void {
                const self: T = @ptrCast(@alignCast(ptr));
                self.submitTask(task);
            }

            pub fn submitTimer(ptr: *anyopaque, task: *IntrusiveTask, delay: time.Duration) void {
                const self: T = @ptrCast(@alignCast(ptr));
                self.submitTimer(task, delay);
            }
        };

        return .{
            .impl = impl,
            .submit_task_fn = Impl.submitTask,
            .submit_timer_fn = Impl.submitTimer,
        };
    }

    pub fn submitTask(self: Runtime, task: *IntrusiveTask) void {
        self.submit_task_fn(self.impl, task);
    }

    pub fn submitTimer(self: Runtime, task: *IntrusiveTask, delay: time.Duration) void {
        self.submit_timer_fn(self.impl, task, delay);
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const Concurrent = @import("concurrent/concurrent_runtime.zig").ConcurrentRuntime;
const Manual = @import("manual/manual_runtime.zig").ManualRuntime;
const Task = @import("../task/task.zig").Task;
const WaitGroup = @import("../threads/wait_group.zig").WaitGroup;

const TestRunnable = struct {
    done: bool = false,
    hook: IntrusiveTask = .{},
    wg: *WaitGroup = undefined,

    pub fn init(self: *TestRunnable) void {
        self.hook.init(Task.init(self));
    }

    pub fn run(self: *TestRunnable) void {
        self.done = true;
        self.wg.done();
    }

    pub fn getHook(self: *TestRunnable) *IntrusiveTask {
        return &self.hook;
    }
};

test "concurrent" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var runtime: Concurrent = .{};
    runtime.init(2, allocator);
    defer runtime.deinit();

    runtime.allowTimers().start();
    defer runtime.stop();

    var wg: WaitGroup = .{};
    var tasks: [5]TestRunnable = undefined;

    for (0..5) |i| {
        tasks[i] = .{ .wg = &wg };
        tasks[i].init();
        wg.add(1);
    }

    runtime.runtime().submitTask(tasks[0].getHook());
    runtime.runtime().submitTask(tasks[1].getHook());

    runtime.runtime().submitTimer(tasks[2].getHook(), .{ .microseconds = 1 * std.time.us_per_s });
    runtime.runtime().submitTimer(tasks[3].getHook(), .{ .microseconds = 1 * std.time.us_per_s });
    runtime.runtime().submitTimer(tasks[4].getHook(), .{ .microseconds = 2 * std.time.us_per_s });

    wg.wait();
    for (tasks) |t| {
        try testing.expect(t.done);
    }
}

test "manual" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var runtime: Manual = .{};
    runtime.init(allocator);
    defer runtime.deinit();

    var wg: WaitGroup = .{};
    var tasks: [5]TestRunnable = undefined;

    for (0..5) |i| {
        tasks[i] = .{ .wg = &wg };
        tasks[i].init();
        wg.add(1);
    }

    runtime.runtime().submitTask(tasks[0].getHook());
    runtime.runtime().submitTask(tasks[1].getHook());

    runtime.runtime().submitTimer(tasks[2].getHook(), .{ .microseconds = 1000 });
    runtime.runtime().submitTimer(tasks[3].getHook(), .{ .microseconds = 1000 });
    runtime.runtime().submitTimer(tasks[4].getHook(), .{ .microseconds = 2000 });

    try testing.expect(runtime.runOne());
    try testing.expect(runtime.runOne());

    try testing.expect(runtime.setClockToNextDeadline() == 2);
    try testing.expect(runtime.timers.tasks.count() == 1);

    try testing.expect(runtime.runAll() == 2);

    try testing.expect(runtime.setClockToNextDeadline() == 1);
    try testing.expect(runtime.timers.tasks.count() == 0);

    try testing.expect(runtime.runAll() == 1);
    try testing.expect(runtime.isEmpty());

    try testing.expect(wg.waiters == 0);
    for (tasks) |t| {
        try testing.expect(t.done);
    }
}
