const builtin = @import("builtin");

extern fn switchStack(from_stack: *u64, to_stack: *u64) void;

const StackContext = switch (builtin.cpu.arch) {
    .x86_64 => switch (builtin.os.tag) {
        .linux => SystemVAMD64ABI,
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

pub const ExecutionContext = struct {
    rsp: *?usize = null,

    pub fn init(stack: *Stack, trampoline: *Trampoline) void {}

    pub fn switchTo(self: *ExecutionContext, target: *ExecutionContext) void {
        switchStack(&self.rsp, &target.rsp);
    }

    pub fn stackPointer(self: *ExecutionContext) *?usize {
        return self.rsp;
    }
};
