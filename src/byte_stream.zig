const std = @import("std");
const io = std.io;
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

        //Interestingly, ArrayList stores a variable "capacity", and then updates
        // the buffer slices len member to track the end of the "size".
        //
        //Reasoning appears to be Generally nicer user API for the buffer
        //
        //This has some consequences, like having to slightly awkward reslice
        //the pointer when needing to grab more memory above capacity, or free.
        //
        //todo: I should probably spend some time changing the code to work the same way.
        len: usize,
        pos: usize,
        buffer: []u8,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
                .len = 0,
                .pos = 0,
                .buffer = &[_]u8{}, // zero sized []u8 constant
            };
        }

        pub fn initCapacity(allocator: Allocator, capacity: usize) Allocator.Error!Self {
            var self = Self.init(allocator);
            try self.ensureCapacity(capacity);

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.len = 0;
            self.pos = 0;
            self.allocator.free(self.buffer);
        }

        pub fn ensureCapacity(self: *Self, capacity: usize) Allocator.Error!void {
            if (self.buffer.len >= capacity) {
                return;
            }

            const tmp = self.buffer;

            if (self.allocator.resize(tmp, capacity)) {
                self.buffer.len = capacity;
            } else {
                const new = try self.allocator.alloc(u8, capacity);

                //todo: measure:
                //    zig doc says to not use memcpy for safety reasons,
                //    and that the compiler should convert this to
                //    @memcpy anyway. But maybe confirm

                //@memcpy(new[0..self.buffer.len], self.buffer);
                for (self.buffer[0..], 0..) |e, i| {
                    new[i] = e;
                }
                self.allocator.free(tmp);
                self.buffer = new;
            }
        }

        //implements std.io.Reader API
        //implements std.io.Writer API
        pub const ReadError = error{};
        pub const WriteError = error{allocFailed};

        //todo: Maybe make a new reader and writer?
        //      For now, this is fine
        pub const Reader = io.Reader(*Self, ReadError, read);
        pub const Writer = io.Writer(*Self, WriteError, write);
        pub const WriterAssumeCapacity = io.writer(*Self, WriteError, writeAssumeCapacity);

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        pub fn writerAssumeCapacity(self: *Self) WriterAssumeCapacity {
            return .{ .context = self };
        }

        pub fn read(self: *Self, dest: []u8) ReadError!usize {
            const sz = @min(dest.len, self.len - self.pos);
            const end = self.pos + sz;

            //@memcpy(dest[0..sz], self.buffer[self.pos..end]);
            for (self.buffer[self.pos..end], 0..) |e, i| {
                dest[i] = e;
            }
            self.pos = end;

            return sz;
        }

        pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
            const sz = self.len + bytes.len;
            if (self.buffer.len < sz) {
                //todo: byte_stream is meant for creating and reading network
                //      messages, so is it necessary to put any more
                //      thought in to the grow factor?
                self.ensureCapacity(sz) catch return WriteError.allocFailed;
            }

            return try self.writeAssumeCapacity(bytes);
        }

        pub fn writeAssumeCapacity(self: *Self, bytes: []const u8) WriteError!usize {
            std.debug.assert(self.buffer.len >= self.len + bytes.len);

            @memcpy(self.buffer[self.len..][0..bytes.len], bytes[0..]);

            self.len += bytes.len;

            return bytes.len;
        }

        // implements std.io.SeekableStream api
        pub const SeekError = error{};
        pub const GetSeekPosError = error{};

        pub const SeekableStream = io.SeekableStream(*Self, SeekError, GetSeekPosError, seekTo, seekBy, getPos, getEndPos);

        pub fn seekableStream(self: *Self) SeekableStream {
            return .{ .context = self };
        }

        pub fn seekTo(self: *Self, pos: u64) SeekError!void {
            self.pos = if (std.math.cast(usize, pos)) |p| {
                @min(self.len, p);
            } else {
                self.len;
            };
        }

        pub fn seekBy(self: *Self, amount: i64) SeekError!void {
            // annoyingly, i64 doesn't platform well

            self.pos = if (amount < 0) {
                //the std.math functions nicely tell us when a cast fails,
                // whereas the builtins will cause UB when a number doesn't fit
                const abs = std.math.cast(usize, std.math.absCast(amount)) orelse std.math.maxInt(usize);
                self.pos -| abs;
            } else {
                const cast = std.math.cast(usize, amount) orelse std.math.maxInt(usize);
                const tmp = cast +| self.pos;
                @min(self.len, tmp);
            };
        }

        pub fn getEndPos(self: *Self) GetSeekPosError!u64 {
            return self.len;
        }

        pub fn getPos(self: *Self) GetSeekPosError!u64 {
            return self.pos;
        }
    };
}

//tests
test "byte-stream/init" {
    var stream = ByteStream().init(std.testing.allocator);
    defer stream.deinit();

    try testing.expectEqual(stream.len, 0);
    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.buffer.len, 0);
}

test "byte-stream/initCapacity" {
    var stream = try ByteStream().initCapacity(std.testing.allocator, 123);
    defer stream.deinit();

    try testing.expectEqual(stream.len, 0);
    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.buffer.len, 123);
}

test "byte-stream/ensureCapacity" {
    var stream = ByteStream().init(std.testing.allocator);
    defer stream.deinit();

    try testing.expectEqual(stream.len, 0);
    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.buffer.len, 0);

    {
        try stream.ensureCapacity(250);

        try testing.expectEqual(stream.len, 0);
        try testing.expectEqual(stream.pos, 0);
        try testing.expectEqual(stream.buffer.len, 250);
    }

    //trying to guarantee an in place resize for the test
    {
        try stream.ensureCapacity(251);

        try testing.expectEqual(stream.len, 0);
        try testing.expectEqual(stream.pos, 0);
        try testing.expectEqual(stream.buffer.len, 251);
    }
}

