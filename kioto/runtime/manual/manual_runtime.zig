const std = @import("std");

const time = @import("../time.zig");

const stacks = struct {
    usingnamespace @import("../stack.zig");
};

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Clock = @import("manual_clock.zig").ManualClock;
const Executor = @import("manual_executor.zig").ManualExecutor;
const IntrusiveTask = @import("../../task/intrusive_task.zig").IntrusiveTask;
const Runtime = @import("../runtime.zig").Runtime;
const TimerQueue = @import("timer_queue.zig").TimerQueue;

pub const ManualRuntime = struct {
    const Self = @This();

    const TimePoint = time.TimePoint;
    const Duration = time.Duration;

    const stack_pool_capacity: usize = 1024;

    executor: Executor = .{},
    timers: TimerQueue = undefined,
    clock: Clock = .{},
    allocator: Allocator = undefined,
    stack_pool: stacks.StackPool = undefined,

    pub fn init(self: *Self, allocator: Allocator) void {
        self.executor.init();
        self.timers = TimerQueue.init(allocator);
        self.allocator = allocator;
        self.stack_pool = .{};
        self.stack_pool.init(stack_pool_capacity, allocator);
    }

    pub fn deinit(self: *Self) void {
        self.timers.deinit();
        self.executor.deinit();
        self.stack_pool.deinit();
    }

    // Runtime interface
    pub fn submitTask(self: *Self, task: *IntrusiveTask) void {
        self.executor.submit(task);
    }

    pub fn submitTimer(self: *Self, task: *IntrusiveTask, delay: Duration) void {
        const deadline: TimePoint = .{ .microseconds = self.clock.now().microseconds + delay.microseconds };
        self.timers.push(task, deadline) catch unreachable;
    }

    pub fn allocateStack(self: *Self) Allocator.Error!*stacks.Stack {
        return self.stack_pool.allocate();
    }

    pub fn releaseStack(self: *Self, stack: *stacks.Stack) void {
        self.stack_pool.release(stack);
    }

    pub fn runtime(self: *Self) Runtime {
        return Runtime.init(self);
    }

    // Tasks
    pub fn runOne(self: *Self) bool {
        return self.executor.runOne();
    }

    pub fn runLimited(self: *Self, limit: usize) usize {
        return self.executor.runLimited(limit);
    }

    pub fn runAll(self: *Self) usize {
        return self.executor.runAll();
    }

    // Timers
    pub fn advanceClock(self: *Self, delta: Duration) usize {
        self.clock.advance(delta);
        return self.submitReadyTasks();
    }

    pub fn setClockToNextDeadline(self: *Self) usize {
        if (self.timers.isEmpty()) {
            return 0;
        }

        self.clock.set(self.timers.nextDeadline());
        return self.submitReadyTasks();
    }

    // Misc
    pub fn queueSize(self: *const Self) usize {
        return self.executor.queueSize();
    }

    pub fn isEmpty(self: *const Self) bool {
        return self.executor.isEmpty() and self.timers.isEmpty();
    }

    fn submitReadyTasks(self: *Self) usize {
        var tasks: ArrayList(*IntrusiveTask) = self.timers.takeReadyTasks(self.clock.now(), self.allocator) catch |err| std.debug.panic("Can not submit ready tasks; error: {}\n", .{err});
        defer tasks.deinit();
        for (tasks.items) |t| {
            self.submitTask(t);
        }
        return tasks.items.len;
    }
};

////////////////////////////////////////////////////////////////////////////////

const Task = @import("../../task/task.zig").Task;

const testing = std.testing;

const TestRunnable = struct {
    done: bool = false,
    hook: IntrusiveTask = .{},

    pub fn init(self: *TestRunnable) void {
        self.hook.init(Task.init(self));
    }

    pub fn run(self: *TestRunnable) void {
        self.done = true;
    }

    pub fn getHook(self: *TestRunnable) *IntrusiveTask {
        return &self.hook;
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var manual: ManualRuntime = .{};
    manual.init(allocator);
    defer manual.deinit();

    var tasks: [5]TestRunnable = undefined;

    for (0..5) |i| {
        tasks[i] = .{};
        tasks[i].init();
    }

    manual.submitTask(tasks[0].getHook());
    manual.submitTask(tasks[1].getHook());

    manual.submitTimer(tasks[2].getHook(), .{ .microseconds = 1000 });
    manual.submitTimer(tasks[3].getHook(), .{ .microseconds = 1000 });
    manual.submitTimer(tasks[4].getHook(), .{ .microseconds = 2000 });

    try testing.expect(manual.runOne());
    try testing.expect(tasks[0].done);
    try testing.expect(manual.runOne());
    try testing.expect(tasks[1].done);

    try testing.expect(manual.setClockToNextDeadline() == 2);
    try testing.expect(manual.timers.tasks.count() == 1);

    try testing.expect(manual.runAll() == 2);
    try testing.expect(tasks[2].done);
    try testing.expect(tasks[3].done);

    try testing.expect(manual.setClockToNextDeadline() == 1);
    try testing.expect(manual.timers.tasks.count() == 0);

    try testing.expect(manual.runAll() == 1);
    try testing.expect(manual.isEmpty());
    try testing.expect(tasks[4].done);
}
