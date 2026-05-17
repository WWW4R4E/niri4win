pub const ui = struct {
    pub const app_bar = @import("ui/app_bar.zig");
    pub const task_bar = @import("ui/task_bar.zig");
    pub const d2d = @import("ui/d2d.zig");
    pub const brushes = @import("ui/brushes.zig");
    pub const state = @import("ui/state.zig");
    pub const main_bar_painter = @import("ui/main_bar_painter.zig");
};
pub const win32 = @import("win32").everything;
pub const app = @import("app.zig");
pub const config = @import("config.zig");
pub const desktop = @import("desktop/manager.zig");
pub const input = @import("input/hotkey_manager.zig");
pub const tiling = @import("tiling/manager.zig");
pub const types = @import("types.zig");
pub const com = @import("com.zig");
pub const virtual_desktop = @import("desktop/virtual_desktop.zig");