test "byte-stream/write with space" {
    var stream = try ByteStream().initCapacity(std.testing.allocator, 50);
    defer stream.deinit();

    var bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7 };

    var written = try stream.write(&bytes);

    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.len, 7);
    try testing.expectEqual(written, 7);
    try testing.expectEqual(stream.buffer.len, 50);
    try testing.expectEqualSlices(u8, &bytes, stream.buffer[0..stream.len]);
}

test "byte-stream/write multiple" {
    var stream = try ByteStream().initCapacity(std.testing.allocator, 50);
    defer stream.deinit();

    var bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7 };

    var written = try stream.write(&bytes);

    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.len, 7);
    try testing.expectEqual(written, 7);
    try testing.expectEqual(stream.buffer.len, 50);
    try testing.expectEqualSlices(u8, &bytes, stream.buffer[0..stream.len]);

    var start = stream.len;
    var bytes2 = [_]u8{ 20, 21, 22, 23, 24, 25 };
    written = try stream.write(&bytes2);

    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.len, 13);
    try testing.expectEqual(written, 6);
    try testing.expectEqual(stream.buffer.len, 50);
    try testing.expectEqualSlices(u8, &bytes2, stream.buffer[start..stream.len]);
}

test "byte-stream/write force grow" {
    var stream = ByteStream().init(std.testing.allocator);
    defer stream.deinit();

    var bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7 };

    var written = try stream.write(&bytes);

    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.len, 7);
    try testing.expectEqual(stream.buffer.len, 7);
    try testing.expectEqual(written, 7);
    try testing.expectEqualSlices(u8, &bytes, stream.buffer[0..stream.len]);

    var start = stream.len;
    var bytes2 = [_]u8{ 20, 21, 22, 23, 24, 25 };
    written = try stream.write(&bytes2);

    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.len, 13);
    try testing.expectEqual(stream.buffer.len, 13);
    try testing.expectEqual(written, 6);
    try testing.expectEqualSlices(u8, &bytes2, stream.buffer[start..stream.len]);
}

test "byte-stream/writeAssumeCapacity with space" {
    var stream = try ByteStream().initCapacity(std.testing.allocator, 50);
    defer stream.deinit();

    var bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7 };

    var written = try stream.writeAssumeCapacity(&bytes);

    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.len, 7);
    try testing.expectEqual(written, 7);
    try testing.expectEqual(stream.buffer.len, 50);
    try testing.expectEqualSlices(u8, &bytes, stream.buffer[0..stream.len]);

    var start = stream.len;
    var bytes2 = [_]u8{ 20, 21, 22, 23, 24, 25 };
    written = try stream.writeAssumeCapacity(&bytes2);

    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.len, 13);
    try testing.expectEqual(written, 6);
    try testing.expectEqual(stream.buffer.len, 50);
    try testing.expectEqualSlices(u8, &bytes2, stream.buffer[start..stream.len]);
}

test "byte-stream/writeAssumeCapacity over space" {
    var stream = ByteStream().init(std.testing.allocator);
    defer stream.deinit();

    var bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    _ = bytes;

    //todo: implement an actual test once we can test for panics
    // Looks like there's no way - yet - to test for panics
    //testing.expectPanic(try stream.writeAssumeCapacity(&bytes));
}

test "byte-stream/read" {
    var stream = try ByteStream().initCapacity(std.testing.allocator, 50);
    defer stream.deinit();

    const bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    _ = try stream.write(&bytes);

    var dest: [10]u8 = undefined;
    var read = stream.read(&dest);

    try testing.expectEqual(read, 10);
    try testing.expectEqualSlices(u8, &bytes, &dest);
    try testing.expectEqual(stream.pos, 10);
    try testing.expectEqual(stream.len, 10);
}

test "byte-stream/read multiple" {
    var stream = try ByteStream().initCapacity(std.testing.allocator, 50);
    defer stream.deinit();

    const bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    _ = try stream.write(&bytes);

    var dest1: [5]u8 = undefined;
    var dest2: [4]u8 = undefined;

    var read1 = stream.read(&dest1);
    var read2 = stream.read(&dest2);

    try testing.expectEqual(read1, 5);
    try testing.expectEqualSlices(u8, &dest1, bytes[0..5]);

    try testing.expectEqual(read2, 4);
    try testing.expectEqualSlices(u8, &dest2, bytes[5..9]);

    try testing.expectEqual(stream.pos, 9);
    try testing.expectEqual(stream.len, 10);
    try testing.expectEqual(stream.buffer.len, 50);
}

test "byte-stream/seekTo happy path" {
    var stream = ByteStream().initCapacity(std.testing.allocator, 50);
    defer stream.deinit();

    const bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    _ = try stream.write(&bytes);

    //Now that I write this test, I'm not sure how I want for pos to actually behave
    // on "write".
    //My initial thought was that write would always append.
    //Now I am considering that perhaps write should advance pos for a few reasons:
    //    -It kinda makes sense to be able to rewrite parts of the buffer.
    //    -It appears to be how fixed_buffer_stream works, and I should be consistent
}

test "byte-stream/seekTo no written bytes" {}

test "byte-stream/seekTo zero length buffer" {}

test "byte-stream/seekTo past end" {}

//test "byte-stream/seekBy" {}

//test "byte-stream/getEndPos" {}

//test "byte-stream/getPos" {}
