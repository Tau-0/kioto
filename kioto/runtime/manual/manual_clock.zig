const std = @import("std");

const time = @import("../time.zig");

const assert = std.debug.assert;

pub const ManualClock = struct {
    current_time: time.TimePoint = .{ .microseconds = 0 },

    pub fn advance(self: *ManualClock, delta: time.Duration) void {
        self.current_time.microseconds += delta.microseconds;
    }

    pub fn set(self: *ManualClock, timepoint: time.TimePoint) void {
        assert(timepoint.microseconds >= self.current_time.microseconds);
        self.current_time.microseconds = timepoint.microseconds;
    }

    pub fn now(self: *const ManualClock) time.TimePoint {
        return self.current_time;
    }
};
