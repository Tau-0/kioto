const std = @import("std");

const Awaiter = @import("../core/awaiter.zig").Awaiter;
const Fiber = @import("../core/fiber.zig").Fiber;

pub fn suspendFiber(awaiter: Awaiter) void {
    Fiber.current().?.suspendFiber(awaiter);
}
