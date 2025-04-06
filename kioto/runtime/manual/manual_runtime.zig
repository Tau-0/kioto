const std = @import("std");

const Allocator = std.mem.Allocator;
const DoublyLinkedList = std.DoublyLinkedList;
const Runnable = @import("../task/task.zig").Runnable;

pub const ManualRuntime = struct {
    const Queue = DoublyLinkedList(Runnable);
    const Node = Queue.Node;

    tasks: Queue = .{},
    allocator: Allocator = undefined,

    pub fn init(allocator: Allocator) ManualRuntime {
        return .{
            .allocator = allocator,
        };
    }

    pub fn submit(self: *ManualRuntime, runnable: Runnable) !void {
        var node: *Node = try self.allocator.create(Node);
        node.data = runnable;
        self.tasks.append(node);
    }

    pub fn runOne(self: *ManualRuntime) bool {
        var done: bool = false;
        if (!self.isEmpty()) {
            const node: *Node = self.tasks.popFirst().?;
            var runnable: Runnable = node.data;
            self.allocator.destroy(node);
            runnable.run();
            done = true;
        }
        return done;
    }

    pub fn runLimited(self: *ManualRuntime, limit: usize) usize {
        var done: usize = 0;
        while (done < limit and self.runOne()) {
            done += 1;
        }
        return done;
    }

    pub fn runAll(self: *ManualRuntime) usize {
        var done: usize = 0;
        while (self.runOne()) {
            done += 1;
        }
        return done;
    }

    pub fn isEmpty(self: *const ManualRuntime) bool {
        return self.tasks.len == 0;
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const TestRunnable = struct {
    pub fn runnable(self: *TestRunnable) Runnable {
        return Runnable.init(self);
    }

    pub fn run(_: *TestRunnable) void {
        std.debug.print("Hello from thread {}!\n", .{std.Thread.getCurrentId()});
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var manual: ManualRuntime = ManualRuntime.init(allocator);
    var task: TestRunnable = .{};

    try manual.submit(task.runnable());
    try manual.submit(task.runnable());

    testing.expect(manual.tasks.len == 2) catch @panic("TEST FAIL");
    testing.expect(manual.runOne()) catch @panic("TEST FAIL");
    testing.expect(manual.runOne()) catch @panic("TEST FAIL");
}
