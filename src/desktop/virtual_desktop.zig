const std = @import("std");

const niri4win = @import("root").niri4win;
const win32 = niri4win.win32;
const com = niri4win.com;
const IObjectArray = com.IObjectArray;
const IServiceProvider = com.IServiceProvider;

pub const CLSID_VirtualDesktopManager = win32.Guid{ .Ints = .{ .a = 0xAA509086, .b = 0x5CA9, .c = 0x4C25, .d = .{ 0x8F, 0x95, 0x58, 0x9D, 0x3C, 0x07, 0xB4, 0x8A } } };

pub const CLSID_VirtualDesktopPinnedApps = win32.Guid{ .Ints = .{ .a = 0xB5A399E7, .b = 0x1C87, .c = 0x46B8, .d = .{ 0x88, 0xE9, 0xFC, 0x57, 0x47, 0xB1, 0x71, 0xBD } } };

pub const CLSID_VirtualDesktopAPI_Unknown = win32.Guid{ .Ints = .{ .a = 0xC5E0CDCA, .b = 0x7B6E, .c = 0x41B2, .d = .{ 0x9F, 0xC4, 0xD9, 0x39, 0x75, 0xCC, 0x46, 0x7B } } };

pub const IID_IVirtualDesktopManagerInternal_Candidates = [_]struct { name: []const u8, iid: win32.Guid }{
    .{ .name = "4970BA3D-FD4E-4647-BEA3-D89076EF4B9C (Win11 24H2 26100)", .iid = win32.Guid{ .Ints = .{ .a = 0x4970BA3D, .b = 0xFD4E, .c = 0x4647, .d = .{ 0xBE, 0xA3, 0xD8, 0x90, 0x76, 0xEF, 0x4B, 0x9C } } } },
    .{ .name = "A3175F2D-239C-4BD2-8AA0-EEBA8B0B138E (Win11 23H2/24H2)", .iid = win32.Guid{ .Ints = .{ .a = 0xA3175F2D, .b = 0x239C, .c = 0x4BD2, .d = .{ 0x8A, 0xA0, 0xEE, 0xBA, 0x8B, 0x0B, 0x13, 0x8E } } } },
    .{ .name = "B2F925B9-5A0F-4D2E-9F4D-2B1507593C10 (Win11 22621)", .iid = win32.Guid{ .Ints = .{ .a = 0xB2F925B9, .b = 0x5A0F, .c = 0x4D2E, .d = .{ 0x9F, 0x4D, 0x2B, 0x15, 0x07, 0x59, 0x3C, 0x10 } } } },
    .{ .name = "F31574D6-B682-4CDC-BD56-1827860ABEC6 (Win10/early Win11)", .iid = win32.Guid{ .Ints = .{ .a = 0xF31574D6, .b = 0xB682, .c = 0x4CDC, .d = .{ 0xBD, 0x56, 0x18, 0x27, 0x86, 0x0A, 0xBE, 0xC6 } } } },
};

pub const IID_IVirtualDesktop_Candidates = [_]struct { name: []const u8, iid: win32.Guid }{
    .{ .name = "8AC9D33B-99A2-4D7B-A4D8-D7B7DDDC9E12 (Win11 24H2)", .iid = win32.Guid{ .Ints = .{ .a = 0x8AC9D33B, .b = 0x99A2, .c = 0x4D7B, .d = .{ 0xA4, 0xD8, 0xD7, 0xB7, 0xDD, 0xDC, 0x9E, 0x12 } } } },
    .{ .name = "3F07F4BE-B107-441A-AF0F-39D82529072C (Win11 23H2)", .iid = win32.Guid{ .Ints = .{ .a = 0x3F07F4BE, .b = 0xB107, .c = 0x441A, .d = .{ 0xAF, 0x0F, 0x39, 0xD8, 0x25, 0x29, 0x07, 0x2C } } } },
    .{ .name = "536D3495-B208-4CC9-AE26-DE8111275BF8 (Win11 22621)", .iid = win32.Guid{ .Ints = .{ .a = 0x536D3495, .b = 0xB208, .c = 0x4CC9, .d = .{ 0xAE, 0x26, 0xDE, 0x81, 0x11, 0x27, 0x5B, 0xF8 } } } },
    .{ .name = "62FDF88B-11CA-4AFB-8BD8-2296DFAE49E2 (Win11 22000)", .iid = win32.Guid{ .Ints = .{ .a = 0x62FDF88B, .b = 0x11CA, .c = 0x4AFB, .d = .{ 0x8B, 0xD8, 0x22, 0x96, 0xDF, 0xAE, 0x49, 0xE2 } } } },
    .{ .name = "FF72FFDD-BE7E-43FC-9C03-AD81681E88E4 (Win10)", .iid = win32.Guid{ .Ints = .{ .a = 0xFF72FFDD, .b = 0xBE7E, .c = 0x43FC, .d = .{ 0x9C, 0x03, 0xAD, 0x81, 0x68, 0x1E, 0x88, 0xE4 } } } },
};

