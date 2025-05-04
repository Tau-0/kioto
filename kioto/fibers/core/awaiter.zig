const std = @import("std");

const Fiber = @import("fiber.zig").Fiber;

// Interface, any implementation of Awaiter should implement (type T here):
// - fn awaiter(self: *T) Awaiter
// - fn afterSuspend(self: *T) void
pub const Awaiter = struct {
    impl: *anyopaque = undefined,
    after_suspend_fn: *const fn (ptr: *anyopaque, fiber: *Fiber) void = undefined,

    pub fn init(impl: anytype) Awaiter {
        const T = @TypeOf(impl);

        const Impl = struct {
            pub fn afterSuspend(ptr: *anyopaque, fiber: *Fiber) void {
                const self: T = @ptrCast(@alignCast(ptr));
                self.afterSuspend(fiber);
            }
        };

        return .{
            .impl = impl,
            .after_suspend_fn = Impl.afterSuspend,
        };
    }

    pub fn afterSuspend(self: Awaiter, fiber: *Fiber) void {
        self.after_suspend_fn(self.impl, fiber);
    }
};
