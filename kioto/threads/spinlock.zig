const std = @import("std");

const Atomic = std.atomic.Value;
const Backoff = @import("backoff.zig").Backoff;

pub const Spinlock = struct {
    locked: Atomic(bool) = false,

    pub fn lock(self: *Spinlock) void {
        var backoff: Backoff = .{};
        while (self.locked.swap(true, .seq_cst)) {
            while (self.locked.load(.seq_cst)) {
                backoff.spin();
            }
        }
    }

    pub fn tryLock(self: *Spinlock) bool {
        return !self.locked.swap(true, .seq_cst);
    }

    pub fn unlock(self: *Spinlock) void {
        self.locked.store(false, .seq_cst);
    }
};

//////