pub const IID_IApplicationView = win32.Guid{ .Ints = .{ .a = 0x372E1D3B, .b = 0x38D3, .c = 0x42E4, .d = .{ 0xA1, 0x5B, 0x8A, 0xB2, 0xB1, 0x78, 0xF5, 0x13 } } };

pub const IID_IApplicationViewCollection = win32.Guid{ .Ints = .{ .a = 0x1841C6D7, .b = 0x4F9D, .c = 0x42C0, .d = .{ 0xAF, 0x41, 0x87, 0x47, 0x53, 0x8F, 0x10, 0xE5 } } };

pub const IID_IVirtualDesktopManager = win32.Guid{ .Ints = .{ .a = 0xA5CD92FF, .b = 0x29BE, .c = 0x454C, .d = .{ 0x8D, 0x04, 0xD8, 0x28, 0x79, 0xFB, 0x3F, 0x1B } } };

pub const AdjacentDesktop = enum(c_int) {
    LeftDirection = 3,
    RightDirection = 4,
};

pub const APPLICATION_VIEW_CLOAK_TYPE = enum(c_int) {
    AVCT_NONE = 0,
    AVCT_DEFAULT = 1,
    AVCT_VIRTUAL_DESKTOP = 2,
};

pub const APPLICATION_VIEW_COMPATIBILITY_POLICY = enum(c_int) {
    AVCP_NONE = 0,
    AVCP_SMALL_SCREEN = 1,
    AVCP_TABLET_SMALL_SCREEN = 2,
    AVCP_VERY_SMALL_SCREEN = 3,
    AVCP_HIGH_SCALE_FACTOR = 4,
};

pub const IApplicationView = extern struct {
    lpVtbl: [*c]const IApplicationViewVtbl,

    pub fn QueryInterface(self: *IApplicationView, riid: *const win32.Guid, ppvObject: [*c]?*anyopaque) win32.HRESULT {
        return self.lpVtbl.*.QueryInterface(self, riid, ppvObject);
    }
    pub fn AddRef(self: *IApplicationView) u32 {
        return self.lpVtbl.*.AddRef(self);
    }
    pub fn Release(self: *IApplicationView) u32 {
        return self.lpVtbl.*.Release(self);
    }
    pub fn SetFocus(self: *IApplicationView) win32.HRESULT {
        return self.lpVtbl.*.SetFocus(self);
    }
    pub fn GetThumbnailWindow(self: *IApplicationView, hwnd: [*c]win32.HWND) win32.HRESULT {
        return self.lpVtbl.*.GetThumbnailWindow(self, hwnd);
    }
    pub fn GetVirtualDesktopId(self: *IApplicationView, guid: [*c]win32.Guid) win32.HRESULT {
        return self.lpVtbl.*.GetVirtualDesktopId(self, guid);
    }
    pub fn GetAppUserModelId(self: *IApplicationView, Id: [*c][*c]u16) win32.HRESULT {
        return self.lpVtbl.*.GetAppUserModelId(self, Id);
    }
};

