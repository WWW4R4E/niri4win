const std = @import("std");

const niri4win = @import("root").niri4win;
const win32 = niri4win.win32;
const config = niri4win.config;
const types = niri4win.types;

const HotkeyBinding = struct {
    id: i32,
    modifiers: win32.HOT_KEY_MODIFIERS,
    vk: u32,
    action: types.Action,
};

const KBDLLHOOKSTRUCT = extern struct {
    vkCode: u32,
    scanCode: u32,
    flags: u32,
    time: u32,
    dwExtraInfo: usize,
};

const WM_KEYDOWN = 0x0100;
const WM_KEYUP = 0x0101;
const WM_SYSKEYDOWN = 0x0104;
const WM_SYSKEYUP = 0x0105;

var g_hook: ?win32.HHOOK = null;
var g_hotkey_bindings: [64]HotkeyBinding = undefined;
var g_hotkey_count: usize = 0;
var g_hotkeys_by_vk: [256][32]i32 = undefined;
var g_hotkeys_by_vk_count: [256]usize = undefined;
var g_last_action: types.Action = .none;
var g_custom_message: u32 = 0;
var g_running: bool = false;

fn lowLevelKeyboardProc(nCode: i32, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.winapi) win32.LRESULT {
    if (nCode >= 0) {
        const kbdll = @as(*KBDLLHOOKSTRUCT, @ptrFromInt(@as(usize, @intCast(lParam))));
        if (wParam == WM_KEYDOWN or wParam == WM_SYSKEYDOWN) {
            if (handleKeyDown(kbdll.vkCode)) {
                return 1;
            }
        }
    }
    return win32.CallNextHookEx(g_hook orelse null, nCode, wParam, lParam);
}

fn isKeyDown(vk: i32) bool {
    return win32.GetKeyState(vk) < 0;
}

fn modifiersToFlags(modifiers: win32.HOT_KEY_MODIFIERS) u32 {
    var flags: u32 = 0;
    if (modifiers.ALT == 1) flags |= 0x0001;
    if (modifiers.CONTROL == 1) flags |= 0x0002;
    if (modifiers.SHIFT == 1) flags |= 0x0004;
    if (modifiers.WIN == 1) flags |= 0x0008;
    return flags;
}

fn getCurrentModifiers() u32 {
    var flags: u32 = 0;
    if (isKeyDown(@intFromEnum(win32.VK_MENU))) flags |= 0x0001;
    if (isKeyDown(@intFromEnum(win32.VK_CONTROL))) flags |= 0x0002;
    if (isKeyDown(@intFromEnum(win32.VK_SHIFT))) flags |= 0x0004;
    if (isKeyDown(@intFromEnum(win32.VK_LWIN)) or isKeyDown(@intFromEnum(win32.VK_RWIN))) flags |= 0x0008;
    return flags;
}

fn getModifierCount(modifiers: u32) usize {
    var count: usize = 0;
    if ((modifiers & 0x0001) != 0) count += 1;
    if ((modifiers & 0x0002) != 0) count += 1;
    if ((modifiers & 0x0004) != 0) count += 1;
    if ((modifiers & 0x0008) != 0) count += 1;
    return count;
}

fn handleKeyDown(vkCode: u32) bool {
    const current_modifiers = getCurrentModifiers();
    const vk_idx: usize = @intCast(vkCode);
    if (vk_idx >= 256) return false;

    const candidates = g_hotkeys_by_vk[vk_idx][0..g_hotkeys_by_vk_count[vk_idx]];
    var best_match: ?HotkeyBinding = null;
    var best_modifier_count: usize = 0;

    for (candidates) |hotkey_id| {
        for (0..g_hotkey_count) |i| {
            if (g_hotkey_bindings[i].id == hotkey_id) {
                const binding = &g_hotkey_bindings[i];
                const binding_modifiers = modifiersToFlags(binding.modifiers);
                if (current_modifiers == binding_modifiers) {
                    const binding_modifier_count = getModifierCount(binding_modifiers);
                    if (binding_modifier_count > best_modifier_count) {
                        best_match = binding.*;
                        best_modifier_count = binding_modifier_count;
                    }
                }
                break;
            }
        }
    }

    if (best_match) |binding| {
        std.log.scoped(.Hotkey).info("匹配快捷键: action={s}", .{@tagName(binding.action)});
        g_last_action = binding.action;
        return true;
    }

    return false;
}

