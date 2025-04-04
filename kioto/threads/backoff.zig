const std = @import("std");

// Based on https://github.com/crossbeam-rs/crossbeam/blob/master/crossbeam-utils/src/backoff.rs
pub const Backoff = struct {
    const spin_limit: usize = 6;
    const yield_limit: usize = 10;
    step: u6 = 0,

    pub fn spin(self: *Backoff) void {
        if (self.step < spin_limit) {
            for (0..self.stepLimit()) |_| {
                pause();
            }
        } else {
            std.Thread.yield() catch @panic("CAN NOT YIELD");
        }
        self.step +|= 1;
    }

    pub fn isCompleted(self: *const Backoff) bool {
        return self.step > yield_limit;
    }

    inline fn stepLimit(self: *const Backoff) usize {
        return @as(usize, 1) << self.step;
    }

    inline fn pause() void {
        asm volatile ("pause" ::: "memory");
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

test "basic" {
    var backoff: Backoff = .{};
    for (0..100) |i| {
        const expected_backoff = std.math.pow(usize, 2, @min(i, 63));
        testing.expect(backoff.stepLimit() == expected_backoff) catch @panic("TEST FAIL");
        backoff.spin();
    }
    testing.expect(backoff.isCompleted()) catch @panic("TEST FAIL");
}