const IApplicationViewVtbl = extern struct {
    QueryInterface: *const fn (This: [*c]IApplicationView, riid: *const win32.Guid, ppvObject: [*c]?*anyopaque) callconv(.c) win32.HRESULT,
    AddRef: *const fn (This: [*c]IApplicationView) callconv(.c) u32,
    Release: *const fn (This: [*c]IApplicationView) callconv(.c) u32,
    GetIids: *const fn (This: [*c]IApplicationView, pcount: [*c]u32, pguids: [*c][*c]win32.Guid) callconv(.c) win32.HRESULT,
    GetRuntimeClassName: *const fn (This: [*c]IApplicationView, pClassName: [*c]?*anyopaque) callconv(.c) win32.HRESULT,
    GetTrustLevel: *const fn (This: [*c]IApplicationView, pTrustLevel: [*c]c_int) callconv(.c) win32.HRESULT,
    SetFocus: *const fn (This: [*c]IApplicationView) callconv(.c) win32.HRESULT,
    SwitchTo: *const fn (This: [*c]IApplicationView) callconv(.c) win32.HRESULT,
    TryInvokeBack: *const fn (This: [*c]IApplicationView, Callback: ?*anyopaque) callconv(.c) win32.HRESULT,
    GetThumbnailWindow: *const fn (This: [*c]IApplicationView, hwnd: [*c]win32.HWND) callconv(.c) win32.HRESULT,
    GetMonitor: *const fn (This: [*c]IApplicationView, immersiveMonitor: [*c]?*anyopaque) callconv(.c) win32.HRESULT,
    GetVisibility: *const fn (This: [*c]IApplicationView, visibility: [*c]c_int) callconv(.c) win32.HRESULT,
    SetCloak: *const fn (This: [*c]IApplicationView, cloakType: APPLICATION_VIEW_CLOAK_TYPE, unknown: c_int) callconv(.c) win32.HRESULT,
    GetPosition: *const fn (This: [*c]IApplicationView, guid: [*c]win32.Guid, position: [*c]?*anyopaque) callconv(.c) win32.HRESULT,
    SetPosition: *const fn (This: [*c]IApplicationView, position: ?*anyopaque) callconv(.c) win32.HRESULT,
    InsertAfterWindow: *const fn (This: [*c]IApplicationView, hwnd: win32.HWND) callconv(.c) win32.HRESULT,
    GetExtendedFramePosition: *const fn (This: [*c]IApplicationView, rect: [*c]win32.RECT) callconv(.c) win32.HRESULT,
    GetAppUserModelId: *const fn (This: [*c]IApplicationView, Id: [*c][*c]u16) callconv(.c) win32.HRESULT,
    SetAppUserModelId: *const fn (This: [*c]IApplicationView, Id: [*c]u16) callconv(.c) win32.HRESULT,
    IsEqualByAppUserModelId: *const fn (This: [*c]IApplicationView, Id: [*c]u16, result: [*c]c_int) callconv(.c) win32.HRESULT,
    GetViewState: *const fn (This: [*c]IApplicationView, state: [*c]u32) callconv(.c) win32.HRESULT,
    SetViewState: *const fn (This: [*c]IApplicationView, state: u32) callconv(.c) win32.HRESULT,
    GetNeediness: *const fn (This: [*c]IApplicationView, neediness: [*c]c_int) callconv(.c) win32.HRESULT,
    GetLastActivationTimestamp: *const fn (This: [*c]IApplicationView, timestamp: [*c]u32) callconv(.c) win32.HRESULT,
    SetLastActivationTimestamp: *const fn (This: [*c]IApplicationView, timestamp: u32) callconv(.c) win32.HRESULT,
    GetVirtualDesktopId: *const fn (This: [*c]IApplicationView, guid: [*c]win32.Guid) callconv(.c) win32.HRESULT,
    SetVirtualDesktopId: *const fn (This: [*c]IApplicationView, guid: [*c]win32.Guid) callconv(.c) win32.HRESULT,
    GetShowInSwitchers: *const fn (This: [*c]IApplicationView, flag: [*c]c_int) callconv(.c) win32.HRESULT,
    SetShowInSwitchers: *const fn (This: [*c]IApplicationView, flag: c_int) callconv(.c) win32.HRESULT,
    GetScaleFactor: *const fn (This: [*c]IApplicationView, factor: [*c]c_int) callconv(.c) win32.HRESULT,
    CanReceiveInput: *const fn (This: [*c]IApplicationView, canReceiveInput: [*c]c_int) callconv(.c) win32.HRESULT,
    GetCompatibilityPolicyType: *const fn (This: [*c]IApplicationView, flags: [*c]APPLICATION_VIEW_COMPATIBILITY_POLICY) callconv(.c) win32.HRESULT,
    SetCompatibilityPolicyType: *const fn (This: [*c]IApplicationView, flags: APPLICATION_VIEW_COMPATIBILITY_POLICY) callconv(.c) win32.HRESULT,
    GetSizeConstraints: *const fn (This: [*c]IApplicationView, monitor: ?*anyopaque, size1: [*c]win32.SIZE, size2: [*c]win32.SIZE) callconv(.c) win32.HRESULT,
    GetSizeConstraintsForDpi: *const fn (This: [*c]IApplicationView, uint1: u32, size1: [*c]win32.SIZE, size2: [*c]win32.SIZE) callconv(.c) win32.HRESULT,
    SetSizeConstraintsForDpi: *const fn (This: [*c]IApplicationView, uint1: u32, size1: [*c]win32.SIZE, size2: [*c]win32.SIZE) callconv(.c) win32.HRESULT,
    OnMinSizePreferencesUpdated: *const fn (This: [*c]IApplicationView, hwnd: win32.HWND) callconv(.c) win32.HRESULT,
    ApplyOperation: *const fn (This: [*c]IApplicationView, operation: ?*anyopaque) callconv(.c) win32.HRESULT,
    IsTray: *const fn (This: [*c]IApplicationView, isTray: [*c]c_int) callconv(.c) win32.HRESULT,
    IsInHighZOrderBand: *const fn (This: [*c]IApplicationView, isInHighZOrderBand: [*c]c_int) callconv(.c) win32.HRESULT,
    IsSplashScreenPresented: *const fn (This: [*c]IApplicationView, isSplashScreenPresented: [*c]c_int) callconv(.c) win32.HRESULT,
    Flash: *const fn (This: [*c]IApplicationView) callconv(.c) win32.HRESULT,
    GetRootSwitchableOwner: *const fn (This: [*c]IApplicationView, rootSwitchableOwner: [*c][*c]IApplicationView) callconv(.c) win32.HRESULT,
    EnumerateOwnershipTree: *const fn (This: [*c]IApplicationView, ownershipTree: [*c][*c]IObjectArray) callconv(.c) win32.HRESULT,
    GetEnterpriseId: *const fn (This: [*c]IApplicationView, enterpriseId: [*c][*c]u16) callconv(.c) win32.HRESULT,
    IsMirrored: *const fn (This: [*c]IApplicationView, isMirrored: [*c]c_int) callconv(.c) win32.HRESULT,
    Unknown1: *const fn (This: [*c]IApplicationView, unknown: [*c]c_int) callconv(.c) win32.HRESULT,
    Unknown2: *const fn (This: [*c]IApplicationView, unknown: [*c]c_int) callconv(.c) win32.HRESULT,
    Unknown3: *const fn (This: [*c]IApplicationView, unknown: [*c]c_int) callconv(.c) win32.HRESULT,
    Unknown4: *const fn (This: [*c]IApplicationView, unknown: [*c]c_int) callconv(.c) win32.HRESULT,
    Unknown5: *const fn (This: [*c]IApplicationView, unknown: [*c]c_int) callconv(.c) win32.HRESULT,
    Unknown6: *const fn (This: [*c]IApplicationView, unknown: c_int) callconv(.c) win32.HRESULT,
    Unknown7: *const fn (This: [*c]IApplicationView) callconv(.c) win32.HRESULT,
    Unknown8: *const fn (This: [*c]IApplicationView, unknown: [*c]c_int) callconv(.c) win32.HRESULT,
    Unknown9: *const fn (This: [*c]IApplicationView, unknown: c_int) callconv(.c) win32.HRESULT,
    Unknown10: *const fn (This: [*c]IApplicationView, unknownX: c_int, unknownY: c_int) callconv(.c) win32.HRESULT,
    Unknown11: *const fn (This: [*c]IApplicationView, unknown: c_int) callconv(.c) win32.HRESULT,
    Unknown12: *const fn (This: [*c]IApplicationView, size1: [*c]win32.SIZE) callconv(.c) win32.HRESULT,
};

