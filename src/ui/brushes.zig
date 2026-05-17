const std = @import("std");
const niri4win = @import("../root.zig");
const win32 = niri4win.win32;

/// BrushCache lazily creates and owns D2D solid color brushes.
/// All brushes are invalidated (set to null) on resize; get* accessors
/// recreate them on next access.
pub const BrushCache = struct {
    active_fill: ?*win32.ID2D1SolidColorBrush,
    active_border: ?*win32.ID2D1SolidColorBrush,
    inactive_fill: ?*win32.ID2D1SolidColorBrush,
    inactive_border: ?*win32.ID2D1SolidColorBrush,

    pub fn init() BrushCache {
        return .{
            .active_fill = null,
            .active_border = null,
            .inactive_fill = null,
            .inactive_border = null,
        };
    }

    pub fn deinit(self: *BrushCache) void {
        if (self.active_fill) |b| _ = b.IUnknown.Release();
        if (self.active_border) |b| _ = b.IUnknown.Release();
        if (self.inactive_fill) |b| _ = b.IUnknown.Release();
        if (self.inactive_border) |b| _ = b.IUnknown.Release();
        self.* = init();
    }

    /// Call after D2DContext.resize() / refreshTarget() to mark
    /// all brushes as invalid. They will be recreated on next get* call.
    pub fn invalidate(self: *BrushCache) void {
        self.active_fill = null;
        self.active_border = null;
        self.inactive_fill = null;
        self.inactive_border = null;
    }

    pub fn getActiveFill(self: *BrushCache, ctx: *win32.ID2D1DeviceContext) *win32.ID2D1SolidColorBrush {
        if (self.active_fill) |b| return b;
        var b: ?*win32.ID2D1SolidColorBrush = null;
        _ = ctx.ID2D1RenderTarget.CreateSolidColorBrush(&.{ .r = 68.0 / 255.0, .g = 51.0 / 255.0, .b = 51.0 / 255.0, .a = 1.0 }, null, @ptrCast(&b));
        self.active_fill = b;
        return b.?;
    }

    pub fn getActiveBorder(self: *BrushCache, ctx: *win32.ID2D1DeviceContext) *win32.ID2D1SolidColorBrush {
        if (self.active_border) |b| return b;
        var b: ?*win32.ID2D1SolidColorBrush = null;
        _ = ctx.ID2D1RenderTarget.CreateSolidColorBrush(&.{ .r = 1.0, .g = 102.0 / 255.0, .b = 102.0 / 255.0, .a = 1.0 }, null, @ptrCast(&b));
        self.active_border = b;
        return b.?;
    }

    pub fn getInactiveFill(self: *BrushCache, ctx: *win32.ID2D1DeviceContext) *win32.ID2D1SolidColorBrush {
        if (self.inactive_fill) |b| return b;
        var b: ?*win32.ID2D1SolidColorBrush = null;
        _ = ctx.ID2D1RenderTarget.CreateSolidColorBrush(&.{ .r = 34.0 / 255.0, .g = 34.0 / 255.0, .b = 34.0 / 255.0, .a = 1.0 }, null, @ptrCast(&b));
        self.inactive_fill = b;
        return b.?;
    }

    pub fn getInactiveBorder(self: *BrushCache, ctx: *win32.ID2D1DeviceContext) *win32.ID2D1SolidColorBrush {
        if (self.inactive_border) |b| return b;
        var b: ?*win32.ID2D1SolidColorBrush = null;
        _ = ctx.ID2D1RenderTarget.CreateSolidColorBrush(&.{ .r = 51.0 / 255.0, .g = 51.0 / 255.0, .b = 51.0 / 255.0, .a = 1.0 }, null, @ptrCast(&b));
        self.inactive_border = b;
        return b.?;
    }
};
