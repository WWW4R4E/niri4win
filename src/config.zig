const std = @import("std");
const niri4win = @import("root").niri4win;
const builtin = @import("builtin");
const win32 = niri4win.win32;
const types = niri4win.types;

const MAX_ENTRIES = 32;
const MAX_HOTKEYS = 64;

var g_buf: [8192]u8 = undefined;
var g_buf_pos: usize = 0;

var g_classes: [MAX_ENTRIES][]const u8 = undefined;
var g_classes_count: usize = 0;

var g_titles: [MAX_ENTRIES][]const u8 = undefined;
var g_titles_count: usize = 0;

var g_paths: [MAX_ENTRIES][]const u8 = undefined;
var g_paths_count: usize = 0;

var g_loaded: bool = false;
var g_io: ?std.Io = null;

var g_banned_modules: [32][]const u8 = undefined;
var g_banned_count: usize = 0;
var g_logging_loaded: bool = false;

const Section = enum {
    none,
    class_,
    title,
    path,
    hotkey,
};

const HotkeyConfig = struct {
    id: i32,
    modifiers: win32.HOT_KEY_MODIFIERS,
    vk: u32,
    action: types.Action,
};

var g_hotkey_bindings: [MAX_HOTKEYS]HotkeyConfig = undefined;
var g_hotkey_count: usize = 0;

fn addEntry(list: *[MAX_ENTRIES][]const u8, count: *usize, value: []const u8) void {
    if (count.* >= MAX_ENTRIES) return;
    if (g_buf_pos + value.len > g_buf.len) return;
    @memcpy(g_buf[g_buf_pos..][0..value.len], value);
    list[count.*] = g_buf[g_buf_pos..][0..value.len];
    g_buf_pos += value.len;
    count.* += 1;
}

fn parseKey(name: []const u8) ?u32 {
    if (name.len == 1) {
        const c = name[0];
        if (c >= 'A' and c <= 'Z') return c;
        if (c >= '0' and c <= '9') return c;
        if (c == '=') return 0xBB;
        if (c == '-') return 0xBD;
        if (c == '[') return 0xDB;
        if (c == ']') return 0xDD;
        return null;
    }

    if (std.mem.eql(u8, name, "Left")) return @intFromEnum(win32.VK_LEFT);
    if (std.mem.eql(u8, name, "Right")) return @intFromEnum(win32.VK_RIGHT);
    if (std.mem.eql(u8, name, "Up")) return @intFromEnum(win32.VK_UP);
    if (std.mem.eql(u8, name, "Down")) return @intFromEnum(win32.VK_DOWN);
    if (std.mem.eql(u8, name, "Equals")) return 0xBB;
    if (std.mem.eql(u8, name, "Minus")) return 0xBD;
    if (std.mem.eql(u8, name, "LeftBracket")) return 0xDB;
    if (std.mem.eql(u8, name, "RightBracket")) return 0xDD;

    return null;
}

fn addHotkey(line: []const u8, id: *i32) void {
    const eq_pos = std.mem.lastIndexOf(u8, line, "=") orelse return;
    const key_part = std.mem.trim(u8, line[0..eq_pos], " \t");
    const action_part = std.mem.trim(u8, line[eq_pos + 1 ..], " \t");

    if (key_part.len == 0 or action_part.len == 0) return;

    const action = std.meta.stringToEnum(types.Action, action_part) orelse return;

    var modifiers = win32.HOT_KEY_MODIFIERS{};
    var key: u32 = 0;

    var token_start: usize = 0;
    var i: usize = 0;
    while (i <= key_part.len) : (i += 1) {
        if (i == key_part.len or key_part[i] == '+') {
            const part = std.mem.trim(u8, key_part[token_start..i], " \t");
            if (part.len > 0) {
                if (std.mem.eql(u8, part, "Alt")) {
                    modifiers.ALT = 1;
                } else if (std.mem.eql(u8, part, "Ctrl") or std.mem.eql(u8, part, "Control")) {
                    modifiers.CONTROL = 1;
                } else if (std.mem.eql(u8, part, "Shift")) {
                    modifiers.SHIFT = 1;
                } else if (std.mem.eql(u8, part, "Win")) {
                    modifiers.WIN = 1;
                } else {
                    key = parseKey(part) orelse return;
                }
            }
            token_start = i + 1;
        }
    }

    if (key == 0) return;
    if (g_hotkey_count >= MAX_HOTKEYS) return;

    g_hotkey_bindings[g_hotkey_count] = .{
        .id = id.*,
        .modifiers = modifiers,
        .vk = key,
        .action = action,
    };
    g_hotkey_count += 1;
    id.* += 1;
}

