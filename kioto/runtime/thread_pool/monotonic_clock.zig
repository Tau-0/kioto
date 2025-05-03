const std = @import("std");

const assert = std.debug.assert;

const Timer = std.time.Timer;

pub const MonotonicClock = struct {
    const Self = @This();

    pub const Duration = struct {
        microseconds: u64,
    };

    pub const TimePoint = struct {
        microseconds: u64,
    };

    timer: Timer = undefined,

    pub fn init() Self {
        return .{
            .timer = Timer.start() catch unreachable,
        };
    }

    pub fn now(self: *Self) TimePoint {
        const current_time = self.timer.read();
        return .{
            .microseconds = @divTrunc(current_time, std.time.ns_per_us),
        };
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

test "basic" {
    var clock = MonotonicClock.init();
    const start = clock.now();

    std.Thread.sleep(1 * std.time.ns_per_s);

    const finish = clock.now();

    try testing.expect(finish.microseconds - start.microseconds >= 1 * std.time.ms_per_s);
}
