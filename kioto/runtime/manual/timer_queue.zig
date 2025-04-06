const std = @import("std");

const Allocator = std.mem.Allocator;
const ManualClock = @import("manual_clock.zig").ManualClock;
const Order = std.math.Order;
const PriorityQueue = std.PriorityQueue;
const Runnable = @import("../../task/task.zig").Runnable;

const TimedTask = struct {
    handler: Runnable = undefined,
    deadline: ManualClock.TimePoint = undefined,
};

fn lessThan(_: void, a: TimedTask, b: TimedTask) Order {
    return std.math.order(a.deadline, b.deadline);
}

pub const TimerQueue = struct {
    const Queue = PriorityQueue(TimedTask, void, lessThan);
    const Self = @This();
    const TimePoint = ManualClock.TimePoint;

    tasks: Queue = undefined,

    pub fn init(allocator: Allocator) Self {
        return .{
            .tasks = Queue.init(allocator, void),
        };
    }

    pub fn push(self: *Self, handler: Runnable, deadline: TimePoint) !void {
        try self.tasks.add(.{ .handler = handler, .deadline = deadline });
    }
};
