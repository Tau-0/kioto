const std = @import("std");

const futures = struct {
    usingnamespace @import("../core/contract.zig");
    usingnamespace @import("constructors.zig");
};

const Contract = futures.Contract;
const Future = futures.Future;
const Promise = futures.Promise;

const Allocator = std.mem.Allocator;
const Callback = @import("../core/callback.zig").Callback;
const Event = @import("../../threads/event.zig").Event;
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const Unit = @import("../core/unit.zig").Unit;

pub fn map()

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const fibers = struct {
    usingnamespace @import("../../fibers/api.zig");
};

const ConcurrentRuntime = @import("../../runtime/concurrent/concurrent_runtime.zig").ConcurrentRuntime;
const Task = @import("../../task/task.zig").Task;

const TestRunnable = struct {
    promise: Promise(u32) = undefined,

    pub fn task(self: *TestRunnable) Task {
        return Task.init(self);
    }

    pub fn run(self: *TestRunnable) void {
        fibers.sleepFor(.{ .microseconds = 0.5 * std.time.us_per_s });
        self.promise.set(10);
    }
};

test "get" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ConcurrentRuntime = .{};
    rt.init(2, allocator);
    defer rt.deinit();

    rt.allowTimers().start();
    defer rt.stop();

    var contract: Contract(u32) = try futures.makeContract(u32, allocator);
    var task: TestRunnable = .{ .promise = contract.promise };
    contract.future.setRuntime(rt.runtime());

    try fibers.spawn(rt.runtime(), task.task(), allocator);

    const value: u32 = get(u32, contract.future);
    try testing.expect(value == 10);
}
