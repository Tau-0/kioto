const std = @import("std");

const List = @import("../containers/intrusive_list.zig").IntrusiveList;
const Task = @import("task.zig").Task;

// Intrusive hook for Task's implementations, any user of IntrusiveTask should define (as type T here):
// - fn run(self: *T) void
//
// Also type T should have a field of type IntrusiveTask:
// hook: IntrusiveTask = .{}
pub const IntrusiveTask = struct {
    const Self = @This();

    pub const Node = List(IntrusiveTask).Node;

    task: Task = undefined,
    node: Node = undefined,

    pub fn init(self: *Self, task: Task) void {
        self.task = task;
        self.node = .{ .left = null, .right = null };
    }

    pub fn run(self: *IntrusiveTask) void {
        self.task.run();
    }

    pub fn getNode(self: *IntrusiveTask) *Node {
        return &self.node;
    }
};

////////////////////////////////////////////////////////////////////////////////

const TaskA = struct {
    data: *u8,
    hook: IntrusiveTask = .{},

    pub fn init(self: *TaskA) void {
        self.hook.init(Task.init(self));
    }

    pub fn run(self: *TaskA) void {
        self.data.* += 1;
    }

    pub fn getNode(self: *TaskA) *IntrusiveTask.Node {
        return &self.hook.node;
    }
};

const TaskB = struct {
    data: *u8,
    hook: IntrusiveTask = .{},

    pub fn init(self: *TaskB) void {
        self.hook.task = Task.init(self);
    }

    pub fn run(self: *TaskB) void {
        self.data.* += 2;
    }

    pub fn getNode(self: *TaskB) *IntrusiveTask.Node {
        return &self.hook.node;
    }
};

test "intrusive" {
    var x: u8 = 0;

    var tasks_a: [5]TaskA = undefined;
    var tasks_b: [5]TaskB = undefined;

    var queue: List(IntrusiveTask) = .{};
    queue.init();

    for (0..5) |i| {
        tasks_a[i] = .{ .data = &x };
        tasks_a[i].init();
        queue.pushBack(tasks_a[i].getNode());
    }

    for (0..5) |i| {
        tasks_b[i] = .{ .data = &x };
        tasks_b[i].init();
        queue.pushBack(tasks_b[i].getNode());
    }

    while (queue.nonEmpty()) {
        queue.popFrontUnsafe().run();
    }

    try std.testing.expect(x == 15);
}
