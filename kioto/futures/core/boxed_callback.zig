const std = @import("std");

const Allocator = std.mem.Allocator;
const Callback = @import("callback.zig").Callback;

// Owning wrapper over any callable type (Callable here) with defined method "run":
// - fn run(self: *Callable, value: T) void
fn BoxedCallback(comptime CallbackType: type) type {
    return struct {
        const Self = @This();

        const T = CallbackType.ValueType;

        function: CallbackType = undefined,
        allocator: Allocator = undefined,

        fn init(self: *Self, function: CallbackType, allocator: Allocator) void {
            self.function = function;
            self.allocator = allocator;
        }

        fn deinit(self: *Self) void {
            self.allocator.destroy(self);
        }

        pub fn run(self: *Self, value: T) void {
            self.function.run(value);
            self.deinit();
        }

        pub fn callback(self: *Self) Callback(T) {
            return Callback(T).init(self);
        }
    };
}

pub fn makeBoxedCallback(callback: anytype, allocator: Allocator) !*BoxedCallback(@TypeOf(callback)) {
    var boxed_callback = try allocator.create(BoxedCallback(@TypeOf(callback)));
    boxed_callback.init(callback, allocator);
    return boxed_callback;
}

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const TaskA = struct {
    const ValueType = u64;

    pub fn run(_: *TaskA, value: u64) void {
        std.debug.assert(value == 10);
    }
};

fn testFn(allocator: Allocator) !*BoxedCallback(TaskA) {
    const task: TaskA = .{};
    return try makeBoxedCallback(task, allocator);
}

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var boxed_task = try testFn(allocator);
    boxed_task.run(10);
}
