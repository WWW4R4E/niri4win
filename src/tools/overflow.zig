const std = @import("std");
const niri4win = @import("root").niri4win;
const c = niri4win.win32;
const L = c.L;

fn showAndMoveOverflow(x: i32, y: i32, width: i32, height: i32, io: std.Io) !void {
    std.log.scoped(.Overflow).info("开始显示并移动溢出窗口: x={}, y={}, w={}, h={}", .{ x, y, width, height });

    std.log.scoped(.Overflow).info("发送 Win+B 激活托盘", .{});
    c.keybd_event(@intFromEnum(c.VK_LWIN), 0, c.KEYBD_EVENT_FLAGS{}, 0);
    c.keybd_event('B', 0, c.KEYBD_EVENT_FLAGS{}, 0);
    c.keybd_event('B', 0, c.KEYEVENTF_KEYUP, 0);
    c.keybd_event(@intFromEnum(c.VK_LWIN), 0, c.KEYEVENTF_KEYUP, 0);

    try std.Io.sleep(io, std.Io.Duration{ .nanoseconds = 50 * std.time.ns_per_ms }, .awake);

    std.log.scoped(.Overflow).info("发送回车打开溢出窗口", .{});
    c.keybd_event(@intFromEnum(c.VK_RETURN), 0, c.KEYBD_EVENT_FLAGS{}, 0);
    c.keybd_event(@intFromEnum(c.VK_RETURN), 0, c.KEYEVENTF_KEYUP, 0);

    var hwnd: ?c.HWND = null;
    var attempts: u32 = 0;
    while (attempts < 50) {
        try std.Io.sleep(io, std.Io.Duration{ .nanoseconds = 10 * std.time.ns_per_ms }, .awake);

        hwnd = c.FindWindowW(L("Windows.UI.Core.CoreWindow"), null);
        if (hwnd == null) {
            hwnd = c.FindWindowW(L("PopupHost"), null);
        }
        if (hwnd == null) {
            hwnd = c.FindWindowW(null, L("通知区域溢出窗口"));
        }

        if (hwnd != null and c.IsWindowVisible(hwnd) != 0) {
            std.log.scoped(.Overflow).info("第{}次尝试: 找到溢出窗口 hwnd={any}", .{ attempts, hwnd });
            break;
        }
        attempts += 1;
    }

    if (hwnd == null) {
        std.log.scoped(.Overflow).info("未找到溢出窗口 (尝试了50次)", .{});
        return error.WindowNotFound;
    }

    std.log.scoped(.Overflow).info("设置窗口位置: x={}, y={}, w={}, h={}", .{ x, y, width, height });
    _ = c.SetWindowPos(
        hwnd,
        c.HWND_TOPMOST,
        x,
        y,
        width,
        height,
        .{ .NOZORDER = 1, .NOACTIVATE = 1, .SHOWWINDOW = 1, .DRAWFRAME = 1, .NOCOPYBITS = 1, .NOSENDCHANGING = 1 },
    );
    std.log.scoped(.Overflow).info("溢出窗口位置设置完成", .{});
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    niri4win.config.init(io);

    std.log.scoped(.Overflow).info("程序启动", .{});
    _ = try showAndMoveOverflow(50, 50, 0, 0, io);
    std.log.scoped(.Overflow).info("程序执行完成", .{});
}
