const std = @import("std");
const expect = std.testing.expect;
const kioto = @import("kioto");

test "basic add functionality" {
    try expect(kioto.add(3, 7) == 10);
}

test "always succeeds" {
    try expect(true);
}

// test "always fails" {
//     try expect(false);
// }
