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
const FiberEvent = @import("../../fibers/sync/event.zig").Event;
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const ThreadEvent = @import("../../threads/event.zig").Event;
const Unit = @import("../core/unit.zig").Unit;

// For threads
pub fn get(future: anytype) @TypeOf(future).ValueType {
    const T = @TypeOf(future).ValueType;

    var event: ThreadEvent = .{};
    var value: ?T = null;
    var f = future;
    f.setRuntime(null);

    const Closure = struct {
        const Self = @This();

        event: *ThreadEvent = undefined,
        value: *?T = undefined,

        fn callback(self: *Self) Callback(T) {
            return Callback(T).init(self);
        }

        pub fn run(self: *Self, t: T) void {
            self.value.* = t;
            self.event.fire();
        }
    };

    var closure: Closure = .{ .event = &event, .value = &value };
    f.subscribe(closure.callback());
    event.wait();
    std.debug.assert(value != null);
    return value.?;
}

// For fibers
pub fn awaitFuture(future: anytype) @TypeOf(future).ValueType {
    const T = @TypeOf(future).ValueType;

    var event: FiberEvent = .{};
    event.init();

    var value: ?T = null;
    var f = future;
    f.setRuntime(null);

    const Closure = struct {
        const Self = @This();

        event: *FiberEvent = undefined,
        value: *?T = undefined,

        fn callback(self: *Self) Callback(T) {
            return Callback(T).init(self);
        }

        pub fn run(self: *Self, t: T) void {
            self.value.* = t;
            self.event.fire();
        }
    };

    var closure: Closure = .{ .event = &event, .value = &value };
    f.subscribe(closure.callback());
    event.wait();
    std.debug.assert(value != null);
    return value.?;
}

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const fibers = struct {
    usingnamespace @import("../../fibers/api.zig");
};

const ConcurrentRuntime = @import("../../runtime/concurrent/concurrent_runtime.zig").ConcurrentRuntime;
const ManualRuntime = @import("../../runtime/manual/manual_runtime.zig").ManualRuntime;
const Task = @import("../../task/task.zig").Task;

const ProducerTask = struct {
    promise: Promise(u32) = undefined,

    pub fn task(self: *ProducerTask) Task {
        return Task.init(self);
    }

    pub fn run(self: *ProducerTask) void {
        fibers.sleepFor(.{ .microseconds = 0.5 * std.time.us_per_s });
        self.promise.set(10);
    }
};

const ConsumerTask = struct {
    future: Future(u32) = undefined,

    pub fn task(self: *ConsumerTask) Task {
        return Task.init(self);
    }

    pub fn run(self: *ConsumerTask) void {
        const value: u32 = awaitFuture(self.future);
        std.debug.assert(value == 10);
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
    var task: ProducerTask = .{ .promise = contract.promise };
    contract.future.setRuntime(rt.runtime());

    try fibers.spawn(rt.runtime(), task.task(), allocator);

    const value: u32 = get(contract.future);
    try testing.expect(value == 10);
}

test "await" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    // defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ManualRuntime = .{};
    rt.init(allocator);
    defer rt.deinit();

    var contract: Contract(u32) = try futures.makeContract(u32, allocator);
    var producer: ProducerTask = .{ .promise = contract.promise };
    var consumer: ConsumerTask = .{ .future = contract.future };

    contract.future.setRuntime(rt.runtime());
    try fibers.spawn(rt.runtime(), consumer.task(), allocator);
    try fibers.spawn(rt.runtime(), producer.task(), allocator);

    try testing.expect(rt.queueSize() == 2);
    try testing.expect(rt.runLimited(2) == 2);
    try testing.expect(rt.setClockToNextDeadline() == 1);
    try testing.expect(rt.queueSize() == 1);
    try testing.expect(rt.runOne());
    try testing.expect(rt.queueSize() == 1);
    try testing.expect(rt.runOne());
}
