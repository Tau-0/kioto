const std = @import("std");

const futures = struct {
    usingnamespace @import("../core/contract.zig");
};

const submitTask = @import("../../runtime/submit.zig").submitTask;

const Contract = futures.Contract;
const Future = futures.Future;
const Promise = futures.Promise;

const Allocator = std.mem.Allocator;
const Callback = @import("../core/callback.zig").Callback;
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const Unit = @import("../core/unit.zig").Unit;

pub fn makeContract(comptime T: type, allocator: Allocator) !Contract(T) {
    return Contract(T).init(allocator);
}

pub fn ready(value: anytype, allocator: Allocator) !Future(@TypeOf(value)) {
    const T = @TypeOf(value);

    var contract = try makeContract(T, allocator);
    contract.promise.set(value);
    return contract.future;
}

pub fn unit(allocator: Allocator) !Future(Unit) {
    return ready(Unit{}, allocator);
}

fn FunctionType(comptime function: anytype) type {
    return @TypeOf(@TypeOf(function).run);
}

fn ReturnType(comptime function: anytype) type {
    const F = FunctionType(function);
    return @typeInfo(F).@"fn".return_type.?;
}

pub fn spawn(comptime function: anytype, runtime: Runtime, allocator: Allocator) !Future(ReturnType(function)) {
    const T = ReturnType(function);

    const Closure = struct {
        promise: Promise(T),
        function: @TypeOf(function),

        pub fn run(self: *@This()) void {
            const value: T = self.function.run();
            self.promise.set(value);
        }
    };

    const contract = try makeContract(T, allocator);
    const closure: Closure = .{ .promise = contract.promise, .function = function };
    try submitTask(closure, runtime, allocator);
    return contract.future;
}

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const ManualRuntime = @import("../../runtime/manual/manual_runtime.zig").ManualRuntime;

const TestCallback = struct {
    value: u32 = 5,

    pub fn callback(self: *TestCallback) Callback(u32) {
        return Callback(u32).init(self);
    }

    pub fn run(self: *TestCallback, value: u32) void {
        self.value *= value;
    }
};

const TestFunction = struct {
    done: bool = false,

    pub fn run(self: *@This()) u32 {
        self.done = true;
        return 10;
    }
};

test "make_contract" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ManualRuntime = .{};
    rt.init(allocator);
    defer rt.deinit();

    var callback: TestCallback = .{};

    var contract: Contract(u32) = try makeContract(u32, allocator);
    contract.promise.set(10);
    contract.future.setRuntime(rt.runtime());
    contract.future.subscribe(callback.callback());

    try testing.expect(callback.value == 5);
    try testing.expect(rt.runOne());
    try testing.expect(rt.isEmpty());
    try testing.expect(callback.value == 50);
}

test "ready" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ManualRuntime = .{};
    rt.init(allocator);
    defer rt.deinit();

    var callback: TestCallback = .{};
    var future = try ready(@as(u32, 10), allocator);
    future.setRuntime(rt.runtime());
    future.subscribe(callback.callback());

    try testing.expect(callback.value == 5);
    try testing.expect(rt.runOne());
    try testing.expect(rt.isEmpty());
    try testing.expect(callback.value == 50);
}

test "unit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ManualRuntime = .{};
    rt.init(allocator);
    defer rt.deinit();

    const UnitCallback = struct {
        done: bool = false,

        pub fn callback(self: *@This()) Callback(Unit) {
            return Callback(Unit).init(self);
        }

        pub fn run(self: *@This(), _: Unit) void {
            self.done = true;
            std.debug.print("Unit\n", .{});
        }
    };

    var callback: UnitCallback = .{};
    var future = try unit(allocator);
    future.setRuntime(rt.runtime());
    future.subscribe(callback.callback());

    try testing.expect(!callback.done);
    try testing.expect(rt.runOne());
    try testing.expect(rt.isEmpty());
    try testing.expect(callback.done);
}

test "spawn" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ManualRuntime = .{};
    rt.init(allocator);
    defer rt.deinit();

    var callback: TestCallback = .{};

    const function: TestFunction = .{};

    var future: Future(u32) = try spawn(function, rt.runtime(), allocator);
    future.subscribe(callback.callback());

    try testing.expect(callback.value == 5);
    try testing.expect(rt.runOne());
    try testing.expect(rt.isEmpty());
    try testing.expect(callback.value == 50);
}
