const std = @import("std");

const futures = struct {
    usingnamespace @import("../core/boxed_callback.zig");
    usingnamespace @import("../core/contract.zig");
    usingnamespace @import("constructors.zig");
    usingnamespace @import("terminators.zig");
};

const tasks = struct {
    usingnamespace @import("../../runtime/submit.zig");
};

const Contract = futures.Contract;
const Future = futures.Future;
const Promise = futures.Promise;

const Allocator = std.mem.Allocator;
const Callback = @import("../core/callback.zig").Callback;
const Duration = @import("../../runtime/time.zig").Duration;
const Event = @import("../../threads/event.zig").Event;
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const Unit = @import("../core/unit.zig").Unit;

pub fn map(future: anytype, mapper: anytype, allocator: Allocator) !Future(@TypeOf(mapper).ReturnType) {
    const T = @TypeOf(future).ValueType;
    const U = @TypeOf(mapper).ReturnType;

    var f: Future(T) = future;
    var contract: Contract(U) = try futures.makeContract(U, allocator);
    contract.future.setRuntime(f.getRuntime());

    const Closure = struct {
        const Self = @This();

        pub const ValueType = T;

        promise: Promise(U),
        mapper: @TypeOf(mapper),

        pub fn run(self: *Self, value: T) void {
            self.promise.set(self.mapper.run(value));
        }
    };

    const closure = Closure{ .promise = contract.promise, .mapper = mapper };
    var callback = try futures.makeBoxedCallback(closure, allocator);

    f.subscribe(callback.callback());
    return contract.future;
}

pub fn flatten(future: anytype, allocator: Allocator) !@TypeOf(future).ValueType {
    const FutureType = @TypeOf(future);
    const NestedFutureType = FutureType.ValueType;
    const T = NestedFutureType.ValueType;

    var f: Future(Future(T)) = future;
    var contract: Contract(T) = try futures.makeContract(T, allocator);
    contract.future.setRuntime(f.getRuntime());

    const InnerClosure = struct {
        pub const ValueType = T;

        promise: Promise(T),

        pub fn run(self: *@This(), value: T) void {
            self.promise.set(value);
        }

        pub fn callback(self: *@This()) Callback(T) {
            return Callback(T).init(self);
        }
    };

    const Closure = struct {
        const Self = @This();

        pub const ValueType = Future(T);

        callback: Callback(T),

        pub fn run(self: *Self, value: Future(T)) void {
            var f_t: Future(T) = value;
            f_t.subscribe(self.callback);
        }
    };

    const inner_callback = try futures.makeBoxedCallback(InnerClosure{ .promise = contract.promise }, allocator);
    var callback = try futures.makeBoxedCallback(Closure{ .callback = inner_callback.callback() }, allocator);
    f.subscribe(callback.callback());
    return contract.future;
}

pub fn flatMap(future: anytype, mapper: anytype, allocator: Allocator) !@TypeOf(mapper).ReturnType {
    const T = @TypeOf(future).ValueType;
    const U = @TypeOf(mapper).ReturnType.ValueType;

    var f: Future(T) = future;
    var contract = try futures.makeContract(U, allocator);
    contract.future.setRuntime(f.getRuntime());

    const InnerClosure = struct {
        pub const ValueType = U;

        promise: Promise(U),

        pub fn run(self: *@This(), value: U) void {
            self.promise.set(value);
        }

        pub fn callback(self: *@This()) Callback(U) {
            return Callback(U).init(self);
        }
    };

    const Closure = struct {
        const Self = @This();

        pub const ValueType = T;

        mapper: @TypeOf(mapper),
        callback: Callback(U),

        pub fn run(self: *Self, value: T) void {
            var f_u: Future(U) = self.mapper.run(value);
            f_u.subscribe(self.callback);
        }
    };

    const inner_callback = try futures.makeBoxedCallback(InnerClosure{ .promise = contract.promise }, allocator);
    var callback = try futures.makeBoxedCallback(Closure{ .mapper = mapper, .callback = inner_callback.callback() }, allocator);
    f.subscribe(callback.callback());
    return contract.future;
}

pub fn via(future: anytype, runtime: Runtime) @TypeOf(future) {
    const T = @TypeOf(future).ValueType;
    var f: Future(T) = future;
    f.setRuntime(runtime);
    return f;
}

pub fn after(future: anytype, delay: Duration, allocator: Allocator) !@TypeOf(future) {
    const T = @TypeOf(future).ValueType;
    var f: Future(T) = future;
    std.debug.assert(f.getRuntime() != null);
    const runtime: Runtime = f.getRuntime().?;

    var contract = try futures.makeContract(T, allocator);
    contract.future = via(contract.future, runtime);

    const Closure = struct {
        pub const ValueType = T;

        promise: Promise(T),

        pub fn run(self: *@This(), value: T) void {
            self.promise.set(value);
        }

        pub fn callback(self: *@This()) Callback(T) {
            return Callback(T).init(self);
        }
    };

    const TimerTask = struct {
        future: Future(T),
        callback: Callback(T),

        pub fn run(self: *@This()) void {
            self.future.subscribe(self.callback);
        }
    };

    var callback = try futures.makeBoxedCallback(Closure{ .promise = contract.promise }, allocator);
    try tasks.submitTimer(TimerTask{ .future = f, .callback = callback.callback() }, delay, runtime, allocator);

    return contract.future;
}

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const fibers = struct {
    usingnamespace @import("../../fibers/api.zig");
};

