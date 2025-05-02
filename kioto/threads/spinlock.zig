const std = @import("std");

const Atomic = std.atomic.Value;
const Backoff = @import("backoff.zig").Backoff;

pub const Spinlock = struct {
    locked: Atomic(bool) = .{ .raw = false },

    pub fn lock(self: *Spinlock) void {
        var backoff: Backoff = .{};
        while (self.locked.swap(true, .acq_rel)) {
            while (self.locked.load(.acquire)) {
                backoff.spin();
            }
        }
    }

    pub fn tryLock(self: *Spinlock) bool {
        return !self.locked.swap(true, .acq_rel);
    }

    pub fn unlock(self: *Spinlock) void {
        self.locked.store(false, .release);
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

const Runnable = @import("../task/task.zig").Runnable;
const ThreadPool = @import("../runtime/thread_pool.zig").ThreadPool;
const WaitGroup = @import("wait_group.zig").WaitGroup;

const Task = struct {
    counter: *i64 = undefined,
    spinlock: *Spinlock = undefined,
    wg: *WaitGroup = undefined,

    pub fn runnable(self: *Task) Runnable {
        return Runnable.init(self);
    }

    pub fn run(self: *Task) void {
        for (0..1_000_000) |_| {
            self.spinlock.lock();
            defer self.spinlock.unlock();
            self.counter.* += 1;
        }
        self.wg.done();
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();

    var tp: ThreadPool = try ThreadPool.init(6, allocator);
    try tp.start();
    defer tp.deinit();
    defer tp.stop();

    var counter: i64 = 0;
    var spinlock: Spinlock = .{};
    var wg: WaitGroup = .{};
    var task: Task = .{ .counter = &counter, .spinlock = &spinlock, .wg = &wg };
    const runnable: Runnable = task.runnable();
    wg.add(6);

    for (0..6) |_| {
        try tp.submit(runnable);
    }

    wg.wait();
    testing.expect(counter == 6_000_000) catch @panic("TEST FAIL");
}
