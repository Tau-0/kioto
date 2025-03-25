const std = @import("std");
const queue = @import("../threads/blocking_queue.zig");
const wg = @import("../threads/wait_group.zig");

const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;

const Task = *const fn () void;

threadlocal var current_pool: ?*ThreadPool = null;

pub const ThreadPool = struct {
    workers: std.ArrayList(std.Thread) = undefined,
    tasks: queue.BlockingQueue(Task) = undefined,
    done: bool = false,

    pub fn init(self: *ThreadPool, workers_count: usize, allocator: std.mem.Allocator) !void {
        self.workers = try std.ArrayList(std.Thread).initCapacity(allocator, workers_count);
        self.tasks = queue.BlockingQueue(Task).init(allocator);
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

    pub fn submit(self: *ThreadPool, task: Task) !void {
        try self.tasks.put(task);
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
            const task: Task = self.tasks.take() orelse return;
            task();
        }
    }
};

fn testWorker() void {
    std.debug.print("Hello from thread {}!\n", .{std.Thread.getCurrentId()});
    std.Thread.sleep(2 * std.time.ns_per_s);
}

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch unreachable;
    const allocator = gpa.allocator();

    var pool: ThreadPool = .{};
    try pool.init(4, allocator);
    try pool.start();
    defer pool.deinit();

    // var waiter: wg.WaitGroup = .{};
    // waiter.add(4);
    try pool.submit(testWorker);
    try pool.submit(testWorker);
    try pool.submit(testWorker);
    try pool.submit(testWorker);
    // waiter.wait();
    pool.stop();
}
