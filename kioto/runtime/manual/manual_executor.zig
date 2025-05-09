const std = @import("std");

const IntrusiveTask = @import("../../task/intrusive_task.zig").IntrusiveTask;
const List = @import("../../containers/intrusive_list.zig").IntrusiveList;

pub const ManualExecutor = struct {
    const Self = @This();

    const TaskQueue = List(IntrusiveTask);
    const Node = TaskQueue.Node;

    tasks: TaskQueue = .{},

    pub fn init(self: *Self) void {
        self.tasks.init();
    }

    pub fn deinit(self: *ManualExecutor) void {
        std.debug.assert(self.isEmpty());
    }

    pub fn submit(self: *ManualExecutor, task: *IntrusiveTask) void {
        self.tasks.pushBack(task.getNode());
    }

    pub fn runOne(self: *ManualExecutor) bool {
        var done: bool = false;
        if (!self.isEmpty()) {
            var task: *IntrusiveTask = self.tasks.popFrontUnsafe();
            task.run();
            done = true;
        }
        return done;
    }

    pub fn runLimited(self: *ManualExecutor, limit: usize) usize {
        var done: usize = 0;
        while (done < limit and self.runOne()) {
            done += 1;
        }
        return done;
    }

    pub fn runAll(self: *ManualExecutor) usize {
        var done: usize = 0;
        while (self.runOne()) {
            done += 1;
        }
        return done;
    }

    pub fn isEmpty(self: *const ManualExecutor) bool {
        return self.tasks.isEmpty();
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const Task = @import("../../task/task.zig").Task;

const TestRunnable = struct {
    data: *u8 = undefined,
    hook: IntrusiveTask = .{},

    pub fn init(self: *TestRunnable) void {
        self.hook.init(Task.init(self));
    }

    pub fn run(self: *TestRunnable) void {
        self.data.* += 1;
    }

    pub fn getHook(self: *TestRunnable) *IntrusiveTask {
        return &self.hook;
    }
};

test "basic" {
    var manual: ManualExecutor = .{};
    manual.init();
    defer manual.deinit();

    var data: u8 = 0;

    var task1: TestRunnable = .{ .data = &data };
    var task2: TestRunnable = .{ .data = &data };

    task1.init();
    task2.init();

    manual.submit(task1.getHook());
    manual.submit(task2.getHook());

    try testing.expect(manual.runOne());
    try testing.expect(data == 1);
    try testing.expect(manual.runOne());
    try testing.expect(data == 2);
    try testing.expect(manual.isEmpty());
}
