const std = @import("std");

// Interface template, any implementation of Callback should define (type Impl here):
// - fn callback(self: *Impl) Callback(T)
// - fn run(self: *Impl, value: T) void
pub fn Callback(comptime T: type) type {
    return struct {
        const Self = @This();

        impl: *anyopaque = undefined,
        run_fn: *const fn (ptr: *anyopaque, value: T) void = undefined,

        pub fn init(impl: anytype) Self {
            const ImplType = @TypeOf(impl);

            const Impl = struct {
                pub fn run(ptr: *anyopaque, value: T) void {
                    const self: ImplType = @ptrCast(@alignCast(ptr));
                    self.run(value);
                }
            };

            return .{
                .impl = impl,
                .run_fn = Impl.run,
            };
        }

        pub fn run(self: Self, value: T) void {
            self.run_fn(self.impl, value);
        }
    };
}

////////////////////////////////////////////////////////////////////////////////

const Unit = @import("unit.zig").Unit;

const CallbackU64 = struct {
    data: u64 = 0,

    pub fn callback(self: *CallbackU64) Callback(u64) {
        return Callback(u64).init(self);
    }

    pub fn run(self: *CallbackU64, value: u64) void {
        self.data = value;
    }
};

const CallbackUnit = struct {
    done: bool = false,

    pub fn callback(self: *CallbackUnit) Callback(Unit) {
        return Callback(Unit).init(self);
    }

    pub fn run(self: *CallbackUnit, _: Unit) void {
        self.done = true;
    }
};

test "basic" {
    var c1: CallbackU64 = .{};
    var c2: CallbackUnit = .{};

    c1.run(10);
    c2.run(.{});

    try std.testing.expect(c1.data == 10);
    try std.testing.expect(c2.done);
}