pub const IApplicationViewCollection = extern struct {
    lpVtbl: [*c]const IApplicationViewCollectionVtbl,

    pub fn QueryInterface(self: *IApplicationViewCollection, riid: *const win32.Guid, ppvObject: [*c]?*anyopaque) win32.HRESULT {
        return self.lpVtbl.*.QueryInterface(self, riid, ppvObject);
    }
    pub fn AddRef(self: *IApplicationViewCollection) u32 {
        return self.lpVtbl.*.AddRef(self);
    }
    pub fn Release(self: *IApplicationViewCollection) u32 {
        return self.lpVtbl.*.Release(self);
    }
    pub fn GetViews(self: *IApplicationViewCollection, ppViews: [*c][*c]IObjectArray) win32.HRESULT {
        return self.lpVtbl.*.GetViews(self, ppViews);
    }
    pub fn GetViewsByZOrder(self: *IApplicationViewCollection, ppViews: [*c][*c]IObjectArray) win32.HRESULT {
        return self.lpVtbl.*.GetViewsByZOrder(self, ppViews);
    }
    pub fn GetViewsByAppUserModelId(self: *IApplicationViewCollection, appId: [*c]const u16, ppViews: [*c][*c]IObjectArray) win32.HRESULT {
        return self.lpVtbl.*.GetViewsByAppUserModelId(self, appId, ppViews);
    }
    pub fn GetViewForHwnd(self: *IApplicationViewCollection, hwnd: win32.HWND, ppView: [*c][*c]IApplicationView) win32.HRESULT {
        return self.lpVtbl.*.GetViewForHwnd(self, hwnd, ppView);
    }
    pub fn GetViewForApplication(self: *IApplicationViewCollection, application: ?*anyopaque, ppView: [*c][*c]IApplicationView) win32.HRESULT {
        return self.lpVtbl.*.GetViewForApplication(self, application, ppView);
    }
    pub fn GetViewForAppUserModelId(self: *IApplicationViewCollection, appId: [*c]const u16, ppView: [*c][*c]IApplicationView) win32.HRESULT {
        return self.lpVtbl.*.GetViewForAppUserModelId(self, appId, ppView);
    }
    pub fn GetViewInFocus(self: *IApplicationViewCollection, ppView: [*c][*c]IApplicationView) win32.HRESULT {
        return self.lpVtbl.*.GetViewInFocus(self, ppView);
    }
    pub fn RefreshCollection(self: *IApplicationViewCollection) win32.HRESULT {
        return self.lpVtbl.*.RefreshCollection(self);
    }
    pub fn RegisterForApplicationViewChanges(self: *IApplicationViewCollection, listener: ?*anyopaque, cookie: [*c]c_int) win32.HRESULT {
        return self.lpVtbl.*.RegisterForApplicationViewChanges(self, listener, cookie);
    }
    pub fn UnregisterForApplicationViewChanges(self: *IApplicationViewCollection, cookie: c_int) win32.HRESULT {
        return self.lpVtbl.*.UnregisterForApplicationViewChanges(self, cookie);
    }
};

