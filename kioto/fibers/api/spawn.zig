const std = @import("std");

const Allocator = std.mem.Allocator;
const Fiber = @import("../core/fiber.zig").Fiber;
const Runnable = @import("../../task/task.zig").Runnable;
const Runtime = @import("../../runtime/runtime.zig").Runtime;

pub fn spawn(runtime: Runtime, task: Runnable, allocator: Allocator) !void {
    var fiber: *Fiber = try allocator.create(Fiber);
    errdefer allocator.destroy(fiber);

    fiber.* = try Fiber.init(runtime, task, allocator, true);
    errdefer fiber.deinit();

    fiber.submitTask();
}

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const ManualRuntime = @import("../../runtime/manual/manual_runtime.zig").ManualRuntime;

const TestRunnable = struct {
    x: i32 = undefined,

    pub fn runnable(self: *TestRunnable) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *TestRunnable) void {
        std.debug.print("{}\n", .{self.x});
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var manual: ManualRuntime = ManualRuntime.init(allocator);
    defer manual.deinit();

    var task: TestRunnable = .{ .x = 100 };

    try spawn(manual.runtime(), task.runnable(), allocator);

    testing.expect(manual.runOne()) catch @panic("TEST FAIL");
    testing.expect(manual.isEmpty()) catch @panic("TEST FAIL");
}
