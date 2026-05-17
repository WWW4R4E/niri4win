const std = @import("std");
const niri4win = @import("../root.zig");
const win32 = niri4win.win32;
const tiling = niri4win.tiling;

/// Immutable snapshot of application state at render time.
/// Pure data — no COM, no D2D, no behaviour.
/// Can be constructed manually for testing.
pub const AppState = struct {
    tiling: *const tiling.Manager,
    foreground: ?win32.HWND,
    timestamp: u64,
};
