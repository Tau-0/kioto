const std = @import("std");

const Allocator = std.mem.Allocator;
const Atomic = std.atomic.Value;
const Callback = @import("callback.zig").Callback;
const IntrusiveTask = @import("../../task/intrusive_task.zig").IntrusiveTask;
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const Task = @import("../../task/task.zig").Task;

const StateMachine = enum(u32) {
    Initial,
    OnlyCallback,
    OnlyValue,
    Rendezvous,
};

fn SharedState(comptime T: type) type {
    return struct {
        const Self = @This();

        value: ?T = null,
        callback: Callback(T) = undefined,
        runtime: Runtime = undefined,
        state_machine: Atomic(StateMachine) = undefined,
        allocator: Allocator = undefined,
        hook: IntrusiveTask = .{},

        fn init(runtime: Runtime, allocator: Allocator) !*Self {
            var self: *Self = try allocator.create(Self);
            self.runtime = runtime;
            self.state_machine = .init(.Initial);
            self.allocator = allocator;
            self.hook.init(Task.init(self));
            return self;
        }

        fn deinit(self: *Self) void {
            self.allocator.destroy(self);
        }

        fn getRuntime(self: *const Self) Runtime {
            return self.runtime;
        }

        fn setCallback(self: *Self, callback: Callback(T)) void {
            self.callback = callback;
            switch (self.state_machine.swap(.OnlyCallback, .seq_cst)) {
                .Initial => {},
                .OnlyCallback => std.debug.panic("Callback was set before\n", .{}),
                .OnlyValue => self.execute(),
                .Rendezvous => std.debug.panic("Already done\n", .{}),
            }
        }

        fn setValue(self: *Self, value: T) void {
            self.value = value;
            switch (self.state_machine.swap(.OnlyValue, .seq_cst)) {
                .Initial => {},
                .OnlyCallback => self.execute(),
                .OnlyValue => std.debug.panic("Value was set before\n", .{}),
                .Rendezvous => std.debug.panic("Already done\n", .{}),
            }
        }

        fn execute(self: *Self) void {
            self.state_machine.store(.Rendezvous, .seq_cst);
            self.runtime.submitTask(&self.hook);
        }

        // Task impl
        pub fn run(self: *Self) void {
            std.debug.assert(self.value != null);
            std.debug.assert(self.state_machine.load(.seq_cst) == .Rendezvous);
            self.callback.run(self.value.?);
            self.deinit();
        }
    };
}

pub fn Promise(comptime T: type) type {
    return struct {
        const Self = @This();
        const State = SharedState(T);

        state: ?*State = null,

        pub fn set(self: *Self, value: T) void {
            std.debug.assert(self.state != null);
            self.state.?.setValue(value);
            self.state = null;
        }
    };
}

pub fn Future(comptime T: type) type {
    return struct {
        const Self = @This();
        const State = SharedState(T);

        state: ?*State = null,

        pub fn subscribe(self: *Self, callback: Callback(T)) void {
            std.debug.assert(self.state != null);
            self.state.?.setCallback(callback);
            self.state = null;
        }
    };
}

pub fn Contract(comptime T: type) type {
    return struct {
        promise: Promise(T) = undefined,
        future: Future(T) = undefined,
    };
}

pub fn makeContract(comptime T: type, runtime: Runtime, allocator: Allocator) !Contract(T) {
    const state: *SharedState(T) = try SharedState(T).init(runtime, allocator);
    return Contract(T){ .promise = .{ .state = state }, .future = .{ .state = state } };
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

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ManualRuntime = .{};
    rt.init(allocator);
    defer rt.deinit();

    var callback: TestCallback = .{};

    var contract: Contract(u32) = try makeContract(u32, rt.runtime(), allocator);
    contract.promise.set(10);
    contract.future.subscribe(callback.callback());

    try testing.expect(callback.value == 5);
    try testing.expect(rt.runOne());
    try testing.expect(rt.isEmpty());
    try testing.expect(callback.value == 50);
}
