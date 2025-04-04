const std = @import("std");

const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const BlockingQueue = @import("../threads/blocking_queue.zig").BlockingQueue;
const Runnable = @import("../task/task.zig").Runnable;
const Thread = std.Thread;

threadlocal var current_pool: ?*ThreadPool = null;

pub const ThreadPool = struct {
    workers: ArrayList(Thread) = undefined,
    tasks: BlockingQueue(Runnable) = undefined,
    done: bool = false,

    pub fn init(workers_count: usize, allocator: Allocator) !ThreadPool {
        return .{
            .workers = try ArrayList(Thread).initCapacity(allocator, workers_count),
            .tasks = BlockingQueue(Runnable).init(allocator),
        };
    }

    pub fn deinit(self: *ThreadPool) void {
        assert(self.done);
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

const WaitGroup = @import("../threads/wait_group.zig").WaitGroup;

const TestRunnable = struct {
    wg: *WaitGroup,

    pub fn runnable(self: *TestRunnable) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *TestRunnable) void {
        std.debug.print("Hello from thread {}!\n", .{std.Thread.getCurrentId()});
        std.Thread.sleep(2 * std.time.ns_per_s);
        self.wg.done();
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch unreachable;
    const allocator = gpa.allocator();

    var pool: ThreadPool = try ThreadPool.init(4, allocator);
    try pool.start();
    defer pool.deinit();

    var wg: WaitGroup = .{};
    var test_task: TestRunnable = .{ .wg = &wg };
    const runnable: Runnable = test_task.runnable();
    wg.add(4);
    try pool.submit(runnable);
    try pool.submit(runnable);
    try pool.submit(runnable);
    try pool.submit(runnable);
    wg.wait();
    pool.stop();

    try testing.expect(wg.counter == 0);
}
