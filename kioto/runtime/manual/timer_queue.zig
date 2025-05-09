const std = @import("std");

const time = @import("../time.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ManualClock = @import("manual_clock.zig").ManualClock;
const Order = std.math.Order;
const PriorityQueue = std.PriorityQueue;
const IntrusiveTask = @import("../../task/intrusive_task.zig").IntrusiveTask;

const Context = struct {};

const TimedTask = struct {
    handler: *IntrusiveTask = undefined,
    deadline: time.TimePoint = undefined,
};

fn lessThan(_: Context, a: TimedTask, b: TimedTask) Order {
    return std.math.order(a.deadline.microseconds, b.deadline.microseconds);
}

pub const TimerQueue = struct {
    const Self = @This();

    const Queue = PriorityQueue(TimedTask, Context, lessThan);
    const TimePoint = time.TimePoint;

    tasks: Queue = undefined,

    pub fn init(allocator: Allocator) Self {
        return .{
            .tasks = Queue.init(allocator, .{}),
        };
    }

    pub fn deinit(self: *Self) void {
        self.tasks.deinit();
    }

    pub fn push(self: *Self, handler: *IntrusiveTask, deadline: TimePoint) !void {
        try self.tasks.add(.{ .handler = handler, .deadline = deadline });
    }

    pub fn isEmpty(self: *const Self) bool {
        return self.tasks.count() == 0;
    }

    pub fn nextDeadline(self: *Self) TimePoint {
        return self.tasks.peek().?.deadline;
    }

    pub fn takeReadyTasks(self: *Self, now: TimePoint, allocator: Allocator) !ArrayList(*IntrusiveTask) {
        var ready_tasks = ArrayList(*IntrusiveTask).init(allocator);
        while (!self.isEmpty() and now.microseconds >= self.nextDeadline().microseconds) {
            try ready_tasks.append(self.tasks.remove().handler);
        }
        return ready_tasks;
    }
};

////////////////////////////////////////////////////////////////////////////////

const Task = @import("../../task/task.zig").Task;

const testing = std.testing;

const TestRunnable = struct {
    data: *u8 = undefined,
    hook: IntrusiveTask = .{},

    pub fn init(self: *TestRunnable) void {
        self.hook.init(Task.init(self));
    }

    pub fn run(self: *TestRunnable) void {
        self.data.* += 1;
    }

    pub fn getHook(self: *TestRunnable) *IntrusiveTask {
        return &self.hook;
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer testing.expect(gpa.deinit() == .ok) catch @panic("TEST FAIL");
    const allocator = gpa.allocator();

    var data: u8 = 0;
    var task1: TestRunnable = .{ .data = &data };
    var task2: TestRunnable = .{ .data = &data };
    var task3: TestRunnable = .{ .data = &data };

    task1.init();
    task2.init();
    task3.init();

    var queue: TimerQueue = TimerQueue.init(allocator);
    defer queue.deinit();

    try queue.push(task1.getHook(), .{ .microseconds = 10 });
    try queue.push(task2.getHook(), .{ .microseconds = 20 });
    try queue.push(task3.getHook(), .{ .microseconds = 20 });

    try testing.expect(queue.nextDeadline().microseconds == 10);

    {
        const t = try queue.takeReadyTasks(.{ .microseconds = 0 }, allocator);
        defer t.deinit();

        try testing.expect(t.items.len == 0);
    }
    {
        const t = try queue.takeReadyTasks(.{ .microseconds = 9 }, allocator);
        defer t.deinit();

        try testing.expect(t.items.len == 0);
    }
    {
        const t = try queue.takeReadyTasks(.{ .microseconds = 10 }, allocator);
        defer t.deinit();

        try testing.expect(t.items.len == 1);
        try testing.expect(queue.nextDeadline().microseconds == 20);

        try testing.expect(data == 0);
        for (t.items) |h| {
            h.run();
        }
        try testing.expect(data == 1);
    }
    {
        const t = try queue.takeReadyTasks(.{ .microseconds = 100 }, allocator);
        defer t.deinit();

        try testing.expect(t.items.len == 2);
        try testing.expect(queue.isEmpty());

        try testing.expect(data == 1);
        for (t.items) |h| {
            h.run();
        }
        try testing.expect(data == 3);
    }
}
