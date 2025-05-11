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

fn FirstCombinator(comptime T: type) type {
    return struct {
        const Self = @This();

        promise: Promise(T),
        remaining_work: Atomic(u32),
        done: Atomic(bool),
        allocator: Allocator,

        pub fn init(self: *Self, promise: Promise(T), allocator: Allocator) void {
            self.promise = promise;
            self.remaining_work = .{ .raw = 2 };
            self.done = .{ .raw = false };
            self.allocator = allocator;
        }

        pub fn set(self: *Self, value: T) void {
            defer self.complete();
            if (self.done.swap(true, .seq_cst)) {
                return;
            }

            self.promise.set(value);
        }

        fn complete(self: *Self) void {
            if (self.remaining_work.fetchSub(1, .seq_cst) == 1) {
                self.allocator.destroy(self);
            }
        }
    };
}

pub fn first(f1: anytype, f2: anytype, allocator: Allocator) !Future((@TypeOf(f1).ValueType)) {
    const T = @TypeOf(f1).ValueType;
    comptime std.debug.assert(T == @TypeOf(f2).ValueType);

    const Combinator = FirstCombinator(T);

    var future1: Future(T) = f1;
    var future2: Future(T) = f2;

    const contract = try futures.makeContract(T, allocator);
    var combinator = try allocator.create(Combinator);
    combinator.init(contract.promise, allocator);

    const Closure = struct {
        const Self = @This();

        pub const ValueType = T;

        combinator: *Combinator,

        pub fn run(self: *Self, value: T) void {
            self.combinator.set(value);
        }
    };

    var callback1 = try futures.makeBoxedCallback(Closure{ .combinator = combinator }, allocator);
    future1.subscribe(callback1.callback());

    var callback2 = try futures.makeBoxedCallback(Closure{ .combinator = combinator }, allocator);
    future2.subscribe(callback2.callback());

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

    var f2: Future(u32) = try futures.ready(@as(u32, 500), allocator);
    f2 = futures.via(f2, rt.runtime());
    f2 = try futures.after(f2, .{ .microseconds = 0.1 * std.time.us_per_s }, allocator);

    var f3: Future(u32) = try first(f1, f2, allocator);
    f3 = futures.via(f3, rt.runtime());

    try testing.expect(futures.get(f3) == 500);
    std.Thread.sleep(2 * std.time.ns_per_s);
}