const ConcurrentRuntime = @import("../../runtime/concurrent/concurrent_runtime.zig").ConcurrentRuntime;
const Task = @import("../../task/task.zig").Task;

const TestCallback = struct {
    value: u32 = 5,

    pub fn callback(self: *TestCallback) Callback(u32) {
        return Callback(u32).init(self);
    }

    pub fn run(self: *TestCallback, value: u32) void {
        self.value *= value;
    }
};

const MapperToBool = struct {
    pub const ValueType = u32;
    pub const ReturnType = bool;

    pub fn run(_: *@This(), value: u32) bool {
        return value == 10;
    }
};

const MapperToU32 = struct {
    pub const ValueType = bool;
    pub const ReturnType = u32;

    pub fn run(_: *@This(), value: bool) u32 {
        if (value) {
            return 20;
        } else {
            return 10;
        }
    }
};

const IntFunction = struct {
    v: u32,

    pub fn run(self: *@This()) u32 {
        return self.v;
    }
};

const MapperToFutureBool = struct {
    pub const ValueType = u32;
    pub const ReturnType = Future(bool);

    allocator: Allocator,

    pub fn run(self: *@This(), value: u32) Future(bool) {
        if (value == 10) {
            return futures.ready(@as(bool, true), self.allocator) catch |err| std.debug.panic("{}\n", .{err});
        } else {
            return futures.ready(@as(bool, false), self.allocator) catch |err| std.debug.panic("{}\n", .{err});
        }
    }
};

test "map" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ConcurrentRuntime = .{};
    rt.init(2, allocator);
    defer rt.deinit();

    rt.allowTimers().start();
    defer rt.stop();

    var f1: Future(u32) = try futures.ready(@as(u32, 10), allocator);
    f1.setRuntime(rt.runtime());

    const f2: Future(bool) = try map(f1, MapperToBool{}, allocator);
    try testing.expect(f2.getRuntime() != null);
    const f3: Future(u32) = try map(f2, MapperToU32{}, allocator);
    try testing.expect(f3.getRuntime() != null);

    try testing.expect(futures.get(f3) == 20);
}

test "simple_flatten" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ConcurrentRuntime = .{};
    rt.init(2, allocator);
    defer rt.deinit();

    rt.allowTimers().start();
    defer rt.stop();

    var contract = try futures.makeContract(u32, allocator);
    var f1: Future(u32) = contract.future;
    try testing.expect(f1.state != null);
    f1 = via(f1, rt.runtime());
    try testing.expect(f1.getRuntime() != null);

    var f2: Future(Future(u32)) = try futures.ready(f1, allocator);
    try testing.expect(f2.state != null);
    f2 = via(f2, rt.runtime());
    try testing.expect(f2.getRuntime() != null);

    var f3: Future(u32) = try flatten(f2, allocator);
    try testing.expect(f3.state != null);
    try testing.expect(f3.getRuntime() != null);

    contract.promise.set(10);
    try testing.expect(futures.get(f3) == 10);
}

test "deep_flatten" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ConcurrentRuntime = .{};
    rt.init(2, allocator);
    defer rt.deinit();

    rt.allowTimers().start();
    defer rt.stop();

    var f1: Future(u32) = try futures.ready(@as(u32, 10), allocator);
    try testing.expect(f1.state != null);
    f1 = via(f1, rt.runtime());

    var f2: Future(Future(u32)) = try futures.ready(f1, allocator);
    try testing.expect(f2.state != null);
    f2 = via(f2, rt.runtime());

    var f3: Future(Future(Future(u32))) = try futures.ready(f2, allocator);
    try testing.expect(f3.state != null);
    f3 = via(f3, rt.runtime());

    var f4: Future(Future(u32)) = try flatten(f3, allocator);
    try testing.expect(f4.getRuntime() != null);

    var f5: Future(u32) = try flatten(f4, allocator);
    try testing.expect(f5.getRuntime() != null);

    try testing.expect(futures.get(f5) == 10);
}

test "flat_map" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ConcurrentRuntime = .{};
    rt.init(2, allocator);
    defer rt.deinit();

    rt.allowTimers().start();
    defer rt.stop();

    var f1: Future(u32) = try futures.ready(@as(u32, 10), allocator);
    f1 = via(f1, rt.runtime());

    const mapper = MapperToFutureBool{ .allocator = allocator };
    const f2: Future(bool) = try flatMap(f1, mapper, allocator);
    try testing.expect(f2.getRuntime() != null);
    try testing.expect(futures.get(f2));
}

test "after" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ConcurrentRuntime = .{};
    rt.init(2, allocator);
    defer rt.deinit();

    rt.allowTimers().start();
    defer rt.stop();

    var f1: Future(u32) = try futures.ready(@as(u32, 10), allocator);
    f1 = via(f1, rt.runtime());
    f1 = try after(f1, .{ .microseconds = 1 * std.time.us_per_s }, allocator);
    try testing.expect(futures.get(f1) == 10);
}
