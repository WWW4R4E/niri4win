const std = @import("std");

const niri4win = @import("root").niri4win;
const win32 = niri4win.win32;
const config = niri4win.config;

pub const TaskWindowInternal = struct {
    hwnd: win32.HWND,
    title: [256:0]u8,
    icon: ?win32.HICON,
    process_path: [260:0]u8,
};

/// 检测窗口是否为全屏（游戏/视频全屏独占）
pub fn isFullscreenWindow(hwnd: win32.HWND) bool {
    // DX 全屏独占游戏的特征坐标：Windows位置(-32000,-32000)
    var wrect: win32.RECT = undefined;
    if (win32.GetWindowRect(hwnd, &wrect) == 0) return false;
    if (wrect.left == -32000 or wrect.top == -32000) return true;

    // 边框全屏：窗口尺寸覆盖整个显示器
    const ww = wrect.right - wrect.left;
    const wh = wrect.bottom - wrect.top;
    const monitor = win32.MonitorFromWindow(hwnd, win32.MONITOR_DEFAULTTONEAREST) orelse return false;
    var mi: win32.MONITORINFO = undefined;
    mi.cbSize = @sizeOf(win32.MONITORINFO);
    if (win32.GetMonitorInfoA(monitor, &mi) == 0) return false;
    const mw = mi.rcMonitor.right - mi.rcMonitor.left;
    const mh = mi.rcMonitor.bottom - mi.rcMonitor.top;
    const margin = 8;
    return (ww >= mw - margin and wh >= mh - margin);
}

