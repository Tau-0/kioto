const std = @import("std");

const time = @import("../time.zig");

const Allocator = std.mem.Allocator;
const Atomic = std.atomic.Value;
const Clock = @import("monotonic_clock.zig").MonotonicClock;
const IntrusiveTask = @import("../../task/intrusive_task.zig").IntrusiveTask;
const Mutex = std.Thread.Mutex;
const Order = std.math.Order;
const PriorityQueue = std.PriorityQueue;
const Thread = std.Thread;
const ThreadPool = @import("thread_pool.zig").ThreadPool;

const Context = struct {};

const TimedTask = struct {
    handler: *IntrusiveTask = undefined,
    deadline: time.TimePoint = undefined,
};

fn lessThan(_: Context, a: TimedTask, b: TimedTask) Order {
    return std.math.order(a.deadline.microseconds, b.deadline.microseconds);
}

pub const TimerThread = struct {
    const Duration = time.Duration;
    const TimePoint = time.TimePoint;

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

    pub fn submit(self: *Self, handler: *IntrusiveTask, delay: Duration) !void {
        const deadline: TimePoint = .{ .microseconds = self.clock.now().microseconds + delay.microseconds };
        try self.push(handler, deadline);
    }

    fn push(self: *Self, handler: *IntrusiveTask, deadline: TimePoint) !void {
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

    fn submitReadyTasks(self: *Self) void {
        const now = self.clock.now();
        self.mutex.lock();
        defer self.mutex.unlock();
        while (!self.isEmpty() and now.microseconds >= self.nextDeadline().microseconds) {
            self.thread_pool.submit(self.tasks.remove().handler);
        }
    }

    fn pollerRoutine(self: *Self) void {
        while (!self.stopped.load(.seq_cst)) {
            self.submitReadyTasks();
            Thread.sleep(PollTimeout);
        }
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const Task = @import("../../task/task.zig").Task;
const WaitGroup = @import("../../threads/wait_group.zig").WaitGroup;

const TestRunnable = struct {
    data: *u8 = undefined,
    wg: *WaitGroup = undefined,
    done: Atomic(bool) = .{ .raw = false },
    hook: IntrusiveTask = .{},

    pub fn init(self: *TestRunnable) void {
        self.hook.init(Task.init(self));
    }

    pub fn run(self: *TestRunnable) void {
        self.done.store(true, .seq_cst);
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

    var pool: ThreadPool = .{};
    try pool.init(1, allocator);
    defer pool.deinit();

    try pool.start();
    defer pool.stop();

    var wg: WaitGroup = .{};
    wg.add(3);

    var data: u8 = 0;
    var task1: TestRunnable = .{ .data = &data, .wg = &wg };
    var task2: TestRunnable = .{ .data = &data, .wg = &wg };
    var task3: TestRunnable = .{ .data = &data, .wg = &wg };

    task1.init();
    task2.init();
    task3.init();

    var timer: TimerThread = TimerThread.init(&pool, allocator);
    defer timer.deinit();

    try timer.start();
    defer timer.stop();

    try timer.submit(task1.getHook(), .{ .microseconds = 1 * std.time.us_per_s });
    try timer.submit(task2.getHook(), .{ .microseconds = 1 * std.time.us_per_s });
    try timer.submit(task3.getHook(), .{ .microseconds = 2 * std.time.us_per_s });

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
    testing.expect(pool.tasks.task_queue.isEmpty()) catch @panic("TEST FAIL");
    try testing.expect(data == 3);
}
