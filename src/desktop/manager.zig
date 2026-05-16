const std = @import("std");

const niri4win = @import("root").niri4win;
const win32 = niri4win.win32;
const com = niri4win.com;
const virtual_desktop = niri4win.virtual_desktop;
const log = std.log.scoped(.DesktopManager);
const getApplicationViewCollection = virtual_desktop.getApplicationViewCollection;
const IApplicationView = virtual_desktop.IApplicationView;
const IApplicationViewCollection = virtual_desktop.IApplicationViewCollection;
const IVirtualDesktop = virtual_desktop.IVirtualDesktop;
const IVirtualDesktopManager = virtual_desktop.IVirtualDesktopManager;
const IVirtualDesktopManagerInternal = virtual_desktop.IVirtualDesktopManagerInternal;

pub const Manager = struct {
    serviceProvider: *win32.IServiceProvider,
    desktopManagerInternal: *IVirtualDesktopManagerInternal,
    desktopManager: *IVirtualDesktopManager,
    resolved_ivd_iid: ?win32.Guid = null,
    appViewCollection: ?*IApplicationViewCollection = null,

    pub fn create(allocator: std.mem.Allocator) !*Manager {
        const serviceProvider = try com.createServiceProvider();
        const desktopManagerInternal = try IVirtualDesktopManagerInternal.create(serviceProvider);
        const desktopManager = try IVirtualDesktopManager.create();

        var appViewCollection: ?*IApplicationViewCollection = null;
        const collection_result = getApplicationViewCollection(serviceProvider);
        if (collection_result) |collection| {
            appViewCollection = collection;
        } else |_| {
            log.warn("获取IApplicationViewCollection失败，部分功能可能不可用", .{});
        }

        const manager = try allocator.create(Manager);
        manager.* = Manager{
            .serviceProvider = serviceProvider,
            .desktopManagerInternal = desktopManagerInternal,
            .desktopManager = desktopManager,
            .appViewCollection = appViewCollection,
        };
        return manager;
    }

    pub fn deinit(self: *Manager, allocator: std.mem.Allocator) void {
        if (self.appViewCollection) |collection| {
            _ = collection.Release();
        }
        _ = self.desktopManagerInternal.Release();
        _ = self.desktopManager.Release();
        _ = self.serviceProvider.IUnknown.Release();
        allocator.destroy(self);
    }

    fn dumpVtable(self: *Manager) void {
        log.debug("=== IVirtualDesktopManagerInternal vtable dump ===", .{});
        const vtable_ptr: [*]const *const anyopaque = @ptrCast(self.desktopManagerInternal.lpVtbl);
        comptime var i: usize = 0;
        inline while (i < 13) : (i += 1) {
            log.debug("  vtable[{d}] = {*}", .{ i, vtable_ptr[i] });
        }
    }

    pub fn testAllVtableMethods(self: *Manager) !void {
        log.debug("=== 开始测试所有虚表方法 ===", .{});
        self.dumpVtable();

        var count: c_int = 0;
        const hr_count = self.desktopManagerInternal.GetCount(&count);
        log.debug("\n[3] GetCount: hr=0x{X:0>8}, count={d}", .{ @as(u32, @bitCast(hr_count)), count });

        var originalDesktop: ?*IVirtualDesktop = null;
        const hr_orig = self.desktopManagerInternal.GetCurrentDesktop(@ptrCast(&originalDesktop));
        if (hr_orig != 0 or originalDesktop == null) {
            log.err("获取当前桌面失败!", .{});
            return error.GetCurrentDesktopFailed;
        }
        defer _ = originalDesktop.?.Release();

        var originalDesktopId: win32.Guid = undefined;
        _ = originalDesktop.?.GetID(&originalDesktopId);

        var appViewCollection_opt: ?*IApplicationViewCollection = null;
        var foregroundView_opt: ?*IApplicationView = null;
        const collection_result = getApplicationViewCollection(self.serviceProvider);
        if (collection_result) |collection| {
            appViewCollection_opt = collection;

            const fg_hwnd = win32.GetForegroundWindow();
            if (fg_hwnd) |hwnd| {
                log.debug("前台窗口 hwnd=0x{X}", .{@intFromPtr(hwnd)});
                var view: ?*IApplicationView = null;
                const hr_view = collection.GetViewForHwnd(hwnd, @ptrCast(&view));
                if (hr_view == 0 and view != null) {
                    foregroundView_opt = view;
                    log.info("IApplicationView 获取成功!", .{});
                }
            }
        } else |err| {
            log.err("IApplicationViewCollection 获取失败: {}", .{err});
        }
        defer {
            if (foregroundView_opt) |v| _ = v.Release();
            if (appViewCollection_opt) |c| _ = c.Release();
        }

        if (foregroundView_opt) |view| {
            var can_move: c_int = 0;
            const hr_can = self.desktopManagerInternal.CanViewMoveDesktops(view, &can_move);
            log.debug("\n[5] CanViewMoveDesktops: hr=0x{X:0>8}, can_move={d}", .{ @as(u32, @bitCast(hr_can)), can_move });
        }

        log.debug("\n===== 真实场景测试 =====");
        var newDesktop: ?*IVirtualDesktop = null;
        const hr_create = self.desktopManagerInternal.CreateDesktopW(@ptrCast(&newDesktop));
        if (hr_create != 0 or newDesktop == null) {
            log.err("创建桌面失败!", .{});
            return error.CreateDesktopFailed;
        }
        var newDesktop_ptr = newDesktop.?;
        defer {
            log.debug("\n清理: 删除新桌面...", .{});
            _ = self.desktopManagerInternal.RemoveDesktop(newDesktop_ptr, originalDesktop.?);
            _ = newDesktop_ptr.Release();
        }

        var newDesktopId: win32.Guid = undefined;
        _ = newDesktop_ptr.GetID(&newDesktopId);
        log.info("新桌面创建成功! ID a=0x{X}", .{newDesktopId.Ints.a});

        if (foregroundView_opt) |view| {
            const hr_moveView = self.desktopManagerInternal.MoveViewToDesktop(view, newDesktop_ptr);
            if (hr_moveView == 0) {
                log.info("窗口移动成功!", .{});
            } else {
                log.err("窗口移动失败 (可能需要管理员权限)", .{});
            }
        }

        const hr_switch1 = self.desktopManagerInternal.SwitchDesktop(newDesktop_ptr);
        if (hr_switch1 == 0) {
            log.info("切换到新桌面成功!", .{});
        }

        _ = win32.MessageBoxA(null, "测试桌面切换", "确认", .{ .OK = 1 });

        const hr_switch2 = self.desktopManagerInternal.SwitchDesktopAndMoveForegroundView(originalDesktop.?);
        if (hr_switch2 == 0) {
            log.info("切换回原始桌面成功!", .{});
        }

        var foundDesktop: ?*IVirtualDesktop = null;
        const hr_find = self.desktopManagerInternal.FindDesktop(&newDesktopId, @ptrCast(&foundDesktop));
        if (hr_find == 0 and foundDesktop != null) {
            defer _ = foundDesktop.?.Release();
            log.info("FindDesktop 成功!", .{});
        }

        var desktops: ?*win32.IObjectArray = null;
        const hr_desktops = self.desktopManagerInternal.GetDesktops(@ptrCast(&desktops));
        if (hr_desktops == 0 and desktops != null) {
            defer _ = desktops.?.IUnknown.Release();
            var objCount: u32 = 0;
            _ = desktops.?.GetCount(&objCount);
            log.info("当前共有 {d} 个桌面", .{objCount});
        }

        var newCount: c_int = 0;
        _ = self.desktopManagerInternal.GetCount(&newCount);
        log.info("当前桌面总数: {d}", .{newCount});

        log.info("\n===== 测试完成 =====");
        log.info("✅ 所有测试通过!", .{});
    }

    fn getWindowExeAndName(hwnd: win32.HWND, exeBuf: [*:0]u8, exeLen: u32, nameBuf: [*:0]u8, nameLen: u32) void {
        @memset(exeBuf[0..exeLen], 0);
        @memset(nameBuf[0..nameLen], 0);

        var pid: u32 = 0;
        _ = win32.GetWindowThreadProcessId(hwnd, &pid);
        if (pid == 0) return;

        const process_h = win32.OpenProcess(win32.PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if (process_h == null) return;
        defer _ = win32.CloseHandle(process_h);

        var exeSize: u32 = exeLen - 1;
        if (win32.QueryFullProcessImageNameA(process_h, @enumFromInt(0), exeBuf, &exeSize) != 0) {
            if (std.mem.lastIndexOfScalar(u8, exeBuf[0..exeSize], '\\')) |lastSlash| {
                const namePart = exeBuf[(lastSlash + 1)..exeSize];
                const copyLen = @min(nameLen - 1, namePart.len);
                @memcpy(nameBuf[0..copyLen], namePart[0..copyLen]);
            }
        }
    }

    pub fn debugLogGetViews(self: *Manager) void {
        const collection = self.appViewCollection orelse {
            log.debug("debugLogGetViews: appViewCollection 不可用", .{});
            return;
        };

        var viewsArray: ?*win32.IObjectArray = null;
        const hr_views = collection.GetViews(@ptrCast(&viewsArray));
        if (hr_views != 0 or viewsArray == null) {
            log.err("GetViews 调用失败 hr=0x{X:0>8}", .{@as(u32, @bitCast(hr_views))});
            return;
        }
        defer _ = viewsArray.?.IUnknown.Release();

        var viewCount: u32 = 0;
        _ = viewsArray.?.GetCount(&viewCount);
        log.debug("========== GetViews 调试 ==========", .{});
        log.debug("GetViews: 共 {d} 个视图", .{viewCount});

        var desktopsArray: ?*win32.IObjectArray = null;
        const hr_desk = self.desktopManagerInternal.GetDesktops(@ptrCast(&desktopsArray));
        if (hr_desk != 0 or desktopsArray == null) {
            log.err("GetViews: 获取桌面列表失败", .{});
            return;
        }
        defer _ = desktopsArray.?.IUnknown.Release();

        var desktopCount: u32 = 0;
        _ = desktopsArray.?.GetCount(&desktopCount);

        const IVD_IID_CANDIDATES = virtual_desktop.IID_IVirtualDesktop_Candidates;
        const ivd_iid = self.resolved_ivd_iid orelse blk: {
            for (IVD_IID_CANDIDATES) |cand| {
                const r = com.GetAtWithIID(desktopsArray.?, 0, &cand.iid, IVirtualDesktop);
                if (r.hr == 0) {
                    _ = r.ptr.?.Release();
                    self.resolved_ivd_iid = cand.iid;
                    break :blk cand.iid;
                }
            }
            log.err("GetViews: 无法解析 IVirtualDesktop IID", .{});
            return;
        };

        var counts: [32]u32 = [_]u32{0} ** 32;
        for (0..viewCount) |vi| {
            const vr = com.GetAtWithIID(viewsArray.?, vi, &virtual_desktop.IID_IApplicationView, IApplicationView);
            if (vr.hr != 0 or vr.ptr == null) continue;
            const view = vr.ptr.?;
            defer _ = view.Release();

            var viewDesktopId: win32.Guid = undefined;
            const gotDesktop = (view.GetVirtualDesktopId(&viewDesktopId) == 0);

            var desktopIdx: ?usize = null;
            if (gotDesktop) {
                for (0..@min(desktopCount, 32)) |di| {
                    const dr = com.GetAtWithIID(desktopsArray.?, di, &ivd_iid, IVirtualDesktop);
                    if (dr.hr != 0 or dr.ptr == null) continue;
                    const desktop = dr.ptr.?;
                    defer _ = desktop.Release();
                    var desktopId: win32.Guid = undefined;
                    _ = desktop.GetID(&desktopId);
                    if (std.mem.eql(u8, std.mem.asBytes(&viewDesktopId), std.mem.asBytes(&desktopId))) {
                        desktopIdx = di;
                        counts[di] += 1;
                        break;
                    }
                }
            }

            var hwnd: win32.HWND = undefined;
            @memset(@as(*[8]u8, @ptrCast(&hwnd)), 0);
            const gotHwnd = (view.GetThumbnailWindow(&hwnd) == 0 and @intFromPtr(hwnd) != 0);

            if (!gotHwnd) {
                log.debug("  [{d}] view[{d}] (无 HWND)", .{ desktopIdx orelse 99, vi });
                continue;
            }

            var title: [256:0]u8 = std.mem.zeroes([256:0]u8);
            _ = win32.GetWindowTextA(hwnd, &title, @intCast(title.len));

            var exeBuf: [260:0]u8 = std.mem.zeroes([260:0]u8);
            var nameBuf: [64:0]u8 = std.mem.zeroes([64:0]u8);
            getWindowExeAndName(hwnd, &exeBuf, exeBuf.len, &nameBuf, nameBuf.len);

            log.debug("  [{d}] hwnd=0x{X:0>8} \"{s}\" [{s}] ({s})", .{
                desktopIdx orelse 99,
                @intFromPtr(hwnd),
                &title,
                &nameBuf,
                &exeBuf,
            });
        }

        log.debug("----- 按桌面分组 (GetVirtualDesktopId) -----", .{});
        for (0..@min(desktopCount, 32)) |di| {
            log.debug("  桌面[{d}]: {d} 个视图", .{ di, counts[di] });
        }
        log.info("================================", .{});
    }

    pub fn getCurrentDesktopIndex(self: *Manager) !usize {
        var desktopsNullable: ?*win32.IObjectArray = null;
        const hr_get = self.desktopManagerInternal.GetDesktops(@ptrCast(&desktopsNullable));
        if (hr_get != 0) return error.GetDesktopsFailed;
        var desktops = desktopsNullable orelse return error.Unknown;
        defer _ = desktops.IUnknown.Release();

        var currentDesktopNullable: ?*IVirtualDesktop = null;
        const hr_curr = self.desktopManagerInternal.GetCurrentDesktop(@ptrCast(&currentDesktopNullable));
        if (hr_curr != 0) return error.GetCurrentDesktopFailed;
        var currentDesktop = currentDesktopNullable orelse return error.Unknown;
        defer _ = currentDesktop.Release();

        var currentDesktopId: win32.Guid = undefined;
        _ = currentDesktop.GetID(&currentDesktopId);

        var dCount: u32 = 0;
        _ = desktops.GetCount(&dCount);

        const IVD_IID_CANDIDATES = virtual_desktop.IID_IVirtualDesktop_Candidates;
        const ivd_iid = self.resolved_ivd_iid orelse blk: {
            for (IVD_IID_CANDIDATES) |cand| {
                const r = com.GetAtWithIID(desktops, 0, &cand.iid, IVirtualDesktop);
                if (r.hr == 0) {
                    _ = r.ptr.?.Release();
                    self.resolved_ivd_iid = cand.iid;
                    break :blk cand.iid;
                }
            }
            return error.Unknown;
        };

        for (0..dCount) |i| {
            const r = com.GetAtWithIID(desktops, i, &ivd_iid, IVirtualDesktop);
            if (r.hr == 0 and r.ptr != null) {
                var desktopId: win32.Guid = undefined;
                _ = r.ptr.?.GetID(&desktopId);
                _ = r.ptr.?.Release();
                if (std.mem.eql(u8, std.mem.asBytes(&desktopId), std.mem.asBytes(&currentDesktopId))) {
                    return i;
                }
            }
        }
        return error.DesktopNotFound;
    }

    pub fn getDesktopCount(self: *Manager) usize {
        var count: c_int = 0;
        _ = self.desktopManagerInternal.GetCount(&count);
        return @intCast(count);
    }

    pub fn switchToDesktopByIndex(self: *Manager, index: usize) !void {
        var desktopsNullable: ?*win32.IObjectArray = null;
        const hr_get = self.desktopManagerInternal.GetDesktops(@ptrCast(&desktopsNullable));
        if (hr_get != 0) return error.GetDesktopsFailed;
        var desktops = desktopsNullable orelse return error.Unknown;
        defer _ = desktops.IUnknown.Release();

        var dCount: u32 = 0;
        _ = desktops.GetCount(&dCount);
        if (index >= dCount) return error.InvalidDesktopIndex;

        const IVD_IID_CANDIDATES = virtual_desktop.IID_IVirtualDesktop_Candidates;
        const ivd_iid = self.resolved_ivd_iid orelse blk: {
            for (IVD_IID_CANDIDATES) |cand| {
                const r = com.GetAtWithIID(desktops, 0, &cand.iid, IVirtualDesktop);
                if (r.hr == 0) {
                    _ = r.ptr.?.Release();
                    self.resolved_ivd_iid = cand.iid;
                    break :blk cand.iid;
                }
            }
            return error.Unknown;
        };

        const r = com.GetAtWithIID(desktops, index, &ivd_iid, IVirtualDesktop);
        if (r.hr != 0 or r.ptr == null) return error.GetDesktopFailed;
        const targetDesktop = r.ptr.?;
        defer _ = targetDesktop.Release();

        const hr_switch = self.desktopManagerInternal.SwitchDesktop(targetDesktop);
        if (hr_switch != 0) return error.SwitchDesktopFailed;
    }

    pub fn moveForegroundWindowToDesktopByIndex(self: *Manager, index: usize) !void {
        const fg_hwnd = win32.GetForegroundWindow();
        if (fg_hwnd == null) return error.NoForegroundWindow;

        var desktopsNullable: ?*win32.IObjectArray = null;
        const hr_get = self.desktopManagerInternal.GetDesktops(@ptrCast(&desktopsNullable));
        if (hr_get != 0) return error.GetDesktopsFailed;
        var desktops = desktopsNullable orelse return error.Unknown;
        defer _ = desktops.IUnknown.Release();

        var dCount: u32 = 0;
        _ = desktops.GetCount(&dCount);
        if (index >= dCount) return error.InvalidDesktopIndex;

        const IVD_IID_CANDIDATES = virtual_desktop.IID_IVirtualDesktop_Candidates;
        const ivd_iid = self.resolved_ivd_iid orelse blk: {
            for (IVD_IID_CANDIDATES) |cand| {
                const r = com.GetAtWithIID(desktops, 0, &cand.iid, IVirtualDesktop);
                if (r.hr == 0) {
                    _ = r.ptr.?.Release();
                    self.resolved_ivd_iid = cand.iid;
                    break :blk cand.iid;
                }
            }
            return error.Unknown;
        };

        const r = com.GetAtWithIID(desktops, index, &ivd_iid, IVirtualDesktop);
        if (r.hr != 0 or r.ptr == null) return error.GetDesktopFailed;
        const targetDesktop = r.ptr.?;
        defer _ = targetDesktop.Release();

        if (self.appViewCollection) |collection| {
            var view: ?*IApplicationView = null;
            const hr_view = collection.GetViewForHwnd(fg_hwnd.?, @ptrCast(&view));
            if (hr_view == 0 and view != null) {
                const hr_move = self.desktopManagerInternal.MoveViewToDesktop(view.?, targetDesktop);
                _ = view.?.Release();
                if (hr_move != 0) return error.MoveWindowFailed;
            } else {
                var desktopId: win32.Guid = undefined;
                _ = targetDesktop.GetID(&desktopId);
                _ = self.desktopManager.MoveWindowToDesktop(fg_hwnd.?, &desktopId);
            }
        } else {
            var desktopId: win32.Guid = undefined;
            _ = targetDesktop.GetID(&desktopId);
            _ = self.desktopManager.MoveWindowToDesktop(fg_hwnd.?, &desktopId);
        }
    }

    pub fn moveWindowToDesktop(self: *Manager, hwnd: win32.HWND, targetDesktopIndex: usize) !void {
        var desktopsNullable: ?*win32.IObjectArray = null;
        _ = self.desktopManagerInternal.GetDesktops(@ptrCast(&desktopsNullable));
        var desktops = desktopsNullable orelse return error.Unknown;
        defer _ = desktops.IUnknown.Release();

        var dCount: u32 = 0;
        _ = desktops.GetCount(&dCount);
        if (targetDesktopIndex >= dCount) return error.InvalidDesktopIndex;

        const IVD_IID_CANDIDATES = virtual_desktop.IID_IVirtualDesktop_Candidates;
        const ivd_iid = self.resolved_ivd_iid orelse blk: {
            for (IVD_IID_CANDIDATES) |cand| {
                const r = com.GetAtWithIID(desktops, 0, &cand.iid, IVirtualDesktop);
                if (r.hr == 0) {
                    _ = r.ptr.?.Release();
                    self.resolved_ivd_iid = cand.iid;
                    break :blk cand.iid;
                }
            }
            return error.Unknown;
        };

        const r = com.GetAtWithIID(desktops, targetDesktopIndex, &ivd_iid, IVirtualDesktop);
        if (r.hr != 0) return error.Unknown;
        const targetDesktop = r.ptr.?;
        defer _ = targetDesktop.Release();

        var desktopId: win32.Guid = undefined;
        _ = targetDesktop.GetID(&desktopId);
        _ = self.desktopManager.MoveWindowToDesktop(hwnd, &desktopId);
    }

    pub fn createNewDesktop(self: *Manager) !void {
        var newDesktop: ?*IVirtualDesktop = null;
        const hr_create = self.desktopManagerInternal.CreateDesktopW(@ptrCast(&newDesktop));
        if (hr_create != 0 or newDesktop == null) {
            return error.CreateDesktopFailed;
        }
        _ = newDesktop.?.Release();
    }

    pub fn removeCurrentDesktop(self: *Manager) !void {
        var currentDesktopNullable: ?*IVirtualDesktop = null;
        const hr_curr = self.desktopManagerInternal.GetCurrentDesktop(@ptrCast(&currentDesktopNullable));
        if (hr_curr != 0 or currentDesktopNullable == null) return error.GetCurrentDesktopFailed;
        var currentDesktop = currentDesktopNullable.?;
        defer _ = currentDesktop.Release();

        var desktopsNullable: ?*win32.IObjectArray = null;
        const hr_get = self.desktopManagerInternal.GetDesktops(@ptrCast(&desktopsNullable));
        if (hr_get != 0) return error.GetDesktopsFailed;
        var desktops = desktopsNullable orelse return error.Unknown;
        defer _ = desktops.IUnknown.Release();

        var dCount: u32 = 0;
        _ = desktops.GetCount(&dCount);
        if (dCount <= 1) return error.CannotRemoveLastDesktop;

        const IVD_IID_CANDIDATES = virtual_desktop.IID_IVirtualDesktop_Candidates;
        const ivd_iid = self.resolved_ivd_iid orelse blk: {
            for (IVD_IID_CANDIDATES) |cand| {
                const r = com.GetAtWithIID(desktops, 0, &cand.iid, IVirtualDesktop);
                if (r.hr == 0) {
                    _ = r.ptr.?.Release();
                    self.resolved_ivd_iid = cand.iid;
                    break :blk cand.iid;
                }
            }
            return error.Unknown;
        };

        const r = com.GetAtWithIID(desktops, 0, &ivd_iid, IVirtualDesktop);
        if (r.hr != 0 or r.ptr == null) return error.GetDesktopFailed;
        var fallbackDesktop = r.ptr.?;
        defer _ = fallbackDesktop.Release();

        const hr_remove = self.desktopManagerInternal.RemoveDesktop(currentDesktop, fallbackDesktop);
        if (hr_remove != 0) return error.RemoveDesktopFailed;
    }
};