const IApplicationViewCollectionVtbl = extern struct {
    QueryInterface: *const fn (This: [*c]IApplicationViewCollection, riid: *const win32.Guid, ppvObject: [*c]?*anyopaque) callconv(.c) win32.HRESULT,
    AddRef: *const fn (This: [*c]IApplicationViewCollection) callconv(.c) u32,
    Release: *const fn (This: [*c]IApplicationViewCollection) callconv(.c) u32,
    GetViews: *const fn (This: [*c]IApplicationViewCollection, ppViews: [*c][*c]IObjectArray) callconv(.c) win32.HRESULT,
    GetViewsByZOrder: *const fn (This: [*c]IApplicationViewCollection, ppViews: [*c][*c]IObjectArray) callconv(.c) win32.HRESULT,
    GetViewsByAppUserModelId: *const fn (This: [*c]IApplicationViewCollection, appId: [*c]const u16, ppViews: [*c][*c]IObjectArray) callconv(.c) win32.HRESULT,
    GetViewForHwnd: *const fn (This: [*c]IApplicationViewCollection, hwnd: win32.HWND, ppView: [*c][*c]IApplicationView) callconv(.c) win32.HRESULT,
    GetViewForApplication: *const fn (This: [*c]IApplicationViewCollection, application: ?*anyopaque, ppView: [*c][*c]IApplicationView) callconv(.c) win32.HRESULT,
    GetViewForAppUserModelId: *const fn (This: [*c]IApplicationViewCollection, appId: [*c]const u16, ppView: [*c][*c]IApplicationView) callconv(.c) win32.HRESULT,
    GetViewInFocus: *const fn (This: [*c]IApplicationViewCollection, ppView: [*c][*c]IApplicationView) callconv(.c) win32.HRESULT,
    Unknown1: *const fn (This: [*c]IApplicationViewCollection, ppView: [*c][*c]IApplicationView) callconv(.c) win32.HRESULT,
    RefreshCollection: *const fn (This: [*c]IApplicationViewCollection) callconv(.c) win32.HRESULT,
    RegisterForApplicationViewChanges: *const fn (This: [*c]IApplicationViewCollection, listener: ?*anyopaque, cookie: [*c]c_int) callconv(.c) win32.HRESULT,
    UnregisterForApplicationViewChanges: *const fn (This: [*c]IApplicationViewCollection, cookie: c_int) callconv(.c) win32.HRESULT,
};

