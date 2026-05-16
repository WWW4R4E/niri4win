const std = @import("std");
const niri4win = @import("root").niri4win;
const win32 = niri4win.win32;
const virtual_desktop = niri4win.virtual_desktop;
const ui = niri4win.ui;
const com = niri4win.com;
const tiling = niri4win.tiling;
const desktop = niri4win.desktop;
const input = niri4win.input;
const config = niri4win.config;
const types = niri4win.types;
const d2d = niri4win.ui.d2d;

// ─── 功能分割开关 ─────────────────────────────
// 设为 true 启用对应功能，false 关闭。方便单独测试 bar / 窗口排布。
const ENABLE_BAR: bool = true; // acrylic 背景 + 工作区图标绘制
const ENABLE_TILING: bool = true; // 窗口平铺管理（虚拟桌面同步、焦点、移动等）
// ─────────────────────────────────────────────

var g_tiling_manager: ?*tiling.Manager = null;
var g_desktop_manager: ?*desktop.Manager = null;
var g_app: ?*App = null;
var g_d2d: ?d2d.D2DContext = null;
var g_prev_fs: bool = false; // 全屏状态防抖

pub const App = struct {
    allocator: std.mem.Allocator,
    tiling_manager: tiling.Manager,
    desktop_manager: ?*desktop.Manager,
    running: bool,
    hwnd: ?win32.HWND,

    pub fn init(process_init: std.process.Init) !App {
        std.log.scoped(.App).info("初始化 niri4win...", .{});
        const allocator = process_init.arena.allocator();

        var tiling_manager = tiling.Manager.init(allocator);
        try tiling_manager.ensureWorkspaceCount(1);

        var desktop_manager: ?*desktop.Manager = null;
        const desktop_result = desktop.Manager.create(allocator);
        if (desktop_result) |dm| {
            desktop_manager = dm;
            tiling_manager.appViewCollection = dm.appViewCollection;
            std.log.scoped(.App).info("桌面管理器初始化成功", .{});
        } else |err| {
            std.log.scoped(.App).err("桌面管理器初始化失败: {}", .{err});
        }

        g_tiling_manager = &tiling_manager;
        g_desktop_manager = desktop_manager;

        return App{
            .allocator = allocator,
            .tiling_manager = tiling_manager,
            .desktop_manager = desktop_manager,
            .running = true,
            .hwnd = null,
        };
    }

    fn syncWindowsFromViews(self: *App) void {
        const dm = self.desktop_manager orelse return;
        const collection = dm.appViewCollection orelse return;

        var desktopsNullable: ?*win32.IObjectArray = null;
        const hr_get = dm.desktopManagerInternal.GetDesktops(@ptrCast(&desktopsNullable));
        if (hr_get != 0 or desktopsNullable == null) return;
        var desktops = desktopsNullable.?;
        defer _ = desktops.IUnknown.Release();

        var dCount: u32 = 0;
        _ = desktops.GetCount(&dCount);

        const ivd_iid = dm.resolved_ivd_iid orelse blk: {
            const candidates = virtual_desktop.IID_IVirtualDesktop_Candidates;
            for (candidates) |cand| {
                const r = com.GetAtWithIID(desktops, 0, &cand.iid, virtual_desktop.IVirtualDesktop);
                if (r.hr == 0) {
                    _ = r.ptr.?.Release();
                    dm.resolved_ivd_iid = cand.iid;
                    break :blk cand.iid;
                }
            }
            return;
        };

        var desktop_ids = std.ArrayList(win32.Guid).empty;
        defer desktop_ids.deinit(self.allocator);
        for (0..dCount) |i| {
            const r = com.GetAtWithIID(desktops, i, &ivd_iid, virtual_desktop.IVirtualDesktop);
            if (r.hr == 0 and r.ptr != null) {
                var desktop_id: win32.Guid = undefined;
                _ = r.ptr.?.GetID(&desktop_id);
                _ = r.ptr.?.Release();
                desktop_ids.append(self.allocator, desktop_id) catch {};
            }
        }

        var viewsArray: ?*win32.IObjectArray = null;
        if (collection.GetViews(@ptrCast(&viewsArray)) != 0 or viewsArray == null) return;
        defer _ = viewsArray.?.IUnknown.Release();

        var viewCount: u32 = 0;
        _ = viewsArray.?.GetCount(&viewCount);
        std.log.scoped(.App).info("GetViews 获取到 {d} 个视图", .{viewCount});

        var window_buckets = std.ArrayList(std.ArrayList(win32.HWND)).empty;
        defer {
            for (window_buckets.items) |*b| b.deinit(self.allocator);
            window_buckets.deinit(self.allocator);
        }
        for (0..dCount) |_| {
            window_buckets.append(self.allocator, std.ArrayList(win32.HWND).empty) catch {};
        }

        for (0..viewCount) |vi| {
            const vr = com.GetAtWithIID(viewsArray.?, vi, &virtual_desktop.IID_IApplicationView, virtual_desktop.IApplicationView);
            if (vr.hr != 0 or vr.ptr == null) continue;
            const view = vr.ptr.?;
            defer _ = view.Release();

            var hwnd: win32.HWND = undefined;
            @memset(@as(*[8]u8, @ptrCast(&hwnd)), 0);
            if (view.GetThumbnailWindow(&hwnd) != 0 or @intFromPtr(hwnd) == 0) continue;
            if (!ui.task_bar.isWindowManageable(hwnd)) continue;
            if (self.hwnd) |appbar_hwnd| {
                if (@intFromPtr(hwnd) == @intFromPtr(appbar_hwnd)) continue;
            }

            var viewDesktopId: win32.Guid = undefined;
            var workspace_idx: usize = 0;
            if (view.GetVirtualDesktopId(&viewDesktopId) == 0) {
                for (desktop_ids.items, 0..) |desktop_id, idx| {
                    if (std.mem.eql(u8, std.mem.asBytes(&viewDesktopId), std.mem.asBytes(&desktop_id))) {
                        workspace_idx = idx;
                        break;
                    }
                }
            }

            if (workspace_idx < window_buckets.items.len) {
                window_buckets.items[workspace_idx].append(self.allocator, hwnd) catch {};
            }
        }

        var changed = false;
        for (self.tiling_manager.workspaces.items) |*ws| {
            var i: usize = 0;
            while (i < ws.columns.items.len) {
                const h = ws.columns.items[i].window.hwnd;
                if (win32.IsWindow(h) == 0 or !ui.task_bar.isWindowManageable(h)) {
                    _ = ws.columns.orderedRemove(i);
                    if (i < ws.focused) ws.focused -|= 1;
                    changed = true;
                } else {
                    i += 1;
                }
            }
            if (ws.columns.items.len > 0 and ws.focused >= ws.columns.items.len) {
                ws.focused = ws.columns.items.len - 1;
            }
        }

        for (window_buckets.items, 0..) |*b, ws_idx| {
            if (b.items.len == 0) continue;
            changed = true;
            self.tiling_manager.ensureWorkspaceCount(ws_idx + 1) catch {};
            for (b.items) |hwnd| {
                var already_tracked = false;
                for (self.tiling_manager.workspaces.items) |*existing_ws| {
                    if (existing_ws.findColumn(hwnd) != null) {
                        already_tracked = true;
                        break;
                    }
                }
                if (!already_tracked) {
                    _ = self.tiling_manager.addWindowToWorkspace(hwnd, ws_idx) catch false;
                }
            }
            std.log.scoped(.App).info("桌面 {d}: 添加 {d} 个窗口 (同步)", .{ ws_idx, b.items.len });
        }
        if (changed) {
            self.tiling_manager.arrange();
        }

        if (self.desktop_manager) |dm_ptr| {
            const current_desktop_idx = dm_ptr.getCurrentDesktopIndex() catch 0;
            if (current_desktop_idx != self.tiling_manager.current) {
                std.log.scoped(.App).info("桌面切换检测: os_desktop={d}, ws_current={d}", .{ current_desktop_idx, self.tiling_manager.current });
                self.tiling_manager.ensureWorkspaceCount(current_desktop_idx + 1) catch {};
                self.tiling_manager.current = current_desktop_idx;
                self.tiling_manager.arrange();
            }
        }
    }

    pub fn deinit(self: *App) void {
        std.log.scoped(.App).info("清理 niri4win...", .{});

        self.tiling_manager.deinit();

        if (self.desktop_manager) |dm| {
            dm.deinit(self.allocator);
        }

        g_tiling_manager = null;
        g_desktop_manager = null;
    }

    pub fn run(self: *App) !void {
        g_app = self;
        defer g_app = null;

        const hinstance = win32.GetModuleHandleA(null) orelse return error.GetModuleHandleFailed;

        input.init();
        input.registerHotkeys();
        defer input.deinit();

        self.hwnd = try createAppBarWindow(hinstance);

        // 初始化 Direct2D
        {
            var cr: win32.RECT = undefined;
            _ = win32.GetClientRect(self.hwnd.?, &cr);
            const cw = @as(u32, @intCast(cr.right - cr.left));
            const ch = @as(u32, @intCast(cr.bottom - cr.top));
            g_d2d = d2d.D2DContext.init(self.hwnd.?, cw, ch) catch |err| brk: {
                std.log.scoped(.App).err("D2D初始化失败: {}", .{err});
                break :brk null;
            };
            // 预加载 acrylic（壁纸+噪声+effect 链），避免首次 WM_PAINT 空转
            if (g_d2d) |*ctx| ctx.initAcrylic();
        }

        // D2D 就绪后再显示窗口，避免白屏
        _ = win32.ShowWindow(self.hwnd.?, win32.SW_SHOW);

        if (ENABLE_TILING) {
            self.syncWindowsFromViews();

            const current_idx = if (self.desktop_manager) |dm| dm.getCurrentDesktopIndex() catch 0 else 0;
            if (current_idx > 0) {
                try self.tiling_manager.switchWorkspace(current_idx);
            }
        }

        if (self.hwnd) |hw| {
            _ = win32.InvalidateRect(hw, null, 1);
        }

        std.log.scoped(.App).info("启动后工作区数: {d}, 当前工作区窗口数: {d}", .{ self.tiling_manager.getWorkspaceCount(), self.tiling_manager.getWindowCount() });

        self.tiling_manager.markInitialized();
        self.tiling_manager.arrange();

        var msg: win32.MSG = undefined;
        self.running = true;
        var refresh_counter: u32 = 0;

        while (self.running) {
            const has_message = win32.PeekMessageA(&msg, null, 0, 0, win32.PM_REMOVE) != 0;
            if (has_message) {
                if (msg.message == win32.WM_QUIT) {
                    self.running = false;
                    break;
                }

                _ = win32.TranslateMessage(&msg);
                _ = win32.DispatchMessageA(&msg);
            }

            const action = input.processMessage(msg);
            if (action != .none) {
                if (ENABLE_TILING) {
                    self.handleAction(action) catch {};
                }
                if (self.hwnd) |hw| {
                    _ = win32.InvalidateRect(hw, null, 1);
                }
            }

            if (ENABLE_TILING) {
                if (self.tiling_manager.focusWindowByHwnd(win32.GetForegroundWindow())) {
                    self.tiling_manager.arrange();
                    if (self.hwnd) |hw| {
                        _ = win32.InvalidateRect(hw, null, 1);
                    }
                }
            }

            refresh_counter += 1;
            if (refresh_counter >= 50) {
                refresh_counter = 0;
                if (ENABLE_TILING) {
                    self.syncWindowsFromViews();
                }
                if (self.hwnd) |hw| {
                    _ = win32.InvalidateRect(hw, null, 1);
                }
            }

            // 全屏窗口检测 → 自动隐藏/显示 appbar
            // const fg = win32.GetForegroundWindow();
            // const fg_fs = (fg != null) and ui.task_bar.isFullscreenWindow(fg.?);
            // if (fg_fs and !g_prev_fs) {
            //     g_prev_fs = true;
            //     if (self.hwnd) |hw| {
            //         _ = win32.ShowWindow(hw, win32.SW_HIDE);
            //     }
            // } else if (!fg_fs and g_prev_fs) {
            //     g_prev_fs = false;
            //     if (self.hwnd) |hw| {
            //         _ = win32.ShowWindow(hw, win32.SW_SHOW);
            //         _ = win32.InvalidateRect(hw, null, 1);
            //     }
            // }

            _ = win32.Sleep(1);
        }

        std.log.scoped(.App).info("程序结束", .{});
    }

    fn handleAction(self: *App, action: types.Action) !void {
        switch (action) {
            .none => {},
            .quit => {
                std.log.scoped(.App).info("收到退出指令，程序退出", .{});
                self.running = false;
            },
            .focus_left => {
                std.log.scoped(.Operation).info("操作: 聚焦左列", .{});
                self.tiling_manager.focusColumnLeft();
            },
            .focus_right => {
                std.log.scoped(.Operation).info("操作: 聚焦右列", .{});
                self.tiling_manager.focusColumnRight();
            },
            .move_left => {
                std.log.scoped(.Operation).info("操作: 窗口左移", .{});
                self.tiling_manager.moveColumnLeft();
            },
            .move_right => {
                std.log.scoped(.Operation).info("操作: 窗口右移", .{});
                self.tiling_manager.moveColumnRight();
            },
            .increase_width => {
                std.log.scoped(.Operation).info("操作: 增加宽度", .{});
                self.tiling_manager.increaseColumnWidth();
            },
            .decrease_width => {
                std.log.scoped(.Operation).info("操作: 减少宽度", .{});
                self.tiling_manager.decreaseColumnWidth();
            },
            .toggle_fullscreen => {
                const is_fullscreen = self.tiling_manager.toggleFullscreen();
                std.log.scoped(.Operation).info("操作: {s}", .{if (is_fullscreen) "进入全屏" else "退出全屏"});
            },
            .workspace_up => {
                std.log.scoped(.Operation).info("操作: 切换到上一工作区", .{});
                if (self.desktop_manager) |dm| {
                    const current = dm.getCurrentDesktopIndex() catch |e| {
                        std.log.scoped(.App).err("获取当前桌面失败: {}", .{e});
                        return;
                    };
                    if (current > 0) {
                        dm.switchToDesktopByIndex(current - 1) catch |e| {
                            std.log.scoped(.App).err("切换桌面失败: {}", .{e});
                        };
                    }
                }
                try self.tiling_manager.switchWorkspaceUp();
            },
            .workspace_down => {
                std.log.scoped(.Operation).info("操作: 切换到下一工作区", .{});
                if (self.desktop_manager) |dm| {
                    const current = dm.getCurrentDesktopIndex() catch |e| {
                        std.log.scoped(.App).err("获取当前桌面失败: {}", .{e});
                        return;
                    };
                    const count = dm.getDesktopCount();
                    if (current < count - 1) {
                        dm.switchToDesktopByIndex(current + 1) catch |e| {
                            std.log.scoped(.App).err("切换桌面失败: {}", .{e});
                        };
                    }
                }
                try self.tiling_manager.switchWorkspaceDown();
            },
            .move_workspace_up => {
                std.log.scoped(.Operation).info("操作: 窗口移到上一工作区", .{});
                if (self.desktop_manager) |dm| {
                    const current = dm.getCurrentDesktopIndex() catch |e| {
                        std.log.scoped(.App).err("获取当前桌面失败: {}", .{e});
                        return;
                    };
                    if (current > 0) {
                        const focused_hwnd = self.tiling_manager.workspaces.items[self.tiling_manager.current].focusedHwnd();
                        if (focused_hwnd) |hwnd| {
                            dm.moveWindowToDesktop(hwnd, current - 1) catch |e| {
                                std.log.scoped(.App).err("移动窗口失败: {}", .{e});
                            };
                        }
                    }
                }
                try self.tiling_manager.moveToWorkspaceUp();
            },
            .move_workspace_down => {
                std.log.scoped(.Operation).info("操作: 窗口移到下一工作区", .{});
                if (self.desktop_manager) |dm| {
                    const current = dm.getCurrentDesktopIndex() catch |e| {
                        std.log.scoped(.App).err("获取当前桌面失败: {}", .{e});
                        return;
                    };
                    const count = dm.getDesktopCount();
                    if (current < count - 1) {
                        const focused_hwnd = self.tiling_manager.workspaces.items[self.tiling_manager.current].focusedHwnd();
                        if (focused_hwnd) |hwnd| {
                            dm.moveWindowToDesktop(hwnd, current + 1) catch |e| {
                                std.log.scoped(.App).err("移动窗口失败: {}", .{e});
                            };
                        }
                    }
                }
                try self.tiling_manager.moveToWorkspaceDown();
            },
            else => {
                if (input.columnIndexFromAction(action)) |col_idx| {
                    std.log.scoped(.Operation).info("操作: 聚焦列 {d}", .{col_idx + 1});
                    self.tiling_manager.focusColumnByIndex(col_idx);
                } else if (input.workspaceIndexFromAction(action)) |ws_idx| {
                    if (action == .switch_workspace_1 or
                        action == .switch_workspace_2 or
                        action == .switch_workspace_3 or
                        action == .switch_workspace_4 or
                        action == .switch_workspace_5 or
                        action == .switch_workspace_6 or
                        action == .switch_workspace_7 or
                        action == .switch_workspace_8 or
                        action == .switch_workspace_9)
                    {
                        try self.tiling_manager.switchWorkspace(ws_idx);

                        if (self.desktop_manager) |dm| {
                            var count = dm.getDesktopCount();
                            while (ws_idx >= count) : (count += 1) {
                                std.log.scoped(.App).info("创建新桌面 {d}", .{count + 1});
                                dm.createNewDesktop() catch |err| {
                                    std.log.scoped(.App).err("创建桌面失败: {}", .{err});
                                    break;
                                };
                            }

                            if (ws_idx < count) {
                                std.log.scoped(.Operation).info("操作: 切换到桌面 {d}", .{ws_idx + 1});
                                dm.switchToDesktopByIndex(ws_idx) catch |err| {
                                    std.log.scoped(.App).err("切换桌面失败: {}", .{err});
                                };
                            }
                        }
                    } else {
                        try self.tiling_manager.moveToWorkspace(ws_idx);

                        if (self.desktop_manager) |dm| {
                            var count = dm.getDesktopCount();
                            while (ws_idx >= count) : (count += 1) {
                                std.log.scoped(.App).info("创建新桌面 {d}", .{count + 1});
                                dm.createNewDesktop() catch |err| {
                                    std.log.scoped(.App).err("创建桌面失败: {}", .{err});
                                    break;
                                };
                            }

                            if (ws_idx < count) {
                                std.log.scoped(.Operation).info("操作: 窗口移到桌面 {d} 并切换到该桌面", .{ws_idx + 1});
                                dm.moveForegroundWindowToDesktopByIndex(ws_idx) catch |err| {
                                    std.log.scoped(.App).err("移动窗口失败: {}", .{err});
                                };
                                dm.switchToDesktopByIndex(ws_idx) catch |err| {
                                    std.log.scoped(.App).err("切换桌面失败: {}", .{err});
                                };
                            }
                        }
                    }
                }
            },
        }
    }
};

