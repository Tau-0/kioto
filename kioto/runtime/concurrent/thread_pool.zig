const std = @import("std");

const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const IntrusiveTask = @import("../../task/intrusive_task.zig").IntrusiveTask;
const List = @import("../../containers/intrusive_list.zig");
const Task = @import("../../task/task.zig").Task;
const TaskQueue = @import("task_queue.zig").TaskQueue;
const Thread = std.Thread;

threadlocal var current_pool: ?*ThreadPool = null;

pub const ThreadPool = struct {
    const Self = @This();

    workers: []Thread = undefined,
    tasks: TaskQueue = .{},
    done: bool = false,
    allocator: Allocator = undefined,

    pub fn init(self: *Self, workers_count: usize, allocator: Allocator) !void {
        self.workers = try allocator.alloc(Thread, workers_count);
        self.tasks.init();
        self.allocator = allocator;
    }

    pub fn deinit(self: *ThreadPool) void {
        assert(self.done);
        self.tasks.deinit();
        self.allocator.free(self.workers);
    }

    pub fn start(self: *ThreadPool) !void {
        for (0..self.workers.len) |i| {
            self.workers[i] = try std.Thread.spawn(.{}, workerRoutine, .{self});
        }
    }

    pub fn submit(self: *ThreadPool, task: *IntrusiveTask) void {
        self.tasks.put(task.getNode());
    }

    pub fn stop(self: *ThreadPool) void {
        self.tasks.close();
        for (self.workers) |w| {
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
            const task: *IntrusiveTask = self.tasks.take() orelse return;
            task.run();
        }
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const WaitGroup = @import("../../threads/wait_group.zig").WaitGroup;

const TestRunnable = struct {
    data: *u8 = undefined,
    hook: IntrusiveTask = .{},
    wg: *WaitGroup = undefined,

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

    var pool: ThreadPool = .{};
    try pool.init(1, allocator);
    defer pool.deinit();

    try pool.start();
    defer pool.stop();

    var wg: WaitGroup = .{};
    var data: u8 = 0;

    var tasks: [3]TestRunnable = undefined;

    for (0..3) |i| {
        tasks[i] = .{ .data = &data, .wg = &wg };
        tasks[i].init();
        wg.add(1);
        pool.submit(tasks[i].getHook());
    }

    wg.wait();

    try testing.expect(wg.counter == 0);
    try testing.expect(data == 3);
}
