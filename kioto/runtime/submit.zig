const std = @import("std");

const makeBoxedTask = @import("../task/boxed_task.zig").makeBoxedTask;

const Allocator = std.mem.Allocator;
const Duration = @import("time.zig").Duration;
const Runtime = @import("runtime.zig").Runtime;

pub fn submitTask(task: anytype, runtime: Runtime, allocator: Allocator) !void {
    var boxed_task = try makeBoxedTask(task, allocator);
    runtime.submitTask(boxed_task.getHook());
}

pub fn submitTimer(task: anytype, delay: Duration, runtime: Runtime, allocator: Allocator) !void {
    var boxed_task = try makeBoxedTask(task, allocator);
    runtime.submitTimer(boxed_task.getHook(), delay);
}
