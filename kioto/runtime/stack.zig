const std = @import("std");

const Allocator = std.mem.Allocator;
const IntrusiveList = @import("../containers/intrusive_list.zig").IntrusiveList;
const Spinlock = @import("../threads/spinlock.zig").Spinlock;

const Pool = IntrusiveList(Stack);
const Node = Pool.Node;

pub const Stack = struct {
    const page_size: usize = 4096;
    const stack_pages: usize = 16;

    memory: [page_size * stack_pages]u8 align(page_size) = undefined,
    node: Node = undefined,

    fn init(self: *Stack) void {
        self.node = .{};
    }

    fn getNode(self: *Stack) *Node {
        return &self.node;
    }
};

pub const StackPool = struct {
    const Self = @This();

    pool: Pool = undefined,
    guard: Spinlock = undefined,
    size: usize = undefined,
    capacity: usize = undefined,
    allocator: Allocator = undefined,

    pub fn init(self: *Self, capacity: usize, allocator: Allocator) void {
        self.pool = .{};
        self.pool.init();
        self.guard = .{};
        self.size = 0;
        self.capacity = capacity;
        self.allocator = allocator;
    }

    pub fn deinit(self: *Self) void {
        while (self.pool.nonEmpty()) {
            const stack: *Stack = self.pool.popFrontUnsafe();
            self.allocator.destroy(stack);
        }
    }

    pub fn allocate(self: *Self) Allocator.Error!*Stack {
        {
            self.guard.lock();
            defer self.guard.unlock();
            if (self.pool.nonEmpty()) {
                return self.takeFromPool();
            }
        }
        return self.allocateNewStack();
    }

    pub fn release(self: *Self, stack: *Stack) void {
        {
            self.guard.lock();
            defer self.guard.unlock();
            if (self.size < self.capacity) {
                self.pushToPool(stack);
                return;
            }
        }

        self.allocator.destroy(stack);
    }

    fn allocateNewStack(self: *Self) !*Stack {
        var stack: *Stack = try self.allocator.create(Stack);
        stack.init();
        return stack;
    }

    // With lock
    fn takeFromPool(self: *Self) *Stack {
        std.debug.assert(self.pool.nonEmpty());
        const stack: *Stack = self.pool.popFrontUnsafe();
        self.size -= 1;
        return stack;
    }

    // With lock
    fn pushToPool(self: *Self, stack: *Stack) void {
        self.pool.pushBack(stack.getNode());
        self.size += 1;
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    const stack_limit: usize = 4096;
    var stack_pool: StackPool = .{};
    stack_pool.init(stack_limit, allocator);
    defer stack_pool.deinit();

    var stack: *Stack = try stack_pool.allocate();
    defer stack_pool.release(stack);

    try testing.expect(stack.memory.len == Stack.page_size * Stack.stack_pages);
    try testing.expect(@alignOf(Stack) == Stack.page_size);
    // No gap (correct alignment)
    try testing.expect(&stack.memory[1] - &stack.memory[0] == 1);
}