pub const IVirtualDesktop = extern struct {
    lpVtbl: [*c]const IVirtualDesktopVtbl,

    pub fn QueryInterface(self: *IVirtualDesktop, riid: *const win32.Guid, ppvObject: [*c]?*anyopaque) win32.HRESULT {
        return self.lpVtbl.*.QueryInterface(self, riid, ppvObject);
    }
    pub fn AddRef(self: *IVirtualDesktop) u32 {
        return self.lpVtbl.*.AddRef(self);
    }
    pub fn Release(self: *IVirtualDesktop) u32 {
        return self.lpVtbl.*.Release(self);
    }
    pub fn IsViewVisible(self: *IVirtualDesktop, pView: [*c]IApplicationView, pVisible: [*c]c_int) win32.HRESULT {
        return self.lpVtbl.*.IsViewVisible(self, pView, pVisible);
    }
    pub fn GetID(self: *IVirtualDesktop, pGuid: [*c]win32.Guid) win32.HRESULT {
        return self.lpVtbl.*.GetID(self, pGuid);
    }
};

const IVirtualDesktopVtbl = extern struct {
    QueryInterface: *const fn (This: [*c]IVirtualDesktop, riid: *const win32.Guid, ppvObject: [*c]?*anyopaque) callconv(.c) win32.HRESULT,
    AddRef: *const fn (This: [*c]IVirtualDesktop) callconv(.c) u32,
    Release: *const fn (This: [*c]IVirtualDesktop) callconv(.c) u32,
    IsViewVisible: *const fn (This: [*c]IVirtualDesktop, pView: [*c]IApplicationView, pVisible: [*c]c_int) callconv(.c) win32.HRESULT,
    GetID: *const fn (This: [*c]IVirtualDesktop, pGuid: [*c]win32.Guid) callconv(.c) win32.HRESULT,
};

pub const IVirtualDesktopManager = extern struct {
    lpVtbl: [*c]const IVirtualDesktopManagerVtbl,

    pub fn QueryInterface(self: *IVirtualDesktopManager, riid: *const win32.Guid, ppvObject: [*c]?*anyopaque) win32.HRESULT {
        return self.lpVtbl.*.QueryInterface(self, riid, ppvObject);
    }
    pub fn AddRef(self: *IVirtualDesktopManager) u32 {
        return self.lpVtbl.*.AddRef(self);
    }
    pub fn Release(self: *IVirtualDesktopManager) u32 {
        return self.lpVtbl.*.Release(self);
    }
    pub fn IsWindowOnCurrentVirtualDesktop(self: *IVirtualDesktopManager, topLevelWindow: win32.HWND, onCurrentDesktop: [*c]win32.BOOL) win32.HRESULT {
        return self.lpVtbl.*.IsWindowOnCurrentVirtualDesktop(self, topLevelWindow, onCurrentDesktop);
    }
    pub fn GetWindowDesktopId(self: *IVirtualDesktopManager, topLevelWindow: win32.HWND, desktopId: [*c]win32.Guid) win32.HRESULT {
        return self.lpVtbl.*.GetWindowDesktopId(self, topLevelWindow, desktopId);
    }
    pub fn MoveWindowToDesktop(self: *IVirtualDesktopManager, topLevelWindow: win32.HWND, desktopId: *const win32.Guid) win32.HRESULT {
        return self.lpVtbl.*.MoveWindowToDesktop(self, topLevelWindow, desktopId);
    }

    pub fn create() !*IVirtualDesktopManager {
        var virtualDesktopManager: *IVirtualDesktopManager = undefined;
        const hr = win32.CoCreateInstance(&CLSID_VirtualDesktopManager, null, win32.CLSCTX_ALL, &IID_IVirtualDesktopManager, @ptrCast(&virtualDesktopManager));
        if (hr == 0) {
            return virtualDesktopManager;
        } else {
            return error.FailedToCreateComObject;
        }
    }
};

const IVirtualDesktopManagerVtbl = extern struct {
    QueryInterface: *const fn (This: [*c]IVirtualDesktopManager, riid: *const win32.Guid, ppvObject: [*c]?*anyopaque) callconv(.c) win32.HRESULT,
    AddRef: *const fn (This: [*c]IVirtualDesktopManager) callconv(.c) u32,
    Release: *const fn (This: [*c]IVirtualDesktopManager) callconv(.c) u32,
    IsWindowOnCurrentVirtualDesktop: *const fn (This: [*c]IVirtualDesktopManager, topLevelWindow: win32.HWND, onCurrentDesktop: [*c]win32.BOOL) callconv(.c) win32.HRESULT,
    GetWindowDesktopId: *const fn (This: [*c]IVirtualDesktopManager, topLevelWindow: win32.HWND, desktopId: [*c]win32.Guid) callconv(.c) win32.HRESULT,
    MoveWindowToDesktop: *const fn (This: [*c]IVirtualDesktopManager, topLevelWindow: win32.HWND, desktopId: *const win32.Guid) callconv(.c) win32.HRESULT,
};

