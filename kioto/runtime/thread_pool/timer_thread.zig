const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Atomic = std.atomic.Value;
const Clock = @import("monotonic_clock.zig").MonotonicClock;
const Mutex = std.Thread.Mutex;
const Order = std.math.Order;
const PriorityQueue = std.PriorityQueue;
const Runnable = @import("../../task/task.zig").Runnable;
const Thread = std.Thread;
const ThreadPool = @import("thread_pool.zig").ThreadPool;

const Context = struct {};

const TimedTask = struct {
    handler: Runnable = undefined,
    deadline: Clock.TimePoint = undefined,
};

fn lessThan(_: Context, a: TimedTask, b: TimedTask) Order {
    return std.math.order(a.deadline.microseconds, b.deadline.microseconds);
}

pub const TimerThread = struct {
    const Duration = Clock.Duration;
    const TimePoint = Clock.TimePoint;

    const Queue = PriorityQueue(TimedTask, Context, lessThan);
    const Self = @This();
    const PollTimeout: comptime_int = 50 * std.time.ns_per_us; // 50us as nanoseconds

    tasks: Queue = undefined,
    thread_pool: *ThreadPool = undefined,
    poller_thread: ?Thread = null,
    mutex: Mutex = .{},
    stopped: Atomic(bool) = .{ .raw = false },
    clock: Clock = undefined,

    pub fn init(thread_pool: *ThreadPool, allocator: Allocator) Self {
        return .{
            .tasks = Queue.init(allocator, .{}),
            .thread_pool = thread_pool,
            .clock = Clock.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.tasks.deinit();
    }

    pub fn start(self: *Self) !void {
        self.poller_thread = try Thread.spawn(.{}, pollerRoutine, .{self});
    }

    pub fn stop(self: *Self) void {
        self.stopped.store(true, .seq_cst);
        self.poller_thread.?.join();
    }

    pub fn submit(self: *Self, handler: Runnable, delay: Duration) !void {
        const deadline: TimePoint = .{ .microseconds = self.clock.now().microseconds + delay.microseconds };
        try self.push(handler, deadline);
    }

    fn push(self: *Self, handler: Runnable, deadline: TimePoint) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.tasks.add(.{ .handler = handler, .deadline = deadline });
    }

    // With lock
    fn isEmpty(self: *const Self) bool {
        return self.tasks.count() == 0;
    }

    // With lock
    fn nextDeadline(self: *Self) TimePoint {
        return self.tasks.peek().?.deadline;
    }

    fn submitReadyTasks(self: *Self) !void {
        const now = self.clock.now();
        self.mutex.lock();
        defer self.mutex.unlock();
        while (!self.isEmpty() and now.microseconds >= self.nextDeadline().microseconds) {
            try self.thread_pool.submit(self.tasks.remove().handler);
        }
    }

    fn pollerRoutine(self: *Self) void {
        while (!self.stopped.load(.seq_cst)) {
            self.submitReadyTasks() catch |err| std.debug.panic("Can not submit ready tasks: {}\n", .{err});
            Thread.sleep(PollTimeout);
        }
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const WaitGroup = @import("../../threads/wait_group.zig").WaitGroup;

const TestRunnable = struct {
    x: i32 = undefined,
    wg: *WaitGroup,
    done: Atomic(bool) = .{ .raw = false },

    pub fn runnable(self: *TestRunnable) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *TestRunnable) void {
        self.done.store(true, .seq_cst);
        std.debug.print("{}\n", .{self.x});
        self.wg.done();
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var pool = try ThreadPool.init(1, allocator);
    defer pool.deinit();

    try pool.start();
    defer pool.stop();

    var wg: WaitGroup = .{};
    wg.add(3);

    var task1: TestRunnable = .{ .x = 10, .wg = &wg };
    var task2: TestRunnable = .{ .x = 20, .wg = &wg };
    var task3: TestRunnable = .{ .x = 30, .wg = &wg };

    var timer: TimerThread = TimerThread.init(&pool, allocator);
    defer timer.deinit();

    try timer.start();
    defer timer.stop();

    try timer.submit(task1.runnable(), .{ .microseconds = 1 * std.time.us_per_s });
    try timer.submit(task2.runnable(), .{ .microseconds = 1 * std.time.us_per_s });
    try timer.submit(task3.runnable(), .{ .microseconds = 2 * std.time.us_per_s });

    {
        testing.expect(timer.tasks.count() == 3) catch @panic("TEST FAIL");
        std.Thread.sleep(1.5 * std.time.ns_per_s);

        testing.expect(task1.done.load(.seq_cst)) catch @panic("TEST FAIL");
        testing.expect(task2.done.load(.seq_cst)) catch @panic("TEST FAIL");
    }
    {
        std.Thread.sleep(1.5 * std.time.ns_per_s);

        testing.expect(task3.done.load(.seq_cst)) catch @panic("TEST FAIL");
    }

    wg.wait();
    testing.expect(pool.tasks.buffer.len == 0) catch @panic("TEST FAIL");
}
