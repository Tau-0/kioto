const std = @import("std");

const Atomic = std.atomic.Value;
const Futex = std.Thread.Futex;

pub const Event = struct {
    const Self = @This();

    fired: Atomic(u32) = .{ .raw = 0 },

    pub fn wait(self: *Self) void {
        while (self.fired.load(.acquire) == 0) {
            Futex.wait(&self.fired, 0);
        }
    }

    pub fn fire(self: *Self) void {
        const wake_key: *Atomic(u32) = &self.fired;
        self.fired.store(1, .release);
        Futex.wake(wake_key, std.math.maxInt(u32));
    }
};
