const std = @import("std");

const Context = @import("machine/context.zig").Context;
const Stack = @import("machine/stack.zig").Stack;
const Task = @import("../../task/task.zig").Task;

threadlocal var current_coroutine: ?*Coroutine = null;

pub const Coroutine = struct {
    task: Task = undefined,
    stack: Stack = undefined,
    self_context: Context = undefined,
    caller_context: Context = undefined,
    is_completed: bool = false,

    pub fn init(task: Task, allocator: std.mem.Allocator) !Coroutine {
        var result: Coroutine = .{
            .task = task,
            .stack = try Stack.init(16, allocator),
        };
        result.self_context = Context.init(&result.stack, Coroutine.Trampoline);
        return result;
    }

    pub fn deinit(self: *Coroutine) void {
        self.stack.deinit();
    }

    pub fn resumeCoro(self: *Coroutine) void {
        const caller: ?*Coroutine = current_coroutine;
        current_coroutine = self;
        self.caller_context.switchTo(&self.self_context);
        current_coroutine = caller;
    }

    pub fn suspendCoro() void {
        std.debug.assert(current_coroutine != null);
        const coro: *Coroutine = current_coroutine.?;
        coro.self_context.switchTo(&coro.caller_context);
    }

    pub fn current() ?*Coroutine {
        return current_coroutine;
    }

    pub fn isCompleted(self: *const Coroutine) bool {
        return self.is_completed;
    }

    fn Trampoline() noreturn {
        std.debug.assert(current_coroutine != null);
        const coro: *Coroutine = current_coroutine.?;
        coro.task.run();
        coro.is_completed = true;
        suspendCoro();

        unreachable;
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const TaskA = struct {
    pub fn task(self: *TaskA) Task {
        return Task.init(self);
    }

    pub fn run(_: *TaskA) void {
        std.debug.print("2\n", .{});
        Coroutine.suspendCoro();
        std.debug.print("5\n", .{});
    }
};

const TaskB = struct {
    coro: *Coroutine,

    pub fn task(self: *TaskB) Task {
        return Task.init(self);
    }

    pub fn run(self: *TaskB) void {
        std.debug.print("1\n", .{});
        self.coro.resumeCoro();
        Coroutine.suspendCoro();
        std.debug.print("4\n", .{});
        self.coro.resumeCoro();
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(!gpa.detectLeaks()) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var t1: TaskA = .{};
    var coro1 = try Coroutine.init(t1.task(), allocator);
    defer coro1.deinit();

    var t2: TaskB = .{ .coro = &coro1 };
    var coro2 = try Coroutine.init(t2.task(), allocator);
    defer coro2.deinit();

    coro2.resumeCoro();
    std.debug.print("3\n", .{});
    coro2.resumeCoro();
    std.debug.print("6\n", .{});

    try testing.expect(coro1.isCompleted());
    try testing.expect(coro2.isCompleted());
}
