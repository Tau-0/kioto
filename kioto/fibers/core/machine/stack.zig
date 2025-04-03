const std = @import("std");

const page_size: usize = 4096;

pub const Stack = struct {
    memory: []align(page_size) u8 = undefined,
    allocator: std.mem.Allocator = undefined,

    pub fn init(pages: usize, allocator: std.mem.Allocator) !Stack {
        return .{
            .memory = try allocator.alignedAlloc(u8, page_size, pages * page_size),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Stack) void {
        self.allocator.free(self.memory);
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

test "basic" {
    const pages: usize = 2;
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();
    var stack: Stack = try Stack.init(pages, allocator);
    defer testing.expect(!gpa.detectLeaks()) catch unreachable;
    defer stack.deinit();

    try testing.expect(stack.memory.len == pages * page_size);
    try testing.expect(@typeInfo(@TypeOf(stack.memory.ptr)).pointer.alignment == page_size);
    // No gap (correct alignment)
    try testing.expect(&stack.memory[1] - &stack.memory[0] == 1);
}
