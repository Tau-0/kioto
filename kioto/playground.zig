const std = @import("std");

const fibers = struct {
    usingnamespace @import("fibers/api.zig");
    usingnamespace @import("fibers/sync/buffered_channel.zig");
    usingnamespace @import("fibers/sync/event.zig");
    usingnamespace @import("fibers/sync/mutex.zig");
    usingnamespace @import("fibers/sync/unbuffered_channel.zig");
    usingnamespace @import("fibers/sync/wait_group.zig");
};

const futures = struct {
    usingnamespace @import("futures/core/contract.zig");
    usingnamespace @import("futures/operations/both.zig");
    usingnamespace @import("futures/operations/combinators.zig");
    usingnamespace @import("futures/operations/constructors.zig");
    usingnamespace @import("futures/operations/first.zig");
    usingnamespace @import("futures/operations/terminators.zig");
};

const runtime = struct {
    usingnamespace @import("runtime/runtime.zig");
    usingnamespace @import("runtime/submit.zig");
    usingnamespace @import("runtime/concurrent/concurrent_runtime.zig");
    usingnamespace @import("runtime/manual/manual_runtime.zig");
};

pub fn main() void {
    std.debug.print("Hello, world!\n", .{});
}
