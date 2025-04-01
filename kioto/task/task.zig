const std = @import("std");

// Interface, heir of type T should implement:
// - fn runnable(self: *T) Runnable
// - fn run(self: *T) void
pub const Runnable = struct {
    pub const Task = *const fn (ptr: *anyopaque) void;

    impl: *anyopaque = undefined,
    task_fn: Task = undefined,

    pub fn init(impl: anytype) Runnable {
        const T = @TypeOf(impl);

        const Impl = struct {
            pub fn run(ptr: *anyopaque) void {
                const self: T = @ptrCast(@alignCast(ptr));
                self.run();
            }
        };

        return .{
            .impl = impl,
            .task_fn = Impl.run,
        };
    }

    pub fn run(self: Runnable) void {
        self.task_fn(self.impl);
    }
};

////////////////////////////////////////////////////////////////////////////////

const TaskA = struct {
    data: u64,

    pub fn runnable(self: *TaskA) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *TaskA) void {
        std.debug.print("Task A: {}\n", .{self.data});
    }
};

const TaskB = struct {
    data: *u8,

    pub fn runnable(self: *TaskB) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *TaskB) void {
        self.data.* += 1;
        std.debug.print("Task B: {}\n", .{self.data.*});
    }
};

test "basic" {
    var x: u8 = 10;
    var y: u8 = 2;
    var t1: TaskA = .{ .data = 2 };
    var t2: TaskB = .{ .data = &x };
    var t3: TaskB = .{ .data = &y };

    var tasks: [3]Runnable = undefined;
    tasks[0] = t1.runnable();
    tasks[1] = t2.runnable();
    tasks[2] = t3.runnable();

    for (tasks) |t| {
        t.run();
    }

    try std.testing.expect(x == 11);
    try std.testing.expect(y == 3);
    try std.testing.expect(t1.data == 2);
}