pub const IVirtualDesktopManagerInternal = extern struct {
    lpVtbl: [*c]const IVirtualDesktopManagerInternalVtbl,
    matched_iid_index: usize = 0,

    pub fn QueryInterface(self: *IVirtualDesktopManagerInternal, riid: *const win32.Guid, ppvObject: [*c]?*anyopaque) win32.HRESULT {
        return self.lpVtbl.*.QueryInterface(self, riid, ppvObject);
    }
    pub fn AddRef(self: *IVirtualDesktopManagerInternal) u32 {
        return self.lpVtbl.*.AddRef(self);
    }
    pub fn Release(self: *IVirtualDesktopManagerInternal) u32 {
        return self.lpVtbl.*.Release(self);
    }
    pub fn GetCount(self: *IVirtualDesktopManagerInternal, pCount: [*c]c_int) win32.HRESULT {
        return self.lpVtbl.*.GetCount(self, pCount);
    }
    pub fn MoveViewToDesktop(self: *IVirtualDesktopManagerInternal, pView: [*c]IApplicationView, pDesktop: [*c]IVirtualDesktop) win32.HRESULT {
        return self.lpVtbl.*.MoveViewToDesktop(self, pView, pDesktop);
    }
    pub fn CanViewMoveDesktops(self: *IVirtualDesktopManagerInternal, pView: [*c]IApplicationView, pfCanViewMoveDesktops: [*c]c_int) win32.HRESULT {
        return self.lpVtbl.*.CanViewMoveDesktops(self, pView, pfCanViewMoveDesktops);
    }
    pub fn GetCurrentDesktop(self: *IVirtualDesktopManagerInternal, desktop: [*c][*c]IVirtualDesktop) win32.HRESULT {
        return self.lpVtbl.*.GetCurrentDesktop(self, desktop);
    }
    pub fn GetDesktops(self: *IVirtualDesktopManagerInternal, ppDesktops: [*c][*c]IObjectArray) win32.HRESULT {
        return self.lpVtbl.*.GetDesktops(self, ppDesktops);
    }
    pub fn GetAdjacentDesktop(self: *IVirtualDesktopManagerInternal, pDesktopReference: [*c]IVirtualDesktop, uDirection: AdjacentDesktop, ppAdjacentDesktop: [*c][*c]IVirtualDesktop) win32.HRESULT {
        return self.lpVtbl.*.GetAdjacentDesktop(self, pDesktopReference, uDirection, ppAdjacentDesktop);
    }
    pub fn SwitchDesktop(self: *IVirtualDesktopManagerInternal, pDesktop: [*c]IVirtualDesktop) win32.HRESULT {
        return self.lpVtbl.*.SwitchDesktop(self, pDesktop);
    }
    pub fn SwitchDesktopAndMoveForegroundView(self: *IVirtualDesktopManagerInternal, pDesktop: [*c]IVirtualDesktop) win32.HRESULT {
        return self.lpVtbl.*.SwitchDesktopAndMoveForegroundView(self, pDesktop);
    }
    pub fn CreateDesktopW(self: *IVirtualDesktopManagerInternal, ppNewDesktop: [*c][*c]IVirtualDesktop) win32.HRESULT {
        return self.lpVtbl.*.CreateDesktopW(self, ppNewDesktop);
    }
    pub fn MoveDesktop(self: *IVirtualDesktopManagerInternal, pDesktop: [*c]IVirtualDesktop, index: c_int) win32.HRESULT {
        return self.lpVtbl.*.MoveDesktop(self, pDesktop, index);
    }
    pub fn RemoveDesktop(self: *IVirtualDesktopManagerInternal, pRemove: [*c]IVirtualDesktop, pFallbackDesktop: [*c]IVirtualDesktop) win32.HRESULT {
        return self.lpVtbl.*.RemoveDesktop(self, pRemove, pFallbackDesktop);
    }
    pub fn FindDesktop(self: *IVirtualDesktopManagerInternal, desktopId: *const win32.Guid, ppDesktop: [*c][*c]IVirtualDesktop) win32.HRESULT {
        return self.lpVtbl.*.FindDesktop(self, desktopId, ppDesktop);
    }

    pub fn create(serviceProvider: *IServiceProvider) !*IVirtualDesktopManagerInternal {
        var virtualDesktopManagerInternal: *IVirtualDesktopManagerInternal = undefined;
        for (IID_IVirtualDesktopManagerInternal_Candidates, 0..) |cand, i| {
            const hr = serviceProvider.QueryService(&CLSID_VirtualDesktopAPI_Unknown, &cand.iid, @ptrCast(&virtualDesktopManagerInternal));
            if (hr == 0) {
                std.log.scoped(.VirtualDesktop).info("QueryService matched IID: {s}", .{cand.name});
                virtualDesktopManagerInternal.matched_iid_index = i;
                return virtualDesktopManagerInternal;
            } else {
                std.log.scoped(.VirtualDesktop).info("QueryService failed for {s}, hr=0x{X:0>8}", .{ cand.name, @as(u32, @bitCast(hr)) });
            }
        }
        return error.FailedToCreateComObject;
    }
};