pub fn init(io: std.Io) void {
    g_io = io;
}

pub fn load() void {
    if (g_loaded) return;
    g_loaded = true;
    g_hotkey_count = 0;

    const io = g_io orelse return;
    const name: []const u8 = "config.conf";
    const config_path = getConfigPath(name);

    const file = std.Io.Dir.cwd().openFile(io, config_path, .{ .mode = .read_only }) catch return;
    defer file.close(io);

    var reader_buf: [4096]u8 = undefined;
    var reader = file.reader(io, &reader_buf);
    const r = &reader.interface;

    var section = Section.none;
    var hotkey_id: i32 = 1;

    while (r.takeDelimiter('\n')) |raw_line| {
        const line = std.mem.trim(u8, raw_line orelse break, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        if (std.mem.eql(u8, line, "[class]")) {
            section = .class_;
        } else if (std.mem.eql(u8, line, "[title]")) {
            section = .title;
        } else if (std.mem.eql(u8, line, "[path]")) {
            section = .path;
        } else if (std.mem.eql(u8, line, "[hotkey]")) {
            section = .hotkey;
        } else {
            switch (section) {
                .none => {},
                .class_ => addEntry(&g_classes, &g_classes_count, line),
                .title => addEntry(&g_titles, &g_titles_count, line),
                .path => addEntry(&g_paths, &g_paths_count, line),
                .hotkey => addHotkey(line, &hotkey_id),
            }
        }
    } else |_| {}
}

pub fn getHotkeyBindings() []HotkeyConfig {
    load();
    return g_hotkey_bindings[0..g_hotkey_count];
}

pub fn isBlacklistedClass(class_name: [:0]const u8) bool {
    load();
    for (0..g_classes_count) |i| {
        if (std.mem.eql(u8, class_name, g_classes[i])) return true;
    }
    return false;
}

pub fn isBlacklistedTitle(title: [:0]const u8) bool {
    load();
    for (0..g_titles_count) |i| {
        if (std.mem.indexOf(u8, title, g_titles[i]) != null) return true;
    }
    return false;
}

pub fn isBlacklistedPath(path: [:0]const u8) bool {
    load();
    for (0..g_paths_count) |i| {
        if (std.mem.indexOf(u8, path, g_paths[i]) != null) return true;
    }
    return false;
}

pub fn getIo() ?std.Io {
    return g_io;
}

pub fn getAppBarHeight() i32 {
    return 52;
}

fn getConfigPath(config_name: []const u8) []u8 {
    var buffer: [1024]u8 = undefined;
    const path_length = std.process.executableDirPath(g_io.?, &buffer) catch 0;
    const exe_path = if (builtin.mode != .Debug) buffer[0..path_length] else buffer[0 .. path_length - 12];
    var config_path_buf: [2048]u8 = undefined;
    const config_path = std.fmt.bufPrint(&config_path_buf, "{s}{s}{s}", .{ exe_path, std.fs.path.sep_str, config_name }) catch return "";
    return config_path;
}

// ============================================================
// 日志配置 (单独的文件 logging.conf)
// ============================================================

pub fn loadLoggingConfig() void {
    if (g_logging_loaded) return;
    g_logging_loaded = true;
    const io = g_io.?;
    const file = std.Io.Dir.cwd().openFile(io, "logging.conf", .{ .mode = .read_only }) catch return;

    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var reader = file.reader(io, &buf);
    const r = &reader.interface;

    var in_banned = false;
    while (r.takeDelimiter('\n')) |raw_line| {
        const line = std.mem.trim(u8, raw_line orelse break, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        if (std.mem.eql(u8, line, "[banned]")) {
            in_banned = true;
            continue;
        }

        if (line[0] == '[') {
            in_banned = false;
            continue;
        }

        if (in_banned and g_banned_count < g_banned_modules.len) {
            if (g_buf_pos + line.len <= g_buf.len) {
                @memcpy(g_buf[g_buf_pos..][0..line.len], line);
                g_banned_modules[g_banned_count] = g_buf[g_buf_pos..][0..line.len];
                g_buf_pos += line.len;
                g_banned_count += 1;
            }
        }
    } else |_| {}
}

pub fn isModuleBanned(scope: []const u8) bool {
    loadLoggingConfig();
    for (0..g_banned_count) |i| {
        if (std.mem.eql(u8, scope, g_banned_modules[i])) return true;
    }
    return false;
}
