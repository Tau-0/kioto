const builtin = @import("builtin");
const Stack = @import("stack.zig").Stack;

extern fn switchStack(current_stack: *anyopaque, target_stack: *anyopaque) void;

const SwitchContext = switch (builtin.cpu.arch) {
    .x86_64 => switch (builtin.os.tag) {
        .linux => SystemVAMD64ABI,
        else => @compileError("Unsupported OS"),
    },
    else => @compileError("Unsupported platform"),
};

const SystemVAMD64ABI = struct {
    comptime {
        asm (
            \\.global switchStack
            \\switchStack:
            \\  pushq %rbp
            \\  pushq %rbx
            \\  pushq %r12
            \\  pushq %r13
            \\  pushq %r14
            \\  pushq %r15
            \\
            \\  movq %rsp, (%rdi)
            \\  movq (%rsi), %rsp
            \\
            \\  popq %r15
            \\  popq %r14
            \\  popq %r13
            \\  popq %r12
            \\  popq %rbx
            \\  popq %rbp
            \\
            \\  retq
        );
    }
};

pub const Context = struct {
    rsp: *anyopaque = undefined,

    pub fn init(stack: *Stack, trampoline: *Trampoline) Context {}

    pub fn switchTo(self: *Context, target: *Context) void {
        switchStack(&self.rsp, &target.rsp);
    }
};
