const std = @import("std");

const Allocator = std.mem.Allocator;
const IntrusiveTask = @import("intrusive_task.zig").IntrusiveTask;
const Task = @import("task.zig").Task;

// Owning wrapper over any callable type (Callable here) with defined method "run":
// - fn run(self: *Callable) void
fn BoxedTask(comptime TaskType: type) type {
    return struct {
        const Self = @This();

        task: TaskType = undefined,
        hook: IntrusiveTask = undefined,
        allocator: Allocator = undefined,

        fn init(self: *Self, task: TaskType, allocator: Allocator) void {
            self.task = task;
            self.hook.init(Task.init(self));
            self.allocator = allocator;
        }

        fn deinit(self: *Self) void {
            self.allocator.destroy(self);
        }

        pub fn getHook(self: *Self) *IntrusiveTask {
            return &self.hook;
        }

        pub fn run(self: *Self) void {
            self.task.run();
            self.deinit();
        }
    };
}

pub fn makeBoxedTask(task: anytype, allocator: Allocator) !*BoxedTask(@TypeOf(task)) {
    var boxed_task = try allocator.create(BoxedTask(@TypeOf(task)));
    boxed_task.init(task, allocator);
    return boxed_task;
}

///////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const Manual = @import("../runtime/manual/manual_runtime.zig").ManualRuntime;

const TaskA = struct {
    data: u64,

    pub fn run(self: *TaskA) void {
        std.debug.assert(self.data == 10);
    }
};

fn testFn(allocator: Allocator) !*BoxedTask(TaskA) {
    const task: TaskA = .{ .data = 10 };
    return try makeBoxedTask(task, allocator);
}

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var runtime: Manual = .{};
    runtime.init(allocator);
    defer runtime.deinit();

    var boxed_task = try testFn(allocator);

    runtime.submitTask(boxed_task.getHook());

    try testing.expect(runtime.runOne());
}