pub fn isWindowManageable(hwnd: win32.HWND) bool {
    if (win32.IsWindowVisible(hwnd) == 0) return false;

    if (win32.GetWindow(hwnd, win32.GW_OWNER) != null) return false;

    const style_raw = win32.GetWindowLongA(hwnd, win32.GWL_STYLE);
    const style: win32.WINDOW_STYLE = @bitCast(style_raw);
    if (style.CHILD != 0) return false;

    const ex_style_raw = win32.GetWindowLongA(hwnd, win32.GWL_EXSTYLE);
    const ex_style: win32.WINDOW_EX_STYLE = @bitCast(ex_style_raw);
    if (ex_style.TOOLWINDOW != 0) return false;
    if (ex_style.NOACTIVATE != 0) return false;
    if (ex_style.TOPMOST != 0) return false;

    var title: [256:0]u8 = std.mem.zeroes([256:0]u8);
    const len = win32.GetWindowTextA(hwnd, @ptrCast(&title), title.len);
    if (len == 0) return false;

    const title_slice: [:0]const u8 = @ptrCast(&title);
    if (config.isBlacklistedTitle(title_slice)) return false;

    var placement: win32.WINDOWPLACEMENT = undefined;
    placement.length = @sizeOf(win32.WINDOWPLACEMENT);
    if (win32.GetWindowPlacement(hwnd, &placement) != 0) {
        const rect = placement.rcNormalPosition;
        if (rect.right - rect.left <= 0 or rect.bottom - rect.top <= 0) return false;
    }

    var class_name: [256:0]u8 = std.mem.zeroes([256:0]u8);
    _ = win32.GetClassNameA(hwnd, &class_name, class_name.len);
    const class_slice: [:0]const u8 = @ptrCast(&class_name);
    if (config.isBlacklistedClass(class_slice)) return false;

    var process_path: [260:0]u8 = std.mem.zeroes([260:0]u8);
    var pid: u32 = 0;
    _ = win32.GetWindowThreadProcessId(hwnd, &pid);

    const process_handle = win32.OpenProcess(win32.PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
    if (process_handle) |h| {
        var path_len: u32 = 260;
        _ = win32.QueryFullProcessImageNameA(h, win32.PROCESS_NAME_WIN32, @ptrCast(&process_path), &path_len);
        _ = win32.CloseHandle(h);
    }

    const path_slice: [:0]const u8 = @ptrCast(&process_path);
    if (config.isBlacklistedPath(path_slice)) return false;

    // 排除全屏窗口（游戏、全屏视频等）
    if (isFullscreenWindow(hwnd)) return false;
    // {
    //     var wr: win32.RECT = undefined;
    //     _ = win32.GetWindowRect(hwnd, &wr);
    //     logger.log("TaskBar", "可管理窗口: hwnd=0x{X} title=\"{s}\" rect=({d},{d})-({d},{d})", .{
    //         @as(usize, @intFromPtr(hwnd)),
    //         @as(*[256:0]u8, @ptrCast(&title)),
    //         wr.left,
    //         wr.top,
    //         wr.right,
    //         wr.bottom,
    //     });
    // }
    return true;
}

pub fn getWindowIcon(hwnd: win32.HWND) ?win32.HICON {
    var icon: ?win32.HICON = null;

    const WM_GETICON = 0x007F;
    const ICON_BIG = 1;
    const ICON_SMALL2 = 2;

    icon = @ptrFromInt(@as(usize, @intCast(win32.SendMessageA(hwnd, WM_GETICON, ICON_BIG, 0))));
    if (icon != null) return icon;

    icon = @ptrFromInt(@as(usize, @intCast(win32.SendMessageA(hwnd, WM_GETICON, ICON_SMALL2, 0))));
    if (icon != null) return icon;

    icon = @ptrFromInt(@as(usize, @intCast(win32.GetClassLongPtrA(hwnd, win32.GCLP_HICON))));
    if (icon != null) return icon;

    icon = @ptrFromInt(@as(usize, @intCast(win32.GetClassLongPtrA(hwnd, win32.GCLP_HICONSM))));
    return icon;
}

const IID_IShellItemImageFactory = win32.Guid{
    .Ints = .{ .a = 0xBCC18B79, .b = 0xBA16, .c = 0x442F, .d = .{ 0x80, 0xC4, 0x8A, 0x59, 0xC3, 0x0C, 0x46, 0x3B } },
};

const IShellItemImageFactoryVtbl = extern struct {
    QueryInterface: *const fn (This: [*c]IShellItemImageFactory, riid: *const win32.Guid, ppvObject: [*c]?*anyopaque) callconv(.c) win32.HRESULT,
    AddRef: *const fn (This: [*c]IShellItemImageFactory) callconv(.c) u32,
    Release: *const fn (This: [*c]IShellItemImageFactory) callconv(.c) u32,
    GetImage: *const fn (This: [*c]IShellItemImageFactory, size: win32.SIZE, flags: win32.SIIGBF, phbm: [*c]?*anyopaque) callconv(.c) win32.HRESULT,
};

const IShellItemImageFactory = extern struct {
    lpVtbl: *const IShellItemImageFactoryVtbl,

    pub fn QueryInterface(self: *IShellItemImageFactory, riid: *const win32.Guid, ppvObject: [*c]?*anyopaque) win32.HRESULT {
        return self.lpVtbl.*.QueryInterface(self, riid, ppvObject);
    }
    pub fn AddRef(self: *IShellItemImageFactory) u32 {
        return self.lpVtbl.*.AddRef(self);
    }
    pub fn Release(self: *IShellItemImageFactory) u32 {
        return self.lpVtbl.*.Release(self);
    }
    pub fn GetImage(self: *IShellItemImageFactory, size: win32.SIZE, flags: win32.SIIGBF, phbm: [*c]?*anyopaque) win32.HRESULT {
        return self.lpVtbl.*.GetImage(self, size, flags, phbm);
    }
};

fn hbitmapToHicon(hbitmap: win32.HBITMAP) ?win32.HICON {
    var ds: win32.DIBSECTION = undefined;
    if (win32.GetObjectA(@ptrCast(hbitmap), @sizeOf(win32.DIBSECTION), &ds) == 0) return null;

    const w = ds.dsBmih.biWidth;
    const h = @abs(ds.dsBmih.biHeight);

    const mask = win32.CreateBitmap(@as(i32, @intCast(w)), @as(i32, @intCast(h)), 1, 1, null) orelse return null;
    defer _ = win32.DeleteObject(mask);

    var ii: win32.ICONINFO = undefined;
    ii.fIcon = 1;
    ii.hbmColor = hbitmap;
    ii.hbmMask = mask;

    return win32.CreateIconIndirect(&ii);
}

pub fn getIconFromAumid(aumid: [*:0]const u16) ?win32.HICON {
    const prefix = [_]u16{ 's', 'h', 'e', 'l', 'l', ':', 'A', 'p', 'p', 's', 'F', 'o', 'l', 'd', 'e', 'r', '\\' };
    var path_storage: [1024:0]u16 = undefined;

    for (prefix, 0..) |c, i| {
        path_storage[i] = c;
    }

    var pos: usize = prefix.len;
    var j: usize = 0;
    while (aumid[j] != 0) : (j += 1) {
        if (pos >= 1023) return null;
        path_storage[pos] = aumid[j];
        pos += 1;
    }
    path_storage[pos] = 0;

    var factory: ?*IShellItemImageFactory = null;
    const hr = win32.SHCreateItemFromParsingName(
        @ptrCast(&path_storage),
        null,
        &IID_IShellItemImageFactory,
        @ptrCast(&factory),
    );
    if (hr != 0 or factory == null) return null;
    defer _ = factory.?.Release();

    var hbitmap: ?*anyopaque = null;
    const size = win32.SIZE{ .cx = 32, .cy = 32 };
    const flags = win32.SIIGBF{ .ICONONLY = 1, .BIGGERSIZEOK = 1 };

    if (factory.?.GetImage(size, flags, @ptrCast(&hbitmap)) != 0 or hbitmap == null) return null;
    defer _ = win32.DeleteObject(@ptrCast(hbitmap.?));

    return hbitmapToHicon(@ptrCast(hbitmap.?));
}

pub fn extractIconFromPath(path: [*:0]const u8) ?win32.HICON {
    const SHGFI_LARGEICON: u32 = 0x00000000;
    const SHGFI_ICON: u32 = 0x00000100;
    const SHGFI_USEFILEATTRIBUTES: u32 = 0x00000010;

    var shfi: win32.SHFILEINFOA = undefined;
    const result = win32.SHGetFileInfoA(
        path,
        win32.FILE_ATTRIBUTE_NORMAL,
        &shfi,
        @sizeOf(win32.SHFILEINFOA),
        @bitCast(SHGFI_ICON | SHGFI_LARGEICON | SHGFI_USEFILEATTRIBUTES),
    );

    if (result != 0) {
        return shfi.hIcon;
    }
    return null;
}
