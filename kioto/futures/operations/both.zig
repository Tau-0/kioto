const std = @import("std");

const futures = struct {
    usingnamespace @import("../core/boxed_callback.zig");
    usingnamespace @import("../core/contract.zig");
    usingnamespace @import("combinators.zig");
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
const Atomic = std.atomic.Value;
const Callback = @import("../core/callback.zig").Callback;
const Duration = @import("../../runtime/time.zig").Duration;
const Event = @import("../../threads/event.zig").Event;
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const Unit = @import("../core/unit.zig").Unit;

fn Pair(comptime T: type, comptime U: type) type {
    return struct {
        first: T,
        second: U,
    };
}

fn BothCombinator(comptime T: type, comptime U: type) type {
    return struct {
        const Self = @This();
        const PromiseType = Promise(Pair(T, U));

        t: ?T,
        u: ?U,
        promise: PromiseType,
        remaining_work: Atomic(u32),
        allocator: Allocator,

        pub fn init(self: *Self, promise: PromiseType, allocator: Allocator) void {
            self.t = null;
            self.u = null;
            self.promise = promise;
            self.remaining_work = .{ .raw = 2 };
            self.allocator = allocator;
        }

        pub fn set(self: *Self, index: comptime_int, value: anytype) void {
            if (comptime index == 0) {
                comptime std.debug.assert(@TypeOf(value) == T);
                self.t = value;
            } else {
                comptime std.debug.assert(@TypeOf(value) == U);
                self.u = value;
            }

            if (self.remaining_work.fetchSub(1, .seq_cst) == 2) {
                return;
            }

            self.complete();
        }

        fn complete(self: *Self) void {
            std.debug.assert(self.t != null and self.u != null);
            self.promise.set(Pair(T, U){ .first = self.t.?, .second = self.u.? });
            self.allocator.destroy(self);
        }
    };
}

pub fn both(t: anytype, u: anytype, allocator: Allocator) !Future(Pair(@TypeOf(t).ValueType, @TypeOf(u).ValueType)) {
    const T = @TypeOf(t).ValueType;
    const U = @TypeOf(u).ValueType;
    const Combinator = BothCombinator(T, U);

    var future_t: Future(T) = t;
    var future_u: Future(U) = u;

    const contract = try futures.makeContract(Pair(T, U), allocator);
    var combinator = try allocator.create(Combinator);
    combinator.init(contract.promise, allocator);

    const ClosureT = struct {
        const Self = @This();

        pub const ValueType = T;

        combinator: *Combinator,

        pub fn run(self: *Self, value: T) void {
            self.combinator.set(0, value);
        }
    };

    const ClosureU = struct {
        const Self = @This();

        pub const ValueType = U;

        combinator: *Combinator,

        pub fn run(self: *Self, value: U) void {
            self.combinator.set(1, value);
        }
    };

    var callback_t = try futures.makeBoxedCallback(ClosureT{ .combinator = combinator }, allocator);
    future_t.subscribe(callback_t.callback());

    var callback_u = try futures.makeBoxedCallback(ClosureU{ .combinator = combinator }, allocator);
    future_u.subscribe(callback_u.callback());

    return contract.future;
}

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const ConcurrentRuntime = @import("../../runtime/concurrent/concurrent_runtime.zig").ConcurrentRuntime;

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var rt: ConcurrentRuntime = .{};
    rt.init(2, allocator);
    defer rt.deinit();

    rt.allowTimers().start();
    defer rt.stop();

    var f1: Future(u32) = try futures.ready(@as(u32, 10), allocator);
    f1 = futures.via(f1, rt.runtime());
    f1 = try futures.after(f1, .{ .microseconds = 1 * std.time.us_per_s }, allocator);

    var f2: Future(bool) = try futures.ready(@as(bool, true), allocator);
    f2 = futures.via(f2, rt.runtime());
    f2 = try futures.after(f2, .{ .microseconds = 0.1 * std.time.us_per_s }, allocator);

    var f3: Future(Pair(u32, bool)) = try both(f1, f2, allocator);
    f3 = futures.via(f3, rt.runtime());

    const result: Pair(u32, bool) = futures.get(f3);
    try testing.expect(result.first == 10 and result.second);
}
