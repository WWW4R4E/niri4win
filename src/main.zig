const std = @import("std");
const builtin = @import("builtin");
pub const niri4win = @import("niri4win");
const logger = @import("logger.zig");

pub const logFn = logger.niriLogFn;

pub fn main(init: std.process.Init) !void {
    if (builtin.mode != .Debug) {
        _ = niri4win.win32.FreeConsole();
    }
    _ = niri4win.win32.SetProcessDPIAware();
    _ = niri4win.win32.CoInitializeEx(null, niri4win.win32.COINIT_MULTITHREADED);
    defer niri4win.win32.CoUninitialize();
    niri4win.config.init(init.io);
    var app = try niri4win.app.App.init(init);
    defer app.deinit();

    try app.run();
}
