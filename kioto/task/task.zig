const std = @import("std");

// Interface, any implementation of Task should define (type Impl here):
// - fn task(self: *Impl) Task
// - fn run(self: *Impl) void
pub const Task = struct {
    impl: *anyopaque = undefined,
    run_fn: *const fn (ptr: *anyopaque) void = undefined,

    pub fn init(impl: anytype) Task {
        const T = @TypeOf(impl);

        const Impl = struct {
            pub fn run(ptr: *anyopaque) void {
                const self: T = @ptrCast(@alignCast(ptr));
                self.run();
            }
        };

        return .{
            .impl = impl,
            .run_fn = Impl.run,
        };
    }

    pub fn run(self: Task) void {
        self.run_fn(self.impl);
    }
};

////////////////////////////////////////////////////////////////////////////////

const TaskA = struct {
    data: u64,

    pub fn task(self: *TaskA) Task {
        return Task.init(self);
    }

    pub fn run(self: *TaskA) void {
        std.debug.assert(self.data == 2);
    }
};

const TaskB = struct {
    data: *u8,

    pub fn task(self: *TaskB) Task {
        return Task.init(self);
    }

    pub fn run(self: *TaskB) void {
        self.data.* += 1;
    }
};

test "basic" {
    var t1: TaskA = .{ .data = 2 };

    var x: u8 = 10;
    var t2: TaskB = .{ .data = &x };

    var y: u8 = 2;
    var t3: TaskB = .{ .data = &y };

    var tasks: [3]Task = undefined;
    tasks[0] = t1.task();
    tasks[1] = t2.task();
    tasks[2] = t3.task();

    for (tasks) |t| {
        t.run();
    }

    try std.testing.expect(x == 11);
    try std.testing.expect(y == 3);
    try std.testing.expect(t1.data == 2);
}
