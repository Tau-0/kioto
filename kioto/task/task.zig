const std = @import("std");

// Interface
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

const ClosureA = struct {
    data: u64,

    pub fn runnable(self: *ClosureA) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *ClosureA) void {
        std.debug.print("Closure A: {}\n", .{self.data});
    }
};

const ClosureB = struct {
    data: *u8,

    pub fn runnable(self: *ClosureB) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *ClosureB) void {
        self.data.* += 1;
        std.debug.print("Closure B: {}\n", .{self.data.*});
    }
};

test "basic" {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    // const allocator = gpa.allocator();
    // defer _ = gpa.detectLeaks();

    var x: u8 = 10;
    var y: u8 = 2;
    var c1: ClosureA = .{ .data = 2 };
    var c2: ClosureB = .{ .data = &x };
    var c3: ClosureB = .{ .data = &y };

    var tasks: [3]Runnable = undefined;
    tasks[0] = c1.runnable();
    tasks[1] = c2.runnable();
    tasks[2] = c3.runnable();

    for (tasks) |t| {
        t.run();
    }

    try std.testing.expect(x == 11);
    try std.testing.expect(y == 3);
    try std.testing.expect(c1.data == 2);
}
