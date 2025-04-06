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
