const std = @import("std");
const testing = std.testing;

// this should follow the general stream ideas as seen in std.io.

//read()
//reader()
//write()
//writeAssumeCapacity()
//writer()
//writerAssumeCapacity()
// Main difference being that we're providing writers that can either
// grow the backing array, or assume capacity as necessary.
//

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}
