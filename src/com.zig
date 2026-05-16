const std = @import("std");
const niri4win = @import("root").niri4win;
const win32 = niri4win.win32;

pub const CLSID_ImmersiveShell = win32.Guid{ .Ints = .{ .a = 0xC2F03A33, .b = 0x21F5, .c = 0x47FA, .d = .{ 0xB4, 0xBB, 0x15, 0x63, 0x62, 0xA2, 0xF2, 0x39 } } };

pub const IServiceProvider = win32.IServiceProvider;
pub const IObjectArray = win32.IObjectArray;
pub const IID_IServiceProvider = win32.IID_IServiceProvider;

pub fn createServiceProvider() !*IServiceProvider {
    var serviceProvider: *IServiceProvider = undefined;
    const hr = win32.CoCreateInstance(&CLSID_ImmersiveShell, null, win32.CLSCTX_ALL, IID_IServiceProvider, @ptrCast(&serviceProvider));
    if (hr == 0) {
        return serviceProvider;
    } else {
        std.log.scoped(.Com).err("CoCreateInstance failed, HRESULT=0x{X:0>8}", .{@as(u32, @bitCast(hr))});
        return error.FailedToCreateComObject;
    }
}

pub fn GetAtWithIID(self: *IObjectArray, uiIndex: usize, iid: *const win32.Guid, comptime T: type) struct { hr: win32.HRESULT, ptr: ?*T } {
    var object: *anyopaque = undefined;
    const hr = self.GetAt(@intCast(uiIndex), iid, &object);
    if (hr == 0) {
        return .{ .hr = hr, .ptr = @ptrCast(@alignCast(object)) };
    }
    return .{ .hr = hr, .ptr = null };
}
