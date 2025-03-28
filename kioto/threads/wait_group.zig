const std = @import("std");

pub const WaitGroup = struct {
    mutex: std.Thread.Mutex = .{},
    no_work: std.Thread.Condition = .{},
    counter: u64 = 0,
    waiters: u64 = 0,

    pub fn add(self: *WaitGroup, count: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.counter += count;
    }

    pub fn done(self: *WaitGroup) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.counter -= 1;
        if (self.counter == 0 and self.waiters != 0) {
            self.no_work.broadcast();
        }
    }

    pub fn wait(self: *WaitGroup) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.waiters += 1;
        while (self.counter != 0) {
            self.no_work.wait(&self.mutex);
        }
        self.waiters -= 1;
    }
};

////////////////////////////////////////////////////////////////////////////////

const testing = std.testing;

fn threadFunc(wg: *WaitGroup) void {
    std.Thread.sleep(1_000_000_000);
    wg.done();
}

test "basic" {
    var wg: WaitGroup = .{};
    wg.add(2);
    try testing.expect(wg.counter == 2 and wg.waiters == 0);
    var t1 = try std.Thread.spawn(.{}, threadFunc, .{&wg});
    var t2 = try std.Thread.spawn(.{}, threadFunc, .{&wg});
    wg.wait();
    try testing.expect(wg.counter == 0 and wg.waiters == 0);

    t1.join();
    t2.join();
}
