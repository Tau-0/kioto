const builtin = @import("builtin");
const Stack = @import("../../runtime/stack.zig").Stack;

// const SwitchContext = switch (builtin.cpu.arch) {
//     .x86_64 => switch (builtin.os.tag) {
//         .linux => SystemVAMD64ABI,
//         else => @compileError("Unsupported OS"),
//     },
//     else => @compileError("Unsupported platform"),
// };

// System V AMD64 ABI
// The calling convention requires
// a top of the stack (%rsp) to be aligned by 16
// before a call and after a ret
comptime {
    asm (
        \\.global switchContext;
        \\.global setupContext;
        \\.type switchContext, @function;
        \\.type setupContext, @function;
        \\
        \\switchContext:
        \\  pushq   %rbp
        \\  pushq   %rbx
        \\  pushq   %r12
        \\  pushq   %r13
        \\  pushq   %r14
        \\  pushq   %r15
        \\
        \\  movq    %rsp, (%rdi)
        \\  movq    (%rsi), %rsp
        \\
        \\  popq    %r15
        \\  popq    %r14
        \\  popq    %r13
        \\  popq    %r12
        \\  popq    %rbx
        \\  popq    %rbp
        \\
        \\  retq
        \\
        \\setupContext:
        \\  movq    %rsp, %rcx
        \\  movq    %rdi, %rsp
        \\  andq    $0xfffffffffffffff0, %rsp
        \\  addq    $8, %rsp
        \\  pushq   %rsi
        \\  pushq   $0
        \\  pushq   $0
        \\  pushq   $0
        \\  pushq   $0
        \\  pushq   $0
        \\  pushq   $0
        \\  movq    %rsp, %rax
        \\  movq    %rcx, %rsp
        \\  retq
    );
}

extern fn switchContext(current_context: **anyopaque, target_context: **anyopaque) void;
extern fn setupContext(stack_top: *anyopaque, trampoline: *const anyopaque) *anyopaque;

pub const Context = struct {
    rsp: *anyopaque = undefined,

    pub fn init(stack: *Stack, trampoline: *const anyopaque) Context {
        return .{
            .rsp = setupContext(&stack.memory[stack.memory.len - 1], trampoline),
        };
    }

    pub fn switchTo(self: *Context, target: *Context) void {
        switchContext(&self.rsp, &target.rsp);
    }
};

////////////////////////////////////////////////////////////////////////////////

const std = @import("std");
const testing = std.testing;

const ManualRuntime = @import("../../runtime/manual/manual_runtime.zig").ManualRuntime;

var context1: Context = undefined;
var context2: Context = undefined;

fn testTrampoline() noreturn {
    std.debug.print("1\n", .{});
    context1.switchTo(&context2);
    std.debug.print("3\n", .{});
    context1.switchTo(&context2);

    unreachable;
}

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var manual: ManualRuntime = .{};
    manual.init(allocator);
    defer manual.deinit();

    const stack: *Stack = try manual.allocateStack();
    defer manual.releaseStack(stack);

    context1 = Context.init(stack, @as(*const anyopaque, testTrampoline));

    context2.switchTo(&context1);
    std.debug.print("2\n", .{});
    context2.switchTo(&context1);
    std.debug.print("4\n", .{});
}
