const std = @import("std");

const Allocator = std.mem.Allocator;
const Fiber = @import("../core/fiber.zig").Fiber;
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const Task = @import("../../task/task.zig").Task;

pub fn spawn(runtime: Runtime, task: Task, allocator: Allocator) !void {
    var fiber: *Fiber = try allocator.create(Fiber);
    errdefer allocator.destroy(fiber);

    try fiber.init(runtime, task, allocator, true);
    errdefer fiber.deinit();

    fiber.submitTask();
}

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const ManualRuntime = @import("../../runtime/manual/manual_runtime.zig").ManualRuntime;

const TestRunnable = struct {
    done: bool = false,

    pub fn task(self: *TestRunnable) Task {
        return Task.init(self);
    }

    pub fn run(self: *TestRunnable) void {
        self.done = true;
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var manual: ManualRuntime = .{};
    manual.init(allocator);
    defer manual.deinit();

    var task: TestRunnable = .{};

    try spawn(manual.runtime(), task.task(), allocator);

    try testing.expect(manual.runOne());
    try testing.expect(manual.isEmpty());
    try testing.expect(task.done);
}
