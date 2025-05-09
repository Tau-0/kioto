const std = @import("std");

const time = @import("../time.zig");

const Allocator = std.mem.Allocator;
const IntrusiveTask = @import("../../task/intrusive_task.zig").IntrusiveTask;
const Runtime = @import("../runtime.zig").Runtime;
const ThreadPool = @import("thread_pool.zig").ThreadPool;
const TimerThread = @import("timer_thread.zig").TimerThread;

pub const ConcurrentRuntime = struct {
    const Self = @This();

    pool: ThreadPool = .{},
    timer_thread: ?TimerThread = null,
    allocator: Allocator = undefined,

    pub fn init(self: *Self, worker_count: usize, allocator: Allocator) void {
        self.pool.init(worker_count, allocator) catch unreachable;
        self.allocator = allocator;
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
    pub fn submitTask(self: *Self, task: *IntrusiveTask) void {
        self.pool.submit(task);
    }

    pub fn submitTimer(self: *Self, task: *IntrusiveTask, delay: time.Duration) void {
        std.debug.assert(self.timer_thread != null);
        self.timer_thread.?.submit(task, delay) catch unreachable;
    }

    pub fn runtime(self: *Self) Runtime {
        return Runtime.init(self);
    }

    pub fn here(self: *const Self) bool {
        return self.pool.here();
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const Task = @import("../../task/task.zig").Task;
const WaitGroup = @import("../../threads/wait_group.zig").WaitGroup;

const TestRunnable = struct {
    data: *u8 = undefined,
    wg: *WaitGroup = undefined,
    hook: IntrusiveTask = .{},

    pub fn init(self: *TestRunnable) void {
        self.hook.init(Task.init(self));
    }

    pub fn run(self: *TestRunnable) void {
        self.data.* += 1;
        self.wg.done();
    }

    pub fn getHook(self: *TestRunnable) *IntrusiveTask {
        return &self.hook;
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var runtime: ConcurrentRuntime = .{};
    runtime.init(1, allocator);
    defer runtime.deinit();

    runtime.allowTimers().start();
    defer runtime.stop();

    var wg: WaitGroup = .{};
    var data: u8 = 0;

    var tasks: [5]TestRunnable = undefined;
    for (0..5) |i| {
        tasks[i] = .{ .data = &data, .wg = &wg };
        tasks[i].init();
        wg.add(1);
    }

    runtime.submitTask(tasks[0].getHook());
    runtime.submitTask(tasks[1].getHook());

    runtime.submitTimer(tasks[2].getHook(), .{ .microseconds = 0.5 * std.time.us_per_s });
    runtime.submitTimer(tasks[3].getHook(), .{ .microseconds = 0.5 * std.time.us_per_s });
    runtime.submitTimer(tasks[4].getHook(), .{ .microseconds = 1 * std.time.us_per_s });

    wg.wait();
    try testing.expect(data == 5);
}
