const std = @import("std");

const queue = @import("../threads/blocking_queue.zig");
const task = @import("../task/task.zig");
const wg = @import("../threads/wait_group.zig");

const Runnable = task.Runnable;

threadlocal var current_pool: ?*ThreadPool = null;

// TODO: waitIdle
pub const ThreadPool = struct {
    workers: std.ArrayList(std.Thread) = undefined,
    tasks: queue.BlockingQueue(Runnable) = undefined,
    done: bool = false,

    pub fn init(workers_count: usize, allocator: std.mem.Allocator) !ThreadPool {
        return .{
            .workers = try std.ArrayList(std.Thread).initCapacity(allocator, workers_count),
            .tasks = queue.BlockingQueue(Runnable).init(allocator),
        };
    }

    pub fn deinit(self: *ThreadPool) void {
        std.debug.assert(self.done);
        self.tasks.deinit();
        self.workers.deinit();
    }

    pub fn start(self: *ThreadPool) !void {
        for (0..self.workers.capacity) |_| {
            self.workers.addOneAssumeCapacity().* = try std.Thread.spawn(.{}, workerRoutine, .{self});
        }
    }

    pub fn submit(self: *ThreadPool, runnable: Runnable) !void {
        try self.tasks.put(runnable);
    }

    pub fn stop(self: *ThreadPool) void {
        self.tasks.close();
        for (self.workers.items) |w| {
            w.join();
        }
        self.done = true;
    }

    pub fn currentPool() ?*ThreadPool {
        return current_pool;
    }

    pub fn here(self: *const ThreadPool) bool {
        return current_pool == self;
    }

    fn workerRoutine(self: *ThreadPool) void {
        current_pool = self;
        while (true) {
            const runnable: Runnable = self.tasks.take() orelse return;
            runnable.run();
        }
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const TestRunnable = struct {
    waiter: *wg.WaitGroup,

    pub fn runnable(self: *TestRunnable) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *TestRunnable) void {
        std.debug.print("Hello from thread {}!\n", .{std.Thread.getCurrentId()});
        std.Thread.sleep(2 * std.time.ns_per_s);
        self.waiter.done();
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch unreachable;
    const allocator = gpa.allocator();

    var pool: ThreadPool = try ThreadPool.init(4, allocator);
    try pool.start();
    defer pool.deinit();

    var waiter: wg.WaitGroup = .{};
    var test_task: TestRunnable = .{ .waiter = &waiter };
    const runnable: Runnable = test_task.runnable();
    waiter.add(4);
    try pool.submit(runnable);
    try pool.submit(runnable);
    try pool.submit(runnable);
    try pool.submit(runnable);
    waiter.wait();
    pool.stop();

    try testing.expect(waiter.counter == 0);
}
