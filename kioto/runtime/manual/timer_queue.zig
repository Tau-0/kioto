const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ManualClock = @import("manual_clock.zig").ManualClock;
const Order = std.math.Order;
const PriorityQueue = std.PriorityQueue;
const Runnable = @import("../../task/task.zig").Runnable;

const Context = struct {};

const TimedTask = struct {
    handler: Runnable = undefined,
    deadline: ManualClock.TimePoint = undefined,
};

fn lessThan(_: Context, a: TimedTask, b: TimedTask) Order {
    return std.math.order(a.deadline.microseconds, b.deadline.microseconds);
}

pub const TimerQueue = struct {
    const Queue = PriorityQueue(TimedTask, Context, lessThan);
    const Self = @This();
    const TimePoint = ManualClock.TimePoint;

    tasks: Queue = undefined,

    pub fn init(allocator: Allocator) Self {
        return .{
            .tasks = Queue.init(allocator, .{}),
        };
    }

    pub fn deinit(self: *Self) void {
        self.tasks.deinit();
    }

    pub fn push(self: *Self, handler: Runnable, deadline: TimePoint) !void {
        try self.tasks.add(.{ .handler = handler, .deadline = deadline });
    }

    pub fn isEmpty(self: *const Self) bool {
        return self.tasks.count() == 0;
    }

    pub fn nextDeadline(self: *Self) TimePoint {
        return self.tasks.peek().?.deadline;
    }

    pub fn takeReadyTasks(self: *Self, now: TimePoint, allocator: Allocator) !ArrayList(Runnable) {
        var ready_tasks: ArrayList(Runnable) = ArrayList(Runnable).init(allocator);
        while (!self.isEmpty() and now.microseconds >= self.nextDeadline().microseconds) {
            try ready_tasks.append(self.tasks.remove().handler);
        }
        return ready_tasks;
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const TestRunnable = struct {
    x: i32 = undefined,

    pub fn runnable(self: *TestRunnable) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *TestRunnable) void {
        std.debug.print("{}\n", .{self.x});
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var task1: TestRunnable = .{ .x = 10 };
    var task2: TestRunnable = .{ .x = 20 };
    var queue: TimerQueue = TimerQueue.init(allocator);
    defer queue.deinit();

    queue.push(task1.runnable(), .{ .microseconds = 10 }) catch @panic("TEST FAIL");
    queue.push(task2.runnable(), .{ .microseconds = 20 }) catch @panic("TEST FAIL");

    testing.expect(queue.nextDeadline().microseconds == 10) catch @panic("TEST FAIL");

    {
        const t = queue.takeReadyTasks(.{ .microseconds = 0 }, allocator) catch @panic("TEST FAIL");
        defer t.deinit();

        testing.expect(t.items.len == 0) catch @panic("TEST FAIL");
    }
    {
        const t = queue.takeReadyTasks(.{ .microseconds = 9 }, allocator) catch @panic("TEST FAIL");
        defer t.deinit();

        testing.expect(t.items.len == 0) catch @panic("TEST FAIL");
    }
    {
        const t = queue.takeReadyTasks(.{ .microseconds = 10 }, allocator) catch @panic("TEST FAIL");
        defer t.deinit();

        testing.expect(t.items.len == 1) catch @panic("TEST FAIL");
        testing.expect(queue.nextDeadline().microseconds == 20) catch @panic("TEST FAIL");

        for (t.items) |h| {
            h.run();
        }
    }
    {
        const t = queue.takeReadyTasks(.{ .microseconds = 100 }, allocator) catch @panic("TEST FAIL");
        defer t.deinit();

        testing.expect(t.items.len == 1) catch @panic("TEST FAIL");
        testing.expect(queue.isEmpty()) catch @panic("TEST FAIL");

        for (t.items) |h| {
            h.run();
        }
    }
}
