const std = @import("std");
const niri4win = @import("../root.zig");
const win32 = niri4win.win32;

var g_fUpdating = false;
var g_hShellTrayWnd: ?win32.HWND = null;

var g_show_taskbar: bool = true;

fn findShellTrayWnd() ?win32.HWND {
    return win32.FindWindowA("Shell_TrayWnd", null);
}

fn hideShellTray() void {
    if (g_show_taskbar) return;

    const hwnd = findShellTrayWnd() orelse return;

    var abd = std.mem.zeroes(win32.APPBARDATA);
    abd.cbSize = @sizeOf(win32.APPBARDATA);
    abd.hWnd = hwnd;
    abd.lParam = 1;
    _ = win32.SHAppBarMessage(win32.ABM_SETSTATE, &abd);
    _ = win32.ShowWindow(hwnd, win32.SW_HIDE);
    const hrgn = win32.CreateRectRgn(0, 0, 0, 0);
    _ = win32.SetWindowRgn(hwnd, hrgn, win32.TRUE);

    const hwnd_sec = win32.FindWindowA("Shell_SecondaryTrayWnd", null);
    if (hwnd_sec) |sec| {
        _ = win32.ShowWindow(sec, win32.SW_HIDE);
    }
}

fn showShellTray() void {
    if (g_show_taskbar) return;

    const hwnd = win32.FindWindowA("Shell_TrayWnd", null);
    if (hwnd) |h| {
        _ = win32.SetWindowRgn(h, null, win32.TRUE);
        var abd = std.mem.zeroes(win32.APPBARDATA);
        abd.cbSize = @sizeOf(win32.APPBARDATA);
        abd.hWnd = h;
        abd.lParam = 2;
        _ = win32.SHAppBarMessage(win32.ABM_SETSTATE, &abd);
        _ = win32.ShowWindow(h, win32.SW_SHOW);
    }

    const hwnd_sec = win32.FindWindowA("Shell_SecondaryTrayWnd", null);
    if (hwnd_sec) |sec| {
        _ = win32.ShowWindow(sec, win32.SW_SHOW);
    }
}

pub fn register(hwnd: win32.HWND, size: i32, edge: u32) bool {
    hideShellTray();

    var abd: win32.APPBARDATA = undefined;
    abd.cbSize = @sizeOf(win32.APPBARDATA);
    abd.hWnd = hwnd;

    if (win32.SHAppBarMessage(win32.ABM_NEW, &abd) == 0) {
        return false;
    }

    updatePosition(hwnd, size, edge);
    return true;
}

pub fn unregister(hwnd: win32.HWND) void {
    var abd: win32.APPBARDATA = undefined;
    abd.cbSize = @sizeOf(win32.APPBARDATA);
    abd.hWnd = hwnd;
    _ = win32.SHAppBarMessage(win32.ABM_REMOVE, &abd);

    showShellTray();
}

pub fn updatePosition(hwnd: win32.HWND, size: i32, edge: u32) void {
    if (g_fUpdating) return;
    g_fUpdating = true;
    defer g_fUpdating = false;

    var abd: win32.APPBARDATA = undefined;
    abd.cbSize = @sizeOf(win32.APPBARDATA);
    abd.hWnd = hwnd;
    abd.uEdge = edge;

    if (win32.SystemParametersInfoA(win32.SPI_GETWORKAREA, 0, &abd.rc, .{}) == 0) {
        abd.rc.left = 0;
        abd.rc.top = 0;
        abd.rc.right = win32.GetSystemMetrics(win32.SM_CXSCREEN);
        abd.rc.bottom = win32.GetSystemMetrics(win32.SM_CYSCREEN);
    }

    _ = win32.SHAppBarMessage(win32.ABM_QUERYPOS, &abd);

    switch (edge) {
        win32.ABE_LEFT => abd.rc.right = abd.rc.left + size,
        win32.ABE_RIGHT => abd.rc.left = abd.rc.right - size,
        win32.ABE_TOP => abd.rc.bottom = abd.rc.top + size,
        win32.ABE_BOTTOM => abd.rc.top = abd.rc.bottom - size,
        else => {},
    }

    _ = win32.SHAppBarMessage(win32.ABM_SETPOS, &abd);

    _ = win32.SetWindowPos(
        hwnd,
        win32.HWND_TOPMOST,
        abd.rc.left,
        abd.rc.top,
        abd.rc.right - abd.rc.left,
        abd.rc.bottom - abd.rc.top,
        win32.SWP_NOACTIVATE,
    );
}
