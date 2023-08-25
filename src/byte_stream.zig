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
            _ = bytes;
            _ = self;
        }
    };
}
