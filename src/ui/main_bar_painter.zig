const std = @import("std");
const niri4win = @import("../root.zig");
const win32 = niri4win.win32;
const ui = niri4win.ui;
const d2d = ui.d2d;
const brushes = ui.brushes;
const state = ui.state;
const tiling = niri4win.tiling;

pub const MAX_WORKSPACES: usize = 10;
pub const MAX_ICONS: usize = 64;

const IconSlot = struct {
    rect: win32.D2D_RECT_F,
    icon: win32.HICON,
    hwnd: win32.HWND,
    is_focused: bool,
};

pub const CardLayout = struct {
    rect: win32.D2D_RECT_F,
    is_active: bool,
    icon_count: u8,
    icon_offset: u8,
};

pub const BarLayout = struct {
    cards: [MAX_WORKSPACES]CardLayout,
    card_count: u8,
    icons: [MAX_ICONS]IconSlot,
    icon_count: u8,
    fg_icon: ?IconSlot,
};

pub const MainBarPainter = struct {
    d2d: d2d.D2DContext,
    brushes: brushes.BrushCache,
    hwnd: win32.HWND,

    // Layout cache: computed once in render(), reused by hitTest()
    layout: BarLayout,

    // Drawing constants
    icon_size: f32,
    padding: f32,
    ws_pad: f32,
    ws_margin: f32,
    corner_r: f32,
    fg_icon_size: f32,

    pub fn init(hwnd: win32.HWND) !MainBarPainter {
        var cr: win32.RECT = undefined;
        _ = win32.GetClientRect(hwnd, &cr);
        const cw = @as(u32, @intCast(cr.right - cr.left));
        const ch = @as(u32, @intCast(cr.bottom - cr.top));

        var d2d_ctx = try d2d.D2DContext.init(hwnd, cw, ch);
        d2d_ctx.initAcrylic();

        return MainBarPainter{
            .d2d = d2d_ctx,
            .brushes = brushes.BrushCache.init(),
            .hwnd = hwnd,
            .layout = undefined,
            .icon_size = 24.0,
            .padding = 8.0,
            .ws_pad = 8.0,
            .ws_margin = 4.0,
            .corner_r = 6.0,
            .fg_icon_size = 24.0,
        };
    }

    pub fn deinit(self: *MainBarPainter) void {
        self.brushes.deinit();
        self.d2d.deinit();
    }

    // ─── 入口 ──────────────────────────────────

    pub fn render(self: *MainBarPainter, app_state: *const state.AppState) void {
        self.d2d.beginDraw();

        self.layout = self.computeLayout(app_state);
        self.drawCards(app_state);
        self.drawForeground();

        self.d2d.endDraw();
    }

    // ─── Phase 1: 布局（纯数学，不碰 D2D 绘制）────

    fn computeLayout(self: *MainBarPainter, app_state: *const state.AppState) BarLayout {
        const tm = app_state.tiling;
        const cur_ws = tm.current;

        var client: win32.RECT = undefined;
        _ = win32.GetClientRect(self.hwnd, &client);
        const ww: f32 = @floatFromInt(client.right - client.left);

        const disp_c = tm.workspaces.items.len;

        var result: BarLayout = undefined;
        result.card_count = 0;
        result.icon_count = 0;
        result.fg_icon = null;

        var curr_x: f32 = self.padding;
        var curr_y: f32 = self.padding;

        var wi: usize = 0;
        while (wi < disp_c) : (wi += 1) {
            if (wi >= tm.workspaces.items.len) break;
            const ws = &tm.workspaces.items[wi];
            const has_win = ws.columns.items.len > 0;

            const wsw = if (has_win)
                @as(f32, @floatFromInt(ws.columns.items.len)) * (self.icon_size + self.padding) + self.ws_pad * 2.0
            else
                self.icon_size + self.ws_pad * 2.0;
            const wsh = self.icon_size + self.ws_pad * 2.0;

            const card_rect = win32.D2D_RECT_F{
                .left = curr_x,
                .top = curr_y,
                .right = curr_x + wsw,
                .bottom = curr_y + wsh,
            };

            // Record card layout
            const card_idx = result.card_count;
            result.cards[card_idx] = .{
                .rect = card_rect,
                .is_active = (wi == cur_ws),
                .icon_count = 0,
                .icon_offset = result.icon_count,
            };

            // Record icon positions
            var ix: f32 = curr_x + self.ws_pad;
            const iy: f32 = curr_y + self.ws_pad;
            for (ws.columns.items, 0..) |col, col_i| {
                const is_foc = (wi == cur_ws and col_i == ws.focused);
                const ds: f32 = if (is_foc) 28.0 else self.icon_size;
                const ox: f32 = if (is_foc) (self.icon_size - ds) / 2.0 else 0.0;
                const oy: f32 = if (is_foc) (self.icon_size - ds) / 2.0 else 0.0;

                if (col.window.icon) |icn| {
                    const icon_idx = result.icon_count;
                    result.icons[icon_idx] = .{
                        .rect = .{
                            .left = ix + ox,
                            .top = iy + oy,
                            .right = ix + ox + ds,
                            .bottom = iy + oy + ds,
                        },
                        .icon = icn,
                        .hwnd = col.window.hwnd,
                        .is_focused = is_foc,
                    };
                    result.icon_count += 1;
                    result.cards[card_idx].icon_count += 1;
                }
                ix += self.icon_size + self.padding;
            }

            result.card_count += 1;

            curr_x += wsw + self.ws_margin;
            if (curr_x + wsw > ww - self.padding) {
                curr_x = self.padding;
                curr_y += wsh + self.ws_margin;
            }
        }

        // Foreground window icon
        const rf = app_state.foreground;
        if (rf != null) {
            const ricon = ui.task_bar.getWindowIcon(rf.?);
            if (ricon) |icn| {
                result.fg_icon = .{
                    .rect = .{
                        .left = ww - self.fg_icon_size - self.padding,
                        .top = self.padding,
                        .right = ww - self.padding,
                        .bottom = self.padding + self.fg_icon_size,
                    },
                    .icon = icn,
                    .hwnd = rf.?,
                    .is_focused = false,
                };
            }
        }

        return result;
    }

    // ─── Phase 2: 绘制（只看 layout，不读 AppState）───

    fn drawCards(self: *MainBarPainter, app_state: *const state.AppState) void {
        _ = app_state;
        const lay = &self.layout;

        var ci: u8 = 0;
        while (ci < lay.card_count) : (ci += 1) {
            const card = &lay.cards[ci];

            if (card.is_active) {
                const bf = self.brushes.getActiveFill(self.d2d.ctx);
                self.d2d.fillRoundedRect(card.rect, self.corner_r, @ptrCast(bf));
                const bb = self.brushes.getActiveBorder(self.d2d.ctx);
                self.d2d.drawRoundedRect(card.rect, self.corner_r, @ptrCast(bb), 2.0);
            } else {
                const bf = self.brushes.getInactiveFill(self.d2d.ctx);
                self.d2d.fillRoundedRect(card.rect, self.corner_r, @ptrCast(bf));
                const bb = self.brushes.getInactiveBorder(self.d2d.ctx);
                self.d2d.drawRoundedRect(card.rect, self.corner_r, @ptrCast(bb), 1.0);
            }

            // Draw window icons for this card
            var ii: u8 = 0;
            while (ii < card.icon_count) : (ii += 1) {
                const slot = &lay.icons[card.icon_offset + ii];
                if (self.d2d.hiconToBitmap(slot.icon)) |bmp| {
                    defer _ = bmp.IUnknown.Release();
                    self.d2d.drawBitmap(bmp, &slot.rect, 1.0);
                } else |_| {}
            }
        }
    }

    fn drawForeground(self: *MainBarPainter) void {
        const fg = self.layout.fg_icon orelse return;
        if (self.d2d.hiconToBitmap(fg.icon)) |bmp| {
            defer _ = bmp.IUnknown.Release();
            self.d2d.drawBitmap(bmp, &fg.rect, 1.0);
        } else |_| {}
    }

    // ─── Phase 3: 命中检测（查 layout，零计算）────

    pub const HitResult = struct {
        ws_idx: usize,
        window_hwnd: ?win32.HWND,
    };

    pub fn hitTest(self: *const MainBarPainter, x: f32, y: f32) ?HitResult {
        var ci: u8 = 0;
        while (ci < self.layout.card_count) : (ci += 1) {
            const card = &self.layout.cards[ci];
            const r = card.rect;
            if (!(x >= r.left and x < r.right and y >= r.top and y < r.bottom))
                continue;

            // Check individual window icons first
            var ii: u8 = 0;
            while (ii < card.icon_count) : (ii += 1) {
                const slot = &self.layout.icons[card.icon_offset + ii];
                const sr = slot.rect;
                if (x >= sr.left and x < sr.right and y >= sr.top and y < sr.bottom) {
                    return HitResult{ .ws_idx = ci, .window_hwnd = slot.hwnd };
                }
            }

            // Clicked empty area of the workspace card
            return HitResult{ .ws_idx = ci, .window_hwnd = null };
        }
        return null;
    }
};
