const builtin = @import("builtin");
const Stack = @import("stack.zig").Stack;

const SwitchContext = switch (builtin.cpu.arch) {
    .x86_64 => switch (builtin.os.tag) {
        .linux => SystemVAMD64ABI,
        else => @compileError("Unsupported OS"),
    },
    else => @compileError("Unsupported platform"),
};

extern fn switchContext(current_context: **anyopaque, target_context: **anyopaque) void;
extern fn setupContext(stack_top: *anyopaque, trampoline: *anyopaque) *anyopaque;

// The calling convention requires a top of the stack (%rsp) to be aligned by 16 before a call and after a ret
const SystemVAMD64ABI = struct {
    comptime {
        asm (
            \\.type switchContext, @function
            \\.type setupContext, @function
            \\.global switchContext
            \\.global setupContext
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
            \\  andq    $0xfffffffffffffff0, $rsp
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
};

pub const Context = struct {
    rsp: *anyopaque = undefined,

    pub fn init(stack: *Stack, trampoline: *anyopaque) Context {
        return .{
            .rsp = setupContext(stack.memory.ptr + stack.memory.len - 1, trampoline),
        };
    }

    pub fn switchTo(self: *Context, target: *Context) void {
        switchContext(&self.rsp, &target.rsp);
    }
};