fn windowProc(hwnd: win32.HWND, msg: u32, wparam: win32.WPARAM, lparam: win32.LPARAM) callconv(.winapi) win32.LRESULT {
    switch (msg) {
        win32.WM_ERASEBKGND => return 1,
        win32.WM_PAINT => {
            if (g_d2d) |*d2d_ctx| {
                d2d_ctx.beginDraw();

                if (g_app) |app| {
                    if (!ENABLE_BAR) {
                        d2d_ctx.endDraw();
                        return 0;
                    }
                    const icon_size: f32 = 24.0;
                    const padding: f32 = 8.0;
                    const ws_pad: f32 = 8.0;
                    const ws_margin: f32 = 4.0;
                    const corner_r: f32 = 6.0;
                    var curr_x: f32 = padding;
                    var curr_y: f32 = padding;

                    var client: win32.RECT = undefined;
                    _ = win32.GetClientRect(hwnd, &client);
                    const ww: f32 = @floatFromInt(client.right - client.left);

                    const cur_ws = app.tiling_manager.current;
                    const dc = if (app.desktop_manager) |dm| dm.getDesktopCount() else @max(app.tiling_manager.getWorkspaceCount(), 1);
                    const disp_c = @max(dc, app.tiling_manager.getWorkspaceCount());

                    var wi: usize = 0;
                    while (wi < disp_c) : (wi += 1) {
                        if (wi >= app.tiling_manager.workspaces.items.len) break;
                        const ws = &app.tiling_manager.workspaces.items[wi];
                        const is_cur = (wi == cur_ws);
                        const hw = ws.columns.items.len > 0;

                        const wsw = if (hw)
                            @as(f32, @floatFromInt(ws.columns.items.len)) * (icon_size + padding) + ws_pad * 2.0
                        else
                            icon_size + ws_pad * 2.0;
                        const wsh = icon_size + ws_pad * 2.0;

                        const rr = win32.D2D1_ROUNDED_RECT{
                            .rect = .{ .left = curr_x, .top = curr_y, .right = curr_x + wsw, .bottom = curr_y + wsh },
                            .radiusX = corner_r,
                            .radiusY = corner_r,
                        };

                        if (is_cur) {
                            if (d2d_ctx.brush_active_fill == null) {
                                var b2: ?*win32.ID2D1SolidColorBrush = null;
                                _ = d2d_ctx.ctx.ID2D1RenderTarget.CreateSolidColorBrush(&.{ .r = 68.0 / 255.0, .g = 51.0 / 255.0, .b = 51.0 / 255.0, .a = 1.0 }, null, @ptrCast(&b2));
                                d2d_ctx.brush_active_fill = b2;
                            }
                            if (d2d_ctx.brush_active_border == null) {
                                var b2: ?*win32.ID2D1SolidColorBrush = null;
                                _ = d2d_ctx.ctx.ID2D1RenderTarget.CreateSolidColorBrush(&.{ .r = 1.0, .g = 102.0 / 255.0, .b = 102.0 / 255.0, .a = 1.0 }, null, @ptrCast(&b2));
                                d2d_ctx.brush_active_border = b2;
                            }
                            if (d2d_ctx.brush_active_fill) |bf|
                                d2d_ctx.ctx.ID2D1RenderTarget.FillRoundedRectangle(&rr, @ptrCast(bf));
                            if (d2d_ctx.brush_active_border) |bb|
                                d2d_ctx.ctx.ID2D1RenderTarget.DrawRoundedRectangle(&rr, @ptrCast(bb), 2.0, null);
                        } else {
                            if (d2d_ctx.brush_inactive_fill == null) {
                                var b2: ?*win32.ID2D1SolidColorBrush = null;
                                _ = d2d_ctx.ctx.ID2D1RenderTarget.CreateSolidColorBrush(&.{ .r = 34.0 / 255.0, .g = 34.0 / 255.0, .b = 34.0 / 255.0, .a = 1.0 }, null, @ptrCast(&b2));
                                d2d_ctx.brush_inactive_fill = b2;
                            }
                            if (d2d_ctx.brush_inactive_border == null) {
                                var b2: ?*win32.ID2D1SolidColorBrush = null;
                                _ = d2d_ctx.ctx.ID2D1RenderTarget.CreateSolidColorBrush(&.{ .r = 51.0 / 255.0, .g = 51.0 / 255.0, .b = 51.0 / 255.0, .a = 1.0 }, null, @ptrCast(&b2));
                                d2d_ctx.brush_inactive_border = b2;
                            }
                            if (d2d_ctx.brush_inactive_fill) |bf|
                                d2d_ctx.ctx.ID2D1RenderTarget.FillRoundedRectangle(&rr, @ptrCast(bf));
                            if (d2d_ctx.brush_inactive_border) |bb|
                                d2d_ctx.ctx.ID2D1RenderTarget.DrawRoundedRectangle(&rr, @ptrCast(bb), 1.0, null);
                        }

                        var ix: f32 = curr_x + ws_pad;
                        const iy: f32 = curr_y + ws_pad;
                        for (ws.columns.items, 0..) |col, i| {
                            const is_foc = (wi == cur_ws and i == ws.focused);
                            const ds: f32 = if (is_foc) 28.0 else icon_size;
                            const ox: f32 = if (is_foc) (icon_size - ds) / 2.0 else 0.0;
                            const oy: f32 = if (is_foc) (icon_size - ds) / 2.0 else 0.0;

                            if (col.window.icon) |icn| {
                                if (d2d_ctx.hiconToBitmap(icn)) |bmp| {
                                    defer _ = bmp.IUnknown.Release();
                                    const dr = win32.D2D_RECT_F{ .left = ix + ox, .top = iy + oy, .right = ix + ox + ds, .bottom = iy + oy + ds };
                                    d2d_ctx.ctx.ID2D1RenderTarget.DrawBitmap(bmp, &dr, 1.0, .LINEAR, null);
                                } else |_| {}
                            }
                            ix += icon_size + padding;
                        }

                        curr_x += wsw + ws_margin;
                        if (curr_x + wsw > ww - padding) {
                            curr_x = padding;
                            curr_y += wsh + ws_margin;
                        }
                    }

                    const rf = win32.GetForegroundWindow();
                    if (rf != null) {
                        const ir: f32 = 24.0;
                        const rx = ww - ir - padding;
                        const ry = padding;
                        const ricon = ui.task_bar.getWindowIcon(rf.?);
                        if (ricon) |icn| {
                            if (d2d_ctx.hiconToBitmap(icn)) |b| {
                                defer _ = b.IUnknown.Release();
                                const dr = win32.D2D_RECT_F{ .left = rx, .top = ry, .right = rx + ir, .bottom = ry + ir };
                                d2d_ctx.ctx.ID2D1RenderTarget.DrawBitmap(b, &dr, 1.0, .LINEAR, null);
                            } else |_| {}
                        }
                    }
                }

                d2d_ctx.endDraw();
            }
            return 0;
        },
        win32.WM_LBUTTONDOWN => {
            if (g_app) |app| {
                const x = @as(i32, @intCast(lparam & 0xFFFF));
                const y = @as(i32, @intCast((lparam >> 16) & 0xFFFF));

                const icon_size: i32 = 24;
                const padding: i32 = 8;
                const ws_pad: i32 = 8;
                const ws_margin: i32 = 4;
                var curr_x: i32 = padding;
                var curr_y: i32 = padding;

                var clicked_ws: ?usize = null;
                var clicked_window: ?win32.HWND = null;

                const desktop_count = if (app.desktop_manager) |dm| dm.getDesktopCount() else blk: {
                    break :blk @max(app.tiling_manager.getWorkspaceCount(), 1);
                };
                const display_count = @max(desktop_count, app.tiling_manager.getWorkspaceCount());

                var ws_i: usize = 0;
                while (ws_i < display_count) : (ws_i += 1) {
                    if (ws_i >= app.tiling_manager.workspaces.items.len) break;
                    const ws = &app.tiling_manager.workspaces.items[ws_i];
                    const has_windows = ws.columns.items.len > 0;

                    const ws_w = if (has_windows)
                        @as(i32, @intCast(ws.columns.items.len)) * (icon_size + padding) + ws_pad * 2
                    else
                        icon_size + ws_pad * 2;
                    const ws_h = icon_size + ws_pad * 2;

                    const ws_left = curr_x;
                    const ws_top = curr_y;
                    const ws_right = curr_x + ws_w;
                    const ws_bottom = curr_y + ws_h;

                    if (x >= ws_left and x < ws_right and y >= ws_top and y < ws_bottom) {
                        clicked_ws = ws_i;

                        var icon_x: i32 = curr_x + ws_pad;
                        for (ws.columns.items) |col| {
                            const icon_right = icon_x + icon_size;
                            const icon_bottom = curr_y + ws_pad + icon_size;
                            if (x >= icon_x and x < icon_right and y >= curr_y + ws_pad and y < icon_bottom) {
                                clicked_window = col.window.hwnd;
                                break;
                            }
                            icon_x += icon_size + padding;
                        }
                        break;
                    }

                    curr_x += ws_w + ws_margin;
                    var rect_check: win32.RECT = undefined;
                    _ = win32.GetClientRect(hwnd, &rect_check);
                    const ww = rect_check.right - rect_check.left;
                    if (curr_x + ws_w > ww - padding) {
                        curr_x = padding;
                        curr_y += ws_h + ws_margin;
                    }
                }

                if (clicked_window) |hw| {
                    var title_buf: [256:0]u8 = std.mem.zeroes([256:0]u8);
                    _ = win32.GetWindowTextA(hw, &title_buf, @intCast(title_buf.len));
                    std.log.scoped(.App).info("点击窗口: 0x{X} \"{s}\"", .{ @intFromPtr(hw), &title_buf });

                    var found_ws: ?usize = null;
                    var found_col: ?usize = null;
                    for (app.tiling_manager.workspaces.items, 0..) |*ws, ws_idx| {
                        if (ws.findColumn(hw)) |col_idx| {
                            found_ws = ws_idx;
                            found_col = col_idx;
                            break;
                        }
                    }

                    if (found_ws) |ws_idx| {
                        if (found_col) |col_idx| {
                            if (ws_idx != app.tiling_manager.current) {
                                if (app.desktop_manager) |dm| {
                                    var count = dm.getDesktopCount();
                                    while (ws_idx >= count) : (count += 1) {
                                        std.log.scoped(.App).info("创建新桌面 {d}", .{count + 1});
                                        dm.createNewDesktop() catch {};
                                    }
                                    if (ws_idx < count) {
                                        dm.switchToDesktopByIndex(ws_idx) catch {};
                                    }
                                }
                                app.tiling_manager.current = ws_idx;
                            }

                            const workspace = app.tiling_manager.ws();
                            workspace.focused = col_idx;
                            _ = win32.ShowWindow(hw, win32.SW_RESTORE);

                            var old_lock_timeout: u32 = 0;
                            _ = win32.SystemParametersInfoA(win32.SPI_GETFOREGROUNDLOCKTIMEOUT, 0, @ptrCast(&old_lock_timeout), .{});
                            _ = win32.SystemParametersInfoA(win32.SPI_SETFOREGROUNDLOCKTIMEOUT, 0, null, win32.SPIF_SENDCHANGE);
                            tiling.Manager.bypassForegroundLock();
                            _ = win32.BringWindowToTop(hw);

                            if (app.desktop_manager) |dm| {
                                if (dm.appViewCollection) |collection| {
                                    var view: ?*virtual_desktop.IApplicationView = null;
                                    if (collection.GetViewForHwnd(hw, @ptrCast(&view)) == 0 and view != null) {
                                        _ = view.?.SetFocus();
                                        _ = view.?.Release();
                                    }
                                }
                            }

                            tiling.Manager.restoreForegroundLock();
                            _ = win32.SystemParametersInfoA(win32.SPI_SETFOREGROUNDLOCKTIMEOUT, old_lock_timeout, null, win32.SPIF_SENDCHANGE);

                            app.tiling_manager.arrange();
                            _ = win32.InvalidateRect(hwnd, null, 1);
                        }
                    }
                } else if (clicked_ws) |ws_idx| {
                    std.log.scoped(.App).info("点击工作区: {d}", .{ws_idx});
                    if (app.desktop_manager) |dm| {
                        var count = dm.getDesktopCount();
                        while (ws_idx >= count) : (count += 1) {
                            std.log.scoped(.App).info("创建新桌面 {d}", .{count + 1});
                            dm.createNewDesktop() catch |err| {
                                std.log.scoped(.App).err("创建桌面失败: {}", .{err});
                                break;
                            };
                        }

                        if (ws_idx < count) {
                            dm.switchToDesktopByIndex(ws_idx) catch |err| {
                                std.log.scoped(.App).err("切换桌面失败: {}", .{err});
                            };
                        }
                    }
                    app.syncWindowsFromViews();
                    app.tiling_manager.switchWorkspace(ws_idx) catch |err| {
                        std.log.scoped(.App).err("切换工作区失败: {}", .{err});
                    };
                    app.tiling_manager.activateFocused();
                    _ = win32.InvalidateRect(hwnd, null, 1);
                }
            }

            return 0;
        },
        win32.WM_DESTROY => {
            if (g_d2d) |*d2d_ctx| d2d_ctx.deinit();
            g_d2d = null;
            ui.app_bar.unregister(hwnd);
            win32.PostQuitMessage(0);
            return 0;
        },
        else => {},
    }
    return win32.DefWindowProcA(hwnd, msg, wparam, lparam);
}

