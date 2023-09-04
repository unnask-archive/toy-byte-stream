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

        capacity: usize,
        pos: usize,
        bytes: []u8,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
                .capacity = 0,
                .pos = 0,
                .bytes = &[_]u8{}, // zero sized []u8 constant
            };
        }

        pub fn initCapacity(allocator: Allocator, capacity: usize) Allocator.Error!Self {
            var self = Self.init(allocator);
            try self.ensureCapacity(capacity);

            return self;
        }

        fn backingSlice(self: *Self) []u8 {
            return self.bytes.ptr[0..self.capacity];
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.backingSlice());
            self.capacity = 0;
            self.pos = 0;
        }

        pub fn ensureCapacity(self: *Self, new_capacity: usize) Allocator.Error!void {
            if (self.capacity >= new_capacity) {
                return;
            }

            var tmp = self.backingSlice();

            if (self.allocator.resize(tmp, new_capacity)) {
                self.capacity = new_capacity;
            } else {
                const new = try self.allocator.alloc(u8, new_capacity);

                //todo: measure:
                //    zig doc says to not use memcpy for safety reasons,
                //    and that the compiler should convert this to
                //    @memcpy anyway. But maybe confirm

                //@memcpy(new[0..self.buffer.len], self.buffer);
                for (self.bytes[0..], 0..) |e, i| {
                    new[i] = e;
                }
                self.allocator.free(tmp);
                self.bytes.ptr = new.ptr;
                self.capacity = new_capacity;
            }
        }

        //implements std.io.Reader API
        //implements std.io.Writer API
        pub const ReadError = error{};
        pub const WriteError = error{allocFailed};

        //todo: Maybe make a new reader and writer?
        //      For now, this is fine
        pub const Reader = io.Reader(*Self, ReadError, read);
        pub const AppendingWriter = io.Writer(*Self, WriteError, appendingWrite);
        pub const AppendingWriterAssumeCapacity = io.writer(*Self, WriteError, appendingWriteAssumeCapacity);
        pub const SeekableWriter = io.Writer(*Self, WriteError, seekableWrite);
        pub const SeekableWriterAssumeCapacity = io.Writer(*Self, WriteError, seekableWriteAssumeCapacity);
        pub const Writer = AppendingWriter;
        pub const WriterAssumeCapacity = AppendingWriterAssumeCapacity;

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }

        pub fn appendingWriter(self: *Self) AppendingWriter {
            return .{ .context = self };
        }

        pub fn appendingWriterAssumeCapacity(self: *Self) AppendingWriterAssumeCapacity {
            return .{ .context = self };
        }

        pub fn seekableWriter(self: *Self) SeekableWriter {
            return .{ .context = self };
        }

        pub fn seekableWriterAssumeCapacity(self: *Self) SeekableWriterAssumeCapacity {
            return .{ .context = self };
        }

        pub const writer = appendingWriter;
        pub const writerAssumeCapacity = appendingWriterAssumeCapacity;

        pub fn read(self: *Self, dest: []u8) ReadError!usize {
            const sz = @min(dest.len, self.bytes.len - self.pos);
            const end = self.pos + sz;

            //@memcpy(dest[0..sz], self.buffer[self.pos..end]);
            for (self.bytes[self.pos..end], 0..) |e, i| {
                dest[i] = e;
            }
            self.pos = end;

            return sz;
        }

        pub fn appendingWrite(self: *Self, bytes: []const u8) WriteError!usize {
            const sz = self.bytes.len + bytes.len;
            if (self.capacity < sz) {
                //todo: probably a better way to do this error
                self.ensureCapacity(sz) catch return WriteError.allocFailed;
            }

            return self.appendingWriteAssumeCapacity(bytes);
        }

        pub fn appendingWriteAssumeCapacity(self: *Self, bytes: []const u8) WriteError!usize {
            std.debug.assert(self.capacity >= self.bytes.len + bytes.len);

            const end = self.bytes.len + bytes.len;
            var tmp_dest = self.bytes.ptr[0..end][self.bytes.len..];
            @memcpy(tmp_dest[0..], bytes[0..]);

            self.bytes.len = end;

            return bytes.len;
        }

        pub const write = appendingWrite;
        pub const writeAssumeCapacity = appendingWriteAssumeCapacity;

        pub fn seekableWrite(self: *Self, bytes: []const u8) WriteError!usize {
            const sz = self.pos + bytes.len;
            if (self.capacity < sz) {
                //todo: byte_stream is meant for creating and reading network
                //      messages, so is it necessary to put any more
                //      thought in to the grow factor?
                //todo: probably a better way to do this error
                self.ensureCapacity(sz) catch return WriteError.allocFailed;
            }

            return try self.seekableWriteAssumeCapacity(bytes);
        }

        pub fn seekableWriteAssumeCapacity(self: *Self, bytes: []const u8) WriteError!usize {
            std.debug.assert(self.capacity >= self.pos + bytes.len);

            const end = self.pos + bytes.len;
            var tmp_dest = self.bytes.ptr[0..end][self.pos..];
            @memcpy(tmp_dest[0..], bytes[0..]);

            self.pos = end;
            self.bytes.len = @max(self.bytes.len, end);

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
                @min(self.bytes.len, p);
            } else {
                self.bytes.len;
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
                @min(self.bytes.len, tmp);
            };
        }

        pub fn getEndPos(self: *Self) GetSeekPosError!u64 {
            return self.bytes.len;
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

    try testing.expectEqual(stream.capacity, 0);
    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.bytes.len, 0);
}

test "byte-stream/initCapacity" {
    var stream = try ByteStream().initCapacity(std.testing.allocator, 123);
    defer stream.deinit();

    try testing.expectEqual(stream.capacity, 123);
    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.bytes.len, 0);
}

