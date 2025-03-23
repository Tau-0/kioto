const std = @import("std");

const Task = *const fn () void;

threadlocal var current_coroutine: ?*Coroutine = null;

pub const Coroutine = struct {
    task: Task,
    stack: Stack,
    context: ExecutionContext,
    invoker_context: ExecutionContext,
    is_completed: bool = false,

    pub fn init(self: *Coroutine) void {}

    pub fn resumeCoro(self: *Coroutine) void {}

    pub fn suspendCoro() void {}

    pub fn isCompleted(self: *Coroutine) bool {}
};
