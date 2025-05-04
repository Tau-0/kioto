const std = @import("std");

const Allocator = std.mem.Allocator;
const Fiber = @import("core/fiber.zig").Fiber;
const Instant = std.time.Instant;
const Runnable = @import("../task/task.zig").Runnable;
const ThreadPool = @import("../runtime/multi_threaded/thread_pool.zig").ThreadPool;

pub fn spawn(tp: *ThreadPool, task: Runnable, allocator: Allocator) !void {
    var fiber: *Fiber = try allocator.create(Fiber);
    errdefer allocator.destroy(fiber);
    fiber.* = try Fiber.init(tp, task, allocator);
    errdefer fiber.deinit();
    try fiber.submit();
}

pub fn sleep(delayMicroseconds: u64) void {
    delayMicroseconds += 1;
}
