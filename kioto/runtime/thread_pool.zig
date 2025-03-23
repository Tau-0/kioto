const std = @import("std");
const queue = @import("blocking_queue.zig");
const wg = @import("wait_group.zig");

const Task = *const fn () void;

threadlocal var current_pool: ?*ThreadPool = null;

pub const ThreadPool = struct {
    workers: std.ArrayList(std.Thread) = undefined,
    tasks: queue.BlockingQueue(Task) = undefined,
    wait_group: wg.WaitGroup = .{},

    pub fn init(self: *ThreadPool, workers_count: usize, alloc: std.mem.Allocator) void {
        self.workers = std.ArrayList(std.Thread).initCapacity(alloc, workers_count) catch unreachable;
        self.tasks = queue.BlockingQueue(Task).init(alloc);
    }

    pub fn deinit(self: *ThreadPool) void {
        self.workers.deinit();
        self.tasks.deinit();
    }

    pub fn start(self: *ThreadPool) void {
        for (0..self.workers.capacity) |_| {
            self.workers.append(std.Thread.spawn(.{}, workerRoutine, .{self}) catch unreachable) catch unreachable;
        }
    }

    pub fn submit(self: *ThreadPool, task: Task) void {
        self.wait_group.add(1);
        if (!self.tasks.put(task)) {
            self.wait_group.done();
        }
    }

    pub fn waitIdle(self: *ThreadPool) void {
        self.wait_group.wait();
    }

    pub fn stop(self: *ThreadPool) void {
        self.tasks.close();
        for (self.workers.items) |w| {
            w.join();
        }
    }

    pub fn currentPool() ?*ThreadPool {
        return current_pool;
    }

    fn workerRoutine(self: *ThreadPool) void {
        current_pool = self;
        while (true) {
            const task = self.tasks.take() orelse return;
            task();
            self.wait_group.done();
        }
    }
};

fn testWorker() void {
    std.debug.print("Hello from thread {}!\n", .{std.Thread.getCurrentId()});
    std.time.sleep(5000);
}

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var pool: ThreadPool = .{};
    pool.init(4, alloc);
    defer pool.deinit();

    pool.submit(testWorker);
    pool.submit(testWorker);
    pool.submit(testWorker);
    pool.submit(testWorker);
    pool.start();
    pool.waitIdle();
    pool.stop();
}
