const std = @import("std");
const Allocator = std.mem.Allocator;
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

//todo: play around with whether keeping the allocator reference
//      is nicer to use
pub fn ByteStream() type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        buffer: []u8,
        len: usize,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
                .len = 0,
                .buffer = &[_]u8{}, // zero sized []u8 constant
            };
        }

        pub fn initCapacity(allocator: Allocator, capacity: usize) Allocator.Error!Self {
            _ = capacity;
            var self = Self.init(allocator);
            _ = self;
        }

        pub fn ensureCapacity(self: *Self, capacity: usize) Allocator.Error!void {
            if (self.buffer.len >= capacity) {
                return;
            }

            //todo implement
        }
    };
}

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}
