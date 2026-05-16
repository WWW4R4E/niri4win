const std = @import("std");

const niri4win = @import("root").niri4win;
const win32 = niri4win.win32;

const TaskWindowInternal = niri4win.ui.task_bar.TaskWindowInternal;

const IApplicationView = niri4win.virtual_desktop.IApplicationView;
const IApplicationViewCollection = niri4win.virtual_desktop.IApplicationViewCollection;

const DEFAULT_WIDTH_WEIGHT: f32 = 1.0;

var g_fullscreen_minimize_others: bool = true;

pub fn setFullscreenMinimizeOthers(value: bool) void {
    g_fullscreen_minimize_others = value;
}

pub fn getFullscreenMinimizeOthers() bool {
    return g_fullscreen_minimize_others;
}

fn getOriginalRect(hwnd: win32.HWND) ?win32.RECT {
    var placement: win32.WINDOWPLACEMENT = undefined;
    placement.length = @sizeOf(win32.WINDOWPLACEMENT);
    if (win32.GetWindowPlacement(hwnd, &placement) != 0) {
        return placement.rcNormalPosition;
    }
    return null;
}

fn getInitialWidth(hwnd: win32.HWND) i32 {
    var placement: win32.WINDOWPLACEMENT = undefined;
    placement.length = @sizeOf(win32.WINDOWPLACEMENT);
    if (win32.GetWindowPlacement(hwnd, &placement) != 0) {
        return placement.rcNormalPosition.right - placement.rcNormalPosition.left;
    }
    return 640;
}

const ColumnEntry = struct {
    window: TaskWindowInternal,
    width_weight: f32 = DEFAULT_WIDTH_WEIGHT,
    is_fullscreen: bool = false,
    original_rect: ?win32.RECT = null,
    is_dragging: bool = false,
    user_fixed_width: ?i32 = null,

    pub fn create(window: TaskWindowInternal) ColumnEntry {
        return ColumnEntry{
            .window = window,
            .width_weight = DEFAULT_WIDTH_WEIGHT,
            .is_fullscreen = false,
            .original_rect = getOriginalRect(window.hwnd),
            .is_dragging = false,
            .user_fixed_width = getInitialWidth(window.hwnd),
        };
    }
};

const Workspace = struct {
    allocator: std.mem.Allocator,
    columns: std.ArrayList(ColumnEntry),
    focused: usize = 0,

    pub fn focusedHwnd(self: *const Workspace) ?win32.HWND {
        if (self.columns.items.len == 0) return null;
        if (self.focused >= self.columns.items.len) return null;
        return self.columns.items[self.focused].window.hwnd;
    }

    pub fn findColumn(self: *const Workspace, hwnd: win32.HWND) ?usize {
        for (self.columns.items, 0..) |col, i| {
            if (col.window.hwnd == hwnd) return i;
        }
        return null;
    }

    pub fn init(allocator: std.mem.Allocator) Workspace {
        return Workspace{
            .allocator = allocator,
            .columns = std.ArrayList(ColumnEntry).empty,
            .focused = 0,
        };
    }

    pub fn deinit(self: *Workspace) void {
        self.columns.deinit(self.allocator);
    }
};

