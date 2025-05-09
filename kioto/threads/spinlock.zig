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

const IntrusiveTask = @import("../task/intrusive_task.zig").IntrusiveTask;
const Task = @import("../task/task.zig").Task;
const ThreadPool = @import("../runtime/concurrent/thread_pool.zig").ThreadPool;
const WaitGroup = @import("wait_group.zig").WaitGroup;

const TestRunnable = struct {
    counter: *i64 = undefined,
    spinlock: *Spinlock = undefined,
    wg: *WaitGroup = undefined,
    hook: IntrusiveTask = .{},

    pub fn init(self: *TestRunnable) void {
        self.hook.init(Task.init(self));
    }

    pub fn run(self: *TestRunnable) void {
        for (0..1_000_000) |_| {
            self.spinlock.lock();
            defer self.spinlock.unlock();
            self.counter.* += 1;
        }
        self.wg.done();
    }

    pub fn getHook(self: *TestRunnable) *IntrusiveTask {
        return &self.hook;
    }
};

test "basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();

    var tp: ThreadPool = .{};
    try tp.init(6, allocator);
    defer tp.deinit();

    try tp.start();
    defer tp.stop();

    var counter: i64 = 0;
    var spinlock: Spinlock = .{};
    var wg: WaitGroup = .{};

    var tasks: [6]TestRunnable = undefined;
    for (0..6) |i| {
        tasks[i] = .{ .counter = &counter, .spinlock = &spinlock, .wg = &wg };
        tasks[i].init();
        wg.add(1);
    }

    for (0..6) |i| {
        tp.submit(tasks[i].getHook());
    }

    wg.wait();
    try testing.expect(counter == 6_000_000);
}