pub fn init() void {
    std.log.scoped(.Hotkey).info("初始化钩子系统...", .{});
    const message_name = "niri4win_Hotkey";
    g_custom_message = win32.RegisterWindowMessageA(message_name);
    std.log.scoped(.Hotkey).info("自定义消息ID: {}", .{g_custom_message});

    for (0..256) |i| {
        g_hotkeys_by_vk_count[i] = 0;
    }
}

pub fn registerHotkeys() void {
    std.log.scoped(.Hotkey).info("开始注册快捷键...", .{});
    g_hotkey_count = 0;

    const bindings = config.getHotkeyBindings();
    for (bindings) |binding| {
        if (g_hotkey_count >= g_hotkey_bindings.len) break;
        g_hotkey_bindings[g_hotkey_count] = .{
            .id = binding.id,
            .modifiers = binding.modifiers,
            .vk = binding.vk,
            .action = binding.action,
        };

        const vk_idx: usize = @intCast(binding.vk);
        if (vk_idx < 256 and g_hotkeys_by_vk_count[vk_idx] < 32) {
            g_hotkeys_by_vk[vk_idx][g_hotkeys_by_vk_count[vk_idx]] = binding.id;
            g_hotkeys_by_vk_count[vk_idx] += 1;
        }

        g_hotkey_count += 1;
    }

    const hinstance = win32.GetModuleHandleA(null) orelse {
        std.log.scoped(.Hotkey).warn("获取模块句柄失败", .{});
        return;
    };

    g_hook = win32.SetWindowsHookExW(win32.WINDOWS_HOOK_ID.KEYBOARD_LL, lowLevelKeyboardProc, hinstance, 0);
    if (g_hook == null) {
        std.log.scoped(.Hotkey).warn("设置钩子失败", .{});
    } else {
        std.log.scoped(.Hotkey).info("钩子设置成功，共 {d} 个快捷键", .{g_hotkey_count});
    }

    g_running = true;
}

pub fn deinit() void {
    std.log.scoped(.Hotkey).info("卸载钩子...", .{});
    g_running = false;
    if (g_hook != null) {
        _ = win32.UnhookWindowsHookEx(g_hook);
        g_hook = null;
    }
    g_hotkey_count = 0;
    for (0..256) |i| {
        g_hotkeys_by_vk_count[i] = 0;
    }
    std.log.scoped(.Hotkey).info("钩子已卸载", .{});
}

pub fn processMessage(msg: win32.MSG) types.Action {
    _ = msg;
    const action = g_last_action;
    g_last_action = .none;
    return action;
}

pub fn columnIndexFromAction(action: types.Action) ?usize {
    return switch (action) {
        .focus_column_1 => 0,
        .focus_column_2 => 1,
        .focus_column_3 => 2,
        .focus_column_4 => 3,
        .focus_column_5 => 4,
        .focus_column_6 => 5,
        .focus_column_7 => 6,
        .focus_column_8 => 7,
        .focus_column_9 => 8,
        else => null,
    };
}

pub fn workspaceIndexFromAction(action: types.Action) ?usize {
    return switch (action) {
        .switch_workspace_1 => 0,
        .switch_workspace_2 => 1,
        .switch_workspace_3 => 2,
        .switch_workspace_4 => 3,
        .switch_workspace_5 => 4,
        .switch_workspace_6 => 5,
        .switch_workspace_7 => 6,
        .switch_workspace_8 => 7,
        .switch_workspace_9 => 8,
        .move_to_workspace_1 => 0,
        .move_to_workspace_2 => 1,
        .move_to_workspace_3 => 2,
        .move_to_workspace_4 => 3,
        .move_to_workspace_5 => 4,
        .move_to_workspace_6 => 5,
        .move_to_workspace_7 => 6,
        .move_to_workspace_8 => 7,
        .move_to_workspace_9 => 8,
        else => null,
    };
}