const PendingWindowUpdate = struct {
    hwnd: win32.HWND,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

pub const Manager = struct {
    allocator: std.mem.Allocator,
    workspaces: std.ArrayList(Workspace),
    current: usize = 0,
    pending_updates: std.ArrayList(PendingWindowUpdate),
    is_dragging_window: bool = false,
    dragged_hwnd: ?win32.HWND = null,
    is_initialized: bool = false,
    appViewCollection: ?*IApplicationViewCollection = null,

    pub fn init(allocator: std.mem.Allocator) Manager {
        return Manager{
            .allocator = allocator,
            .workspaces = std.ArrayList(Workspace).empty,
            .pending_updates = std.ArrayList(PendingWindowUpdate).empty,
        };
    }

    pub fn deinit(self: *Manager) void {
        for (self.workspaces.items) |*iter_ws| {
            for (iter_ws.columns.items) |*col| {
                const hwnd = col.window.hwnd;
                if (win32.IsIconic(hwnd) != 0) {
                    continue;
                }
                if (col.original_rect) |rect| {
                    // const transparent_color: win32.COLORREF = 0x00000000;
                    // _ = win32.DwmSetWindowAttribute(
                    //     hwnd,
                    //     win32.DWMWINDOWATTRIBUTE.BORDER_COLOR,
                    //     &transparent_color,
                    //     @sizeOf(win32.COLORREF),
                    // );
                    _ = win32.SetWindowPos(
                        hwnd,
                        null,
                        rect.left,
                        rect.top,
                        rect.right - rect.left,
                        rect.bottom - rect.top,
                        .{ .NOSIZE = 1, .NOZORDER = 1, .SHOWWINDOW = 1 },
                    );
                }
            }
        }

        for (self.workspaces.items) |*iter_ws| {
            iter_ws.deinit();
        }
        self.workspaces.deinit(self.allocator);
        self.pending_updates.deinit(self.allocator);
    }

    pub fn ensureWorkspaceCount(self: *Manager, count: usize) !void {
        while (self.workspaces.items.len < count) {
            const wksp = Workspace.init(self.allocator);
            try self.workspaces.append(self.allocator, wksp);
        }
    }

    pub fn markInitialized(self: *Manager) void {
        self.is_initialized = true;
    }

    pub fn ws(self: *Manager) *Workspace {
        return &self.workspaces.items[self.current];
    }

    fn wsConst(self: *const Manager) *const Workspace {
        return &self.workspaces.items[self.current];
    }

    pub fn startDragging(self: *Manager, hwnd: win32.HWND) void {
        self.is_dragging_window = true;
        self.dragged_hwnd = hwnd;

        const workspace = self.ws();
        if (workspace.findColumn(hwnd)) |idx| {
            workspace.columns.items[idx].is_dragging = true;
        }
    }

    pub fn endDragging(self: *Manager) void {
        if (self.dragged_hwnd) |hwnd| {
            const workspace = self.ws();
            if (workspace.findColumn(hwnd)) |idx| {
                workspace.columns.items[idx].is_dragging = false;
                workspace.focused = idx;

                var rect: win32.RECT = undefined;
                if (win32.GetWindowRect(hwnd, &rect) != 0) {
                    const window_width = rect.right - rect.left;
                    workspace.columns.items[idx].user_fixed_width = window_width;
                }
            }
        }

        self.is_dragging_window = false;
        self.dragged_hwnd = null;
        self.arrange();
    }

    fn addPendingUpdate(self: *Manager, hwnd: win32.HWND, x: i32, y: i32, width: i32, height: i32) !void {
        try self.pending_updates.append(self.allocator, .{
            .hwnd = hwnd,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        });
    }

    fn applyPendingUpdates(self: *Manager) void {
        for (self.pending_updates.items) |*update| {
            var current_rect: win32.RECT = undefined;
            if (win32.GetWindowRect(update.hwnd, &current_rect) != 0) {
                if (current_rect.left == update.x and
                    current_rect.top == update.y and
                    (current_rect.right - current_rect.left) == update.width and
                    (current_rect.bottom - current_rect.top) == update.height)
                {
                    continue;
                }
            }
            if (win32.IsIconic(update.hwnd) != 0) {
                _ = win32.ShowWindow(update.hwnd, win32.SW_RESTORE);
            }
            _ = win32.SetWindowPos(
                update.hwnd,
                null,
                update.x,
                update.y,
                update.width,
                update.height,
                .{ .NOZORDER = 1, .NOACTIVATE = 1, .NOSENDCHANGING = 1 },
            );
        }
        self.pending_updates.clearRetainingCapacity();
    }

    pub fn addWindow(self: *Manager, hwnd: win32.HWND) !void {
        try self.addWindowWithoutArrange(hwnd);
        self.arrange();
    }

    pub fn addWindowToWorkspace(self: *Manager, hwnd: win32.HWND, ws_idx: usize) !bool {
        if (ws_idx >= self.workspaces.items.len) return false;
        const workspace = &self.workspaces.items[ws_idx];
        if (workspace.findColumn(hwnd) != null) return false;

        var window: TaskWindowInternal = undefined;
        window.hwnd = hwnd;

        var win_title: [256:0]u8 = std.mem.zeroes([256:0]u8);
        _ = win32.GetWindowTextA(hwnd, @ptrCast(&win_title), win_title.len);
        window.title = win_title;

        window.icon = null;

        if (self.appViewCollection) |collection| {
            var view: ?*IApplicationView = null;
            if (collection.GetViewForHwnd(hwnd, @ptrCast(&view)) == 0 and view != null) {
                var aumid: [*c]u16 = undefined;
                if (view.?.GetAppUserModelId(@ptrCast(&aumid)) == 0) {
                    window.icon = niri4win.ui.task_bar.getIconFromAumid(@ptrCast(aumid));
                    win32.CoTaskMemFree(@ptrCast(aumid));
                }
                _ = view.?.Release();
            }
        }

        if (window.icon == null) {
            window.icon = niri4win.ui.task_bar.getWindowIcon(hwnd);
        }

        var win_path: [260:0]u8 = std.mem.zeroes([260:0]u8);
        var pid: u32 = 0;
        _ = win32.GetWindowThreadProcessId(hwnd, &pid);
        const process_handle = win32.OpenProcess(win32.PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if (process_handle) |h| {
            var path_len: u32 = 260;
            _ = win32.QueryFullProcessImageNameA(h, win32.PROCESS_NAME_WIN32, @ptrCast(&win_path), &path_len);
            _ = win32.CloseHandle(h);
        }
        window.process_path = win_path;

        if (window.icon == null) {
            window.icon = niri4win.ui.task_bar.extractIconFromPath(@ptrCast(&window.process_path));
        }

        try workspace.columns.append(self.allocator, ColumnEntry.create(window));
        return true;
    }

    pub fn addWindowWithoutArrange(self: *Manager, hwnd: win32.HWND) !void {
        const workspace = self.ws();
        if (workspace.findColumn(hwnd) != null) return;

        var window: TaskWindowInternal = undefined;
        window.hwnd = hwnd;

        var win_title: [256:0]u8 = std.mem.zeroes([256:0]u8);
        _ = win32.GetWindowTextA(hwnd, @ptrCast(&win_title), win_title.len);
        window.title = win_title;

        window.icon = null;

        if (self.appViewCollection) |collection| {
            var view: ?*IApplicationView = null;
            if (collection.GetViewForHwnd(hwnd, @ptrCast(&view)) == 0 and view != null) {
                var aumid: [*c]u16 = undefined;
                if (view.?.GetAppUserModelId(@ptrCast(&aumid)) == 0) {
                    window.icon = niri4win.ui.task_bar.getIconFromAumid(@ptrCast(aumid));
                    win32.CoTaskMemFree(@ptrCast(aumid));
                }
                _ = view.?.Release();
            }
        }

        var win_path: [260:0]u8 = std.mem.zeroes([260:0]u8);
        var pid: u32 = 0;
        _ = win32.GetWindowThreadProcessId(hwnd, &pid);
        const process_handle = win32.OpenProcess(win32.PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if (process_handle) |h| {
            var path_len: u32 = 260;
            _ = win32.QueryFullProcessImageNameA(h, win32.PROCESS_NAME_WIN32, @ptrCast(&win_path), &path_len);
            _ = win32.CloseHandle(h);
        }
        window.process_path = win_path;

        if (window.icon == null) {
            window.icon = niri4win.ui.task_bar.extractIconFromPath(@ptrCast(&window.process_path));
        }

        try workspace.columns.append(self.allocator, ColumnEntry.create(window));
    }

    pub fn removeWindow(self: *Manager, hwnd: win32.HWND) void {
        for (self.workspaces.items) |*ws_item| {
            if (ws_item.findColumn(hwnd)) |idx| {
                _ = ws_item.columns.orderedRemove(idx);
                if (ws_item.focused >= ws_item.columns.items.len and ws_item.columns.items.len > 0) {
                    ws_item.focused = ws_item.columns.items.len - 1;
                }
                break;
            }
        }
        self.arrange();
    }

    pub fn arrange(self: *Manager) void {
        const workspace = self.ws();
        if (workspace.columns.items.len == 0) return;

        var work_area: win32.RECT = undefined;
        _ = win32.SystemParametersInfoA(win32.SPI_GETWORKAREA, 0, &work_area, .{});

        const screen_width = work_area.right - work_area.left;
        const screen_height = work_area.bottom - work_area.top;
        const screen_top = work_area.top;

        std.log.scoped(.Tiling).info("=== arrange start ===", .{});
        std.log.scoped(.Tiling).info("workspace window count: {d}, focus index: {d}", .{ workspace.columns.items.len, workspace.focused });

        for (workspace.columns.items) |*col| {
            if (col.is_fullscreen) {
                _ = win32.ShowWindow(col.window.hwnd, win32.SW_MAXIMIZE);
                return;
            }
        }

        var window_widths = std.ArrayList(i32).empty;
        defer window_widths.deinit(self.allocator);

        for (workspace.columns.items) |*col| {
            window_widths.append(self.allocator, col.user_fixed_width orelse 640) catch {};
        }

        var total_width: i32 = 0;
        for (window_widths.items) |w| {
            total_width += w;
        }

        if (total_width < screen_width) {
            const original_total_width = total_width;
            const scale_factor = @as(f32, @floatFromInt(screen_width)) / @as(f32, @floatFromInt(original_total_width));

            var new_total_width: i32 = 0;
            for (window_widths.items, 0..) |_, i| {
                const new_width = @as(i32, @intFromFloat(@as(f32, @floatFromInt(window_widths.items[i])) * scale_factor));
                window_widths.items[i] = new_width;
                new_total_width += new_width;
            }

            if (new_total_width < screen_width) {
                window_widths.items[0] += screen_width - new_total_width;
                new_total_width = screen_width;
            }

            total_width = new_total_width;
        }

        var left_total_width: i32 = 0;
        for (0..workspace.focused) |i| {
            left_total_width += window_widths.items[i];
        }

        const focused_window_width = window_widths.items[workspace.focused];
        const focused_left = left_total_width;
        const focused_right = focused_left + focused_window_width;

        const max_scroll = @max(0, total_width - screen_width);

        var scroll_offset: i32 = 0;

        if (self.is_initialized) {
            const ideal_scroll = focused_left - @divTrunc(screen_width - focused_window_width, 2);
            scroll_offset = @max(0, @min(ideal_scroll, max_scroll));

            if (focused_right - scroll_offset > screen_width) {
                scroll_offset = focused_right - screen_width;
            }
            if (focused_left - scroll_offset < 0) {
                scroll_offset = focused_left;
            }

            scroll_offset = @max(0, @min(scroll_offset, max_scroll));
        }

        var current_x: i32 = work_area.left - scroll_offset;

        // for (workspace.columns.items) |*col| {
        // const transparent_color: win32.COLORREF = 0x00000000;
        // _ = win32.DwmSetWindowAttribute(
        //     col.window.hwnd,
        //     win32.DWMWINDOWATTRIBUTE.BORDER_COLOR,
        //     &transparent_color,
        //     @sizeOf(win32.COLORREF),
        // );
        // }

        // if (workspace.columns.items.len > 0) {
        // const focused_col = &workspace.columns.items[workspace.focused];
        // const focus_color: win32.COLORREF = 0x000000FF;
        // _ = win32.DwmSetWindowAttribute(
        //     focused_col.window.hwnd,
        //     win32.DWMWINDOWATTRIBUTE.BORDER_COLOR,
        //     &focus_color,
        //     @sizeOf(win32.COLORREF),
        // );
        // }

        self.pending_updates.clearRetainingCapacity();

        for (workspace.columns.items, 0..) |*col, i| {
            const w = window_widths.items[i];
            self.addPendingUpdate(col.window.hwnd, current_x, screen_top, w, screen_height) catch {};
            current_x += w;
        }

        self.applyPendingUpdates();
    }

    pub fn focusColumnLeft(self: *Manager) void {
        const workspace = self.ws();
        if (workspace.columns.items.len <= 1) return;
        if (workspace.focused == 0) return;
        workspace.focused -= 1;
        self.activateFocused();
        self.arrange();
    }

    pub fn focusColumnRight(self: *Manager) void {
        const workspace = self.ws();
        if (workspace.columns.items.len <= 1) return;
        if (workspace.focused >= workspace.columns.items.len - 1) return;
        workspace.focused += 1;
        self.activateFocused();
        self.arrange();
    }

    pub fn focusColumnByIndex(self: *Manager, idx: usize) void {
        const workspace = self.ws();
        if (idx >= workspace.columns.items.len) return;
        workspace.focused = idx;
        self.activateFocused();
        self.arrange();
    }

    pub fn bypassForegroundLock() void {
        const fg_hwnd = win32.GetForegroundWindow();
        const fg_thread = win32.GetWindowThreadProcessId(fg_hwnd, null);
        const my_thread = win32.GetCurrentThreadId();
        if (fg_thread != my_thread) {
            _ = win32.AttachThreadInput(fg_thread, my_thread, 1);
        }
    }

    pub fn restoreForegroundLock() void {
        const fg_hwnd = win32.GetForegroundWindow();
        const fg_thread = win32.GetWindowThreadProcessId(fg_hwnd, null);
        const my_thread = win32.GetCurrentThreadId();
        if (fg_thread != my_thread) {
            _ = win32.AttachThreadInput(fg_thread, my_thread, 0);
        }
    }

    pub fn activateFocused(self: *const Manager) void {
        const hwnd = self.wsConst().focusedHwnd() orelse return;
        _ = win32.ShowWindow(hwnd, win32.SW_SHOWNORMAL);

        var old_lock_timeout: u32 = 0;
        _ = win32.SystemParametersInfoA(win32.SPI_GETFOREGROUNDLOCKTIMEOUT, 0, @ptrCast(&old_lock_timeout), .{});
        _ = win32.SystemParametersInfoA(win32.SPI_SETFOREGROUNDLOCKTIMEOUT, 0, null, win32.SPIF_SENDCHANGE);
        bypassForegroundLock();

        // if (self.appViewCollection) |collection| {
        //     var view: ?*IApplicationView = null;
        //     if (collection.GetViewForHwnd(hwnd, @ptrCast(&view)) == 0 and view != null) {
        //         _ = view.?.SetFocus();
        //         _ = view.?.Release();
        //     }
        // } else {
        //     _ = win32.SetForegroundWindow(hwnd);
        // }
        _ = win32.SwitchToThisWindow(hwnd, 1);
        _ = win32.SetForegroundWindow(hwnd);
        _ = win32.SetActiveWindow(hwnd);

        restoreForegroundLock();
        _ = win32.SystemParametersInfoA(win32.SPI_SETFOREGROUNDLOCKTIMEOUT, old_lock_timeout, null, win32.SPIF_SENDCHANGE);
    }

    pub fn focusWindowByHwnd(self: *Manager, hwnd: ?win32.HWND) bool {
        if (hwnd == null) return false;

        const workspace = self.ws();
        if (workspace.findColumn(hwnd.?)) |idx| {
            if (idx == workspace.focused) return false;
            workspace.focused = idx;
            return true;
        }
        return false;
    }

    pub fn moveColumnLeft(self: *Manager) void {
        const workspace = self.ws();
        if (workspace.focused == 0 or workspace.columns.items.len <= 1) return;
        const tmp = workspace.columns.items[workspace.focused];
        workspace.columns.items[workspace.focused] = workspace.columns.items[workspace.focused - 1];
        workspace.columns.items[workspace.focused - 1] = tmp;
        workspace.focused -= 1;
        self.arrange();
    }

    pub fn moveColumnRight(self: *Manager) void {
        const workspace = self.ws();
        if (workspace.focused >= workspace.columns.items.len - 1 or workspace.columns.items.len <= 1) return;
        const tmp = workspace.columns.items[workspace.focused];
        workspace.columns.items[workspace.focused] = workspace.columns.items[workspace.focused + 1];
        workspace.columns.items[workspace.focused + 1] = tmp;
        workspace.focused += 1;
        self.arrange();
    }

    pub fn increaseColumnWidth(self: *Manager) void {
        const workspace = self.ws();
        if (workspace.columns.items.len <= 1) return;

        const col = &workspace.columns.items[workspace.focused];
        const current_width = col.user_fixed_width orelse blk: {
            var work_area: win32.RECT = undefined;
            _ = win32.SystemParametersInfoA(win32.SPI_GETWORKAREA, 0, &work_area, .{});
            const screen_width = work_area.right - work_area.left;
            break :blk @divTrunc(screen_width, @as(i32, @intCast(workspace.columns.items.len)));
        };

        col.user_fixed_width = current_width + 150;
        self.arrange();
    }

    pub fn decreaseColumnWidth(self: *Manager) void {
        const workspace = self.ws();
        if (workspace.columns.items.len <= 1) return;

        const col = &workspace.columns.items[workspace.focused];
        const current_width = col.user_fixed_width orelse blk: {
            var work_area: win32.RECT = undefined;
            _ = win32.SystemParametersInfoA(win32.SPI_GETWORKAREA, 0, &work_area, .{});
            const screen_width = work_area.right - work_area.left;
            break :blk @divTrunc(screen_width, @as(i32, @intCast(workspace.columns.items.len)));
        };

        if (current_width > 100) {
            col.user_fixed_width = current_width - 150;
        }
        self.arrange();
    }

    pub fn toggleFullscreen(self: *Manager) bool {
        const workspace = self.ws();
        if (workspace.columns.items.len == 0) return false;

        const col = &workspace.columns.items[workspace.focused];
        const was_fullscreen = col.is_fullscreen;
        col.is_fullscreen = !was_fullscreen;

        if (col.is_fullscreen and !was_fullscreen) {
            var placement: win32.WINDOWPLACEMENT = undefined;
            placement.length = @sizeOf(win32.WINDOWPLACEMENT);
            if (win32.GetWindowPlacement(col.window.hwnd, &placement) != 0) {
                col.original_rect = placement.rcNormalPosition;
            } else {
                col.original_rect = getOriginalRect(col.window.hwnd);
            }

            if (g_fullscreen_minimize_others) {
                for (workspace.columns.items, 0..) |*c, i| {
                    if (i != workspace.focused) {
                        _ = win32.ShowWindow(c.window.hwnd, win32.SW_MINIMIZE);
                    }
                }
            } else {
                _ = win32.SetWindowPos(col.window.hwnd, win32.HWND_TOPMOST, 0, 0, 0, 0, .{ .NOSIZE = 1, .NOMOVE = 1 });
            }
        } else if (!col.is_fullscreen and was_fullscreen) {
            if (g_fullscreen_minimize_others) {
                for (workspace.columns.items, 0..) |*c, i| {
                    if (i != workspace.focused) {
                        _ = win32.ShowWindow(c.window.hwnd, win32.SW_RESTORE);
                    }
                }
                self.activateFocused();
            } else {
                _ = win32.SetWindowPos(col.window.hwnd, win32.HWND_NOTOPMOST, 0, 0, 0, 0, .{ .NOSIZE = 1, .NOMOVE = 1 });
            }
        }

        self.arrange();
        return col.is_fullscreen;
    }

    pub fn switchWorkspace(self: *Manager, target: usize) !void {
        try self.ensureWorkspaceCount(target + 1);
        if (target == self.current) return;
        self.current = target;
        self.arrange();
        self.activateFocused();
    }

    pub fn switchWorkspaceUp(self: *Manager) !void {
        if (self.current > 0) try self.switchWorkspace(self.current - 1);
    }

    pub fn switchWorkspaceDown(self: *Manager) !void {
        try self.ensureWorkspaceCount(self.current + 2);
        try self.switchWorkspace(self.current + 1);
    }

    pub fn moveToWorkspace(self: *Manager, target: usize) !void {
        try self.ensureWorkspaceCount(@max(target, self.current) + 1);
        if (target == self.current) return;

        const workspace = self.ws();
        if (workspace.columns.items.len == 0) return;

        const col = workspace.columns.orderedRemove(workspace.focused);
        if (workspace.focused >= workspace.columns.items.len and workspace.columns.items.len > 0) {
            workspace.focused = workspace.columns.items.len - 1;
        }

        const target_ws = &self.workspaces.items[target];
        try target_ws.columns.append(self.allocator, col);
        target_ws.focused = target_ws.columns.items.len - 1;

        std.log.scoped(.Tiling).info("moveToWorkspace: col from {d} -> {d}, current={d}", .{ self.current, target, self.current });
        self.arrange();
    }

    pub fn moveToWorkspaceUp(self: *Manager) !void {
        if (self.current > 0) try self.moveToWorkspace(self.current - 1);
    }

    pub fn moveToWorkspaceDown(self: *Manager) !void {
        try self.ensureWorkspaceCount(self.current + 2);
        try self.moveToWorkspace(self.current + 1);
    }

    pub fn getWindowCount(self: *const Manager) usize {
        return self.wsConst().columns.items.len;
    }

    pub fn getCurrentWorkspace(self: *const Manager) usize {
        return self.current;
    }

    pub fn getWorkspaceWindowCount(self: *const Manager, ws_idx: usize) usize {
        if (ws_idx >= self.workspaces.items.len) return 0;
        return self.workspaces.items[ws_idx].columns.items.len;
    }

    pub fn getWorkspaceCount(self: *const Manager) usize {
        return self.workspaces.items.len;
    }
};
