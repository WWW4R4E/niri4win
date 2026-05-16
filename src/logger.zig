const std = @import("std");
const niri4win = @import("root").niri4win;
const config = niri4win.config;

pub fn niriLogFn(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const scope_str = @tagName(scope);
    if (config.isModuleBanned(scope_str)) return;

    var buf: [64]u8 = undefined;
    const stderr = std.debug.lockStderr(&buf).terminal();
    defer std.debug.unlockStderr();

    // 时间戳 [HH:MM:SS]
    const ms_since_midnight = std.time.milliTimestamp() % 86400000;
    const hours = @as(u32, @intCast(ms_since_midnight / 3600000));
    const mins = @as(u32, @intCast((ms_since_midnight % 3600000) / 60000));
    const secs = @as(u32, @intCast((ms_since_midnight % 60000) / 1000));
    {
        stderr.writer.print("[{d:0>2}:{d:0>2}:{d:0>2}] ", .{ hours, mins, secs }) catch {};
    }

    // 颜色 + 级别
    stderr.setColor(switch (level) {
        .err => .red,
        .warn => .yellow,
        .info => .green,
        .debug => .magenta,
    }) catch {};
    stderr.setColor(.bold) catch {};
    stderr.writer.writeAll(level.asText()) catch {};
    stderr.setColor(.reset) catch {};

    // scope
    stderr.setColor(.dim) catch {};
    stderr.writer.print("({s})", .{@tagName(scope)}) catch {};
    stderr.setColor(.reset) catch {};

    // 消息
    stderr.writer.writeAll(": ") catch {};
    stderr.writer.print(format ++ "\n", args) catch {};
}

// 在 main.zig 中通过 `pub const logFn = logger.niriLogFn` 注册
