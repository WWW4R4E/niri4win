const std = @import("std");

const StdInput = @This();

io: std.Io,
buf: [4096]u8 = undefined,
line: [1024]u8 = undefined,

pub fn init(io: std.Io) StdInput {
    return .{ .io = io };
}

pub fn readLine(s: *StdInput) ![]u8 {
    var reader = std.Io.File.stdin().reader(s.io, s.buf[0..]);
    var result = try reader.interface.takeDelimiterExclusive('\n');
    if (result.len > 0 and result[result.len - 1] == '\r') {
        result = result[0 .. result.len - 1];
    }
    const n = @min(result.len, s.line.len);
    @memcpy(s.line[0..n], result[0..n]);
    return s.line[0..n];
}

pub fn readInt(s: *StdInput, comptime T: type) !T {
    return std.fmt.parseInt(T, try s.readLine(), 10);
}