const IVirtualDesktopManagerInternalVtbl = extern struct {
    QueryInterface: *const fn (This: [*c]IVirtualDesktopManagerInternal, riid: *const win32.Guid, ppvObject: [*c]?*anyopaque) callconv(.c) win32.HRESULT,
    AddRef: *const fn (This: [*c]IVirtualDesktopManagerInternal) callconv(.c) u32,
    Release: *const fn (This: [*c]IVirtualDesktopManagerInternal) callconv(.c) u32,
    GetCount: *const fn (This: [*c]IVirtualDesktopManagerInternal, pCount: [*c]c_int) callconv(.c) win32.HRESULT,
    MoveViewToDesktop: *const fn (This: [*c]IVirtualDesktopManagerInternal, pView: [*c]IApplicationView, pDesktop: [*c]IVirtualDesktop) callconv(.c) win32.HRESULT,
    CanViewMoveDesktops: *const fn (This: [*c]IVirtualDesktopManagerInternal, pView: [*c]IApplicationView, pfCanViewMoveDesktops: [*c]c_int) callconv(.c) win32.HRESULT,
    GetCurrentDesktop: *const fn (This: [*c]IVirtualDesktopManagerInternal, desktop: [*c][*c]IVirtualDesktop) callconv(.c) win32.HRESULT,
    GetDesktops: *const fn (This: [*c]IVirtualDesktopManagerInternal, ppDesktops: [*c][*c]IObjectArray) callconv(.c) win32.HRESULT,
    GetAdjacentDesktop: *const fn (This: [*c]IVirtualDesktopManagerInternal, pDesktopReference: [*c]IVirtualDesktop, uDirection: AdjacentDesktop, ppAdjacentDesktop: [*c][*c]IVirtualDesktop) callconv(.c) win32.HRESULT,
    SwitchDesktop: *const fn (This: [*c]IVirtualDesktopManagerInternal, pDesktop: [*c]IVirtualDesktop) callconv(.c) win32.HRESULT,
    SwitchDesktopAndMoveForegroundView: *const fn (This: [*c]IVirtualDesktopManagerInternal, pDesktop: [*c]IVirtualDesktop) callconv(.c) win32.HRESULT,
    CreateDesktopW: *const fn (This: [*c]IVirtualDesktopManagerInternal, ppNewDesktop: [*c][*c]IVirtualDesktop) callconv(.c) win32.HRESULT,
    MoveDesktop: *const fn (This: [*c]IVirtualDesktopManagerInternal, pDesktop: [*c]IVirtualDesktop, index: c_int) callconv(.c) win32.HRESULT,
    RemoveDesktop: *const fn (This: [*c]IVirtualDesktopManagerInternal, pRemove: [*c]IVirtualDesktop, pFallbackDesktop: [*c]IVirtualDesktop) callconv(.c) win32.HRESULT,
    FindDesktop: *const fn (This: [*c]IVirtualDesktopManagerInternal, desktopId: *const win32.Guid, ppDesktop: [*c][*c]IVirtualDesktop) callconv(.c) win32.HRESULT,
};

pub fn getApplicationViewCollection(serviceProvider: *IServiceProvider) !*IApplicationViewCollection {
    var collection: *IApplicationViewCollection = undefined;
    const hr = serviceProvider.QueryService(&IID_IApplicationViewCollection, &IID_IApplicationViewCollection, @ptrCast(&collection));
    if (hr == 0) {
        return collection;
    } else {
        return error.FailedToGetApplicationViewCollection;
    }
}
