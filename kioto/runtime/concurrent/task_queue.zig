const std = @import("std");

const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const Condition = std.Thread.Condition;
const IntrusiveList = @import("../../containers/intrusive_list.zig").IntrusiveList;
const IntrusiveTask = @import("../../task/intrusive_task.zig").IntrusiveTask;
const Mutex = std.Thread.Mutex;
const Task = @import("../../task/task.zig").Task;

// Unbounded blocking intrusive MPMC queue for tasks
pub const TaskQueue = struct {
    const List = IntrusiveList(IntrusiveTask);
    const Node = IntrusiveTask.Node;

    pub const Self = @This();

    task_queue: List = .{},
    mutex: Mutex = .{},
    has_values: Condition = .{},
    is_open: bool = true,

    pub fn init(self: *Self) void {
        self.task_queue.init();
    }

    pub fn deinit(self: *Self) void {
        assert(self.isEmpty());
    }

    pub fn put(self: *Self, node: *Node) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (!self.is_open) {
            return;
        }

        self.task_queue.pushBack(node);
        self.has_values.signal();
    }

    pub fn take(self: *Self) ?*IntrusiveTask {
        self.mutex.lock();
        defer self.mutex.unlock();
        while (self.isEmpty() and self.is_open) {
            self.has_values.wait(&self.mutex);
        }

        if (self.isEmpty()) {
            return null;
        }
        return self.takeLocked();
    }

    // With lock
    fn takeLocked(self: *Self) *IntrusiveTask {
        assert(!self.isEmpty());
        return self.task_queue.popFrontUnsafe();
    }

    // With lock
    fn isEmpty(self: *Self) bool {
        return self.task_queue.isEmpty();
    }

    pub fn close(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.is_open = false;
        self.has_values.broadcast();
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
        std.Thread.sleep(1 * std.time.ns_per_s);
        self.data.* += 1;
        self.wg.done();
    }

    pub fn getNode(self: *TestRunnable) *IntrusiveTask.Node {
        return &self.hook.node;
    }
};

fn workerRoutine(q: *TaskQueue, wg: *WaitGroup) void {
    for (0..3) |_| {
        assert(!q.isEmpty());
        q.take().?.run();
    }

    q.close();
    wg.done();
}

test "basic" {
    var queue: TaskQueue = .{};
    queue.init();
    defer queue.deinit();

    var wg: WaitGroup = .{};
    wg.add(4);

    var data: u8 = 0;
    var tasks: [3]TestRunnable = undefined;

    for (0..3) |i| {
        tasks[i] = .{ .data = &data, .wg = &wg };
        tasks[i].init();
        queue.put(tasks[i].getNode());
    }

    var worker = try std.Thread.spawn(.{}, workerRoutine, .{ &queue, &wg });

    wg.wait();
    worker.join();
    try testing.expect(data == 3);
}
