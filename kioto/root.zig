comptime {
    _ = @import("fibers/machine/context.zig");
    _ = @import("fibers/machine/stack.zig");
    _ = @import("runtime/thread_pool.zig");
    _ = @import("task/task.zig");
    _ = @import("threads/blocking_queue.zig");
    _ = @import("threads/wait_group.zig");
}