test "byte-stream/ensureCapacity" {
    var stream = ByteStream().init(std.testing.allocator);
    defer stream.deinit();

    try testing.expectEqual(stream.capacity, 0);
    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.bytes.len, 0);

    {
        try stream.ensureCapacity(250);

        try testing.expectEqual(stream.capacity, 250);
        try testing.expectEqual(stream.pos, 0);
        try testing.expectEqual(stream.bytes.len, 0);
    }

    //trying to guarantee an in place resize for the test
    {
        try stream.ensureCapacity(251);

        try testing.expectEqual(stream.capacity, 251);
        try testing.expectEqual(stream.pos, 0);
        try testing.expectEqual(stream.bytes.len, 0);
    }
}

test "byte-stream/appendingWrite with space" {
    var stream = try ByteStream().initCapacity(std.testing.allocator, 50);
    defer stream.deinit();

    var bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7 };

    var written = try stream.appendingWrite(&bytes);

    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.capacity, 50);
    try testing.expectEqual(written, 7);
    try testing.expectEqual(stream.bytes.len, 7);
    try testing.expectEqualSlices(u8, &bytes, stream.bytes);
}

test "byte-stream/appendingWrite multiple" {
    var stream = try ByteStream().initCapacity(std.testing.allocator, 50);
    defer stream.deinit();

    var bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7 };

    var written = try stream.appendingWrite(&bytes);

    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.capacity, 50);
    try testing.expectEqual(written, 7);
    try testing.expectEqual(stream.bytes.len, 7);
    try testing.expectEqualSlices(u8, &bytes, stream.bytes);

    var start = stream.bytes.len;
    var bytes2 = [_]u8{ 20, 21, 22, 23, 24, 25 };
    written = try stream.appendingWrite(&bytes2);

    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.capacity, 50);
    try testing.expectEqual(written, 6);
    try testing.expectEqual(stream.bytes.len, 13);
    try testing.expectEqualSlices(u8, &bytes2, stream.bytes[start..]);
}

test "byte-stream/appendingWrite force grow" {
    var stream = ByteStream().init(std.testing.allocator);
    defer stream.deinit();

    var bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7 };

    var written = try stream.appendingWrite(&bytes);

    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.capacity, 7);
    try testing.expectEqual(stream.bytes.len, 7);
    try testing.expectEqual(written, 7);
    try testing.expectEqualSlices(u8, &bytes, stream.bytes);

    var start = stream.bytes.len;
    var bytes2 = [_]u8{ 20, 21, 22, 23, 24, 25 };
    written = try stream.appendingWrite(&bytes2);

    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.capacity, 13);
    try testing.expectEqual(stream.bytes.len, 13);
    try testing.expectEqual(written, 6);
    try testing.expectEqualSlices(u8, &bytes2, stream.bytes[start..]);
}

test "byte-stream/appendingWriteAssumeCapacity with space" {
    var stream = try ByteStream().initCapacity(std.testing.allocator, 50);
    defer stream.deinit();

    var bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7 };

    var written = try stream.appendingWriteAssumeCapacity(&bytes);

    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.capacity, 50);
    try testing.expectEqual(written, 7);
    try testing.expectEqual(stream.bytes.len, 7);
    try testing.expectEqualSlices(u8, &bytes, stream.bytes);

    var start = stream.bytes.len;
    var bytes2 = [_]u8{ 20, 21, 22, 23, 24, 25 };
    written = try stream.appendingWriteAssumeCapacity(&bytes2);

    try testing.expectEqual(stream.pos, 0);
    try testing.expectEqual(stream.capacity, 50);
    try testing.expectEqual(written, 6);
    try testing.expectEqual(stream.bytes.len, 13);
    try testing.expectEqualSlices(u8, &bytes2, stream.bytes[start..]);
}

test "byte-stream/appendingWriteAssumeCapacity over space" {
    var stream = ByteStream().init(std.testing.allocator);
    defer stream.deinit();

    var bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    _ = bytes;

    //todo: implement an actual test once we can test for panics
    // Looks like there's no way - yet - to test for panics
    //testing.expectPanic(try stream.writeAssumeCapacity(&bytes));
}

//todo seekable writer tests

test "byte-stream/read" {
    var stream = try ByteStream().initCapacity(std.testing.allocator, 50);
    defer stream.deinit();

    const bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    _ = try stream.appendingWrite(&bytes);

    var dest: [10]u8 = undefined;
    var read = stream.read(&dest);

    try testing.expectEqual(read, 10);
    try testing.expectEqualSlices(u8, &bytes, &dest);
    try testing.expectEqual(stream.pos, 10);
    try testing.expectEqual(stream.capacity, 50);
}

test "byte-stream/read multiple" {
    var stream = try ByteStream().initCapacity(std.testing.allocator, 50);
    defer stream.deinit();

    const bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    _ = try stream.appendingWrite(&bytes);

    var dest1: [5]u8 = undefined;
    var dest2: [4]u8 = undefined;

    var read1 = stream.read(&dest1);
    var read2 = stream.read(&dest2);

    try testing.expectEqual(read1, 5);
    try testing.expectEqualSlices(u8, &dest1, bytes[0..5]);

    try testing.expectEqual(read2, 4);
    try testing.expectEqualSlices(u8, &dest2, bytes[5..9]);

    try testing.expectEqual(stream.pos, 9);
    try testing.expectEqual(stream.capacity, 50);
    try testing.expectEqual(stream.bytes.len, 10);
}

test "byte-stream/seekTo happy path" {
    var stream = try ByteStream().initCapacity(std.testing.allocator, 50);
    defer stream.deinit();

    const bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    _ = try stream.appendingWrite(&bytes);

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
