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
            self.ensureCapacity(capacity);
        }

        pub fn ensureCapacity(self: *Self, capacity: usize) Allocator.Error!void {
            if (self.buffer.len >= capacity) {
                return;
            }

            const tmp = self.buffer;

            if (!self.allocator.resize(tmp, capacity)) {
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
        pub const WriteError = error{};

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
            const sz = self.buffer.len + bytes.len;
            if (self.buffer.len < sz) {
                //todo: byte_stream is meant for creating and reading network
                //      messages, so is it necessary to put any more
                //      thought in to the grow factor?
                self.ensureCapacity(sz);
            }

            try self.writeAssumeCapacity(bytes);
        }

        pub fn writeAssumeCapacity(self: *Self, bytes: []const u8) WriteError!usize {
            std.debug.assert(self.buffer.len >= self.pos + bytes.len);

            @memcpy(self.buffer[self.pos..][0..bytes.len], bytes[0..]);

            self.pos += bytes.len;

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
            _ = pos;
            _ = self;
            //todo: implement
        }

        pub fn seekBy(self: *Self, pos: i64) SeekError!void {
            _ = pos;
            _ = self;
            //todo: implement
        }

        pub fn getEndPos(self: *Self) GetSeekPosError!u64 {
            return self.buffer.len;
        }

        pub fn getPos(self: *Self) GetSeekPosError!u64 {
            return self.pos;
        }
    };
}