fn createAppBarWindow(hinstance: win32.HINSTANCE) !win32.HWND {
    const window_class = "niri4winAppBar";

    var wc: win32.WNDCLASSEXA = undefined;
    wc.cbSize = @sizeOf(win32.WNDCLASSEXA);
    wc.style = .{ .HREDRAW = 1, .VREDRAW = 1 };
    wc.lpfnWndProc = windowProc;
    wc.cbClsExtra = 0;
    wc.cbWndExtra = 0;
    wc.hInstance = hinstance;
    wc.hIcon = null;
    wc.hCursor = win32.LoadCursorW(null, win32.IDC_ARROW);
    wc.hbrBackground = null;
    wc.lpszMenuName = null;
    wc.lpszClassName = window_class;
    wc.hIconSm = null;

    if (win32.RegisterClassExA(&wc) == 0) {
        return error.RegisterClassFailed;
    }

    const hwnd = win32.CreateWindowExA(
        .{ .TOOLWINDOW = 1, .TOPMOST = 1, .NOACTIVATE = 1, .NOREDIRECTIONBITMAP = 1 },
        window_class,
        "Niri Window",
        .{ .POPUP = 1, .CLIPCHILDREN = 1, .CLIPSIBLINGS = 1 },
        0,
        0,
        0,
        0,
        null,
        null,
        hinstance,
        null,
    );

    if (hwnd == null) {
        return error.CreateWindowFailed;
    }
    const hwnd_ptr = hwnd.?;

    // ShowWindow 延迟到 D2D 初始化后执行，避免白屏闪烁
    // 自绘 acrylic，不再使用 DWM ExtendFrameIntoClientArea
    // const DWMWA_USE_IMMERSIVE_DARK_MODE: win32.DWMWINDOWATTRIBUTE = @enumFromInt(20);
    // const DWMWA_SYSTEMBACKDROP_TYPE: win32.DWMWINDOWATTRIBUTE = @enumFromInt(38);
    // var dark_mode: i32 = 1;
    // _ = win32.DwmSetWindowAttribute(hwnd_ptr, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark_mode, @sizeOf(i32));
    // var backdrop_type: i32 = 3;
    // _ = win32.DwmSetWindowAttribute(hwnd_ptr, DWMWA_SYSTEMBACKDROP_TYPE, &backdrop_type, @sizeOf(i32));

    if (!ui.app_bar.register(hwnd_ptr, config.getAppBarHeight(), win32.ABE_TOP)) {
        return error.RegisterAppBarFailed;
    }

    return hwnd_ptr;
}
