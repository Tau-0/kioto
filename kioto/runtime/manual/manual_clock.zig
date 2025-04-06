const std = @import("std");

const assert = std.debug.assert;

pub const ManualClock = struct {
    pub const Duration = struct {
        microseconds: i64,
    };

    pub const TimePoint = struct {
        microseconds: i64,
    };

    // in microseconds
    current_time: TimePoint = .{ .microseconds = 0 },

    pub fn advance(self: *ManualClock, delta: Duration) void {
        self.current_time.microseconds += delta.microseconds;
    }

    pub fn set(self: *ManualClock, timepoint: TimePoint) void {
        assert(timepoint.microseconds >= self.current_time.microseconds);
        self.current_time.microseconds = timepoint.microseconds;
    }

    pub fn now(self: *const ManualClock) TimePoint {
        return self.current_time;
    }
};
