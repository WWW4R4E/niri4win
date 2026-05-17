const std = @import("std");
const niri4win = @import("../root.zig");
const win32 = niri4win.win32;

pub const Color = win32.D2D_COLOR_F;
const U = win32.IUnknown;

const NOISE_DLL = "Windows.UI.Xaml.Controls.dll";
const NOISE_RESOURCE_ID = 2000;

const TINT_COLOR = Color{ .r = 32.0 / 255.0, .g = 32.0 / 255.0, .b = 38.0 / 255.0, .a = 0.7 };
const LUMINOSITY_COLOR = Color{ .r = 32.0 / 255.0, .g = 32.0 / 255.0, .b = 38.0 / 255.0, .a = 0.9 };
const NOISE_OPACITY: f32 = 0.03;
const BLUR_AMOUNT: f32 = 30.0;

pub const D2DContext = struct {
    ctx: *win32.ID2D1DeviceContext,
    swap: *win32.IDXGISwapChain1,
    wf: *win32.IWICImagingFactory,
    bg: ?*win32.ID2D1Bitmap1,
    bg_blur: ?*win32.ID2D1Effect,
    width: u32,
    height: u32,
    img_w: u32,
    img_h: u32,
    d3d_device: *win32.ID3D11Device,
    d3d_context: *win32.ID3D11DeviceContext,
    // Acrylic resources
    wallpaper_bmp: ?*win32.ID2D1Bitmap1,
    noise_bmp: ?*win32.ID2D1Bitmap1,
    blur_effect: ?*win32.ID2D1Effect,
    blend_luminosity: ?*win32.ID2D1Effect,
    blend_color: ?*win32.ID2D1Effect,
    blend_noise: ?*win32.ID2D1Effect,
    flood_tint: ?*win32.ID2D1Effect,
    flood_luminosity: ?*win32.ID2D1Effect,
    border_effect: ?*win32.ID2D1Effect,
    opacity_effect: ?*win32.ID2D1Effect,
    acrylic_ready: bool,

    pub fn init(hwnd: win32.HWND, width: u32, height: u32) !D2DContext {
        var d3d_device: ?*win32.ID3D11Device = null;
        var d3d_context: ?*win32.ID3D11DeviceContext = null;
        const feature_levels = [_]win32.D3D_FEATURE_LEVEL{win32.D3D_FEATURE_LEVEL_11_0};
        var hr = win32.D3D11CreateDevice(
            null,
            .HARDWARE,
            null,
            win32.D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            &feature_levels,
            feature_levels.len,
            win32.D3D11_SDK_VERSION,
            @ptrCast(&d3d_device),
            null,
            @ptrCast(&d3d_context),
        );
        if (hr != win32.S_OK) return error.D3D11CreateDeviceFailed;

        var dxgi_device: ?*win32.IDXGIDevice = null;
        hr = d3d_device.?.IUnknown.QueryInterface(win32.IID_IDXGIDevice, @ptrCast(&dxgi_device));
        if (hr != win32.S_OK) return error.QueryDxgiDeviceFailed;

        var adapter: ?*win32.IDXGIAdapter = null;
        hr = dxgi_device.?.GetAdapter(@ptrCast(&adapter));
        if (hr != win32.S_OK) return error.GetAdapterFailed;

        var dxgi_factory: ?*win32.IDXGIFactory2 = null;
        hr = adapter.?.IDXGIObject.GetParent(win32.IID_IDXGIFactory2, @ptrCast(&dxgi_factory));
        if (hr != win32.S_OK) return error.QueryDxgiFactoryFailed;
        _ = (@as(*const U, @ptrCast(adapter.?))).Release();

        const desc = win32.DXGI_SWAP_CHAIN_DESC1{
            .Width = width,
            .Height = height,
            .Format = .B8G8R8A8_UNORM,
            .Stereo = 0,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .BufferUsage = 0x20,
            .BufferCount = 2,
            .Scaling = .STRETCH,
            .SwapEffect = .FLIP_DISCARD,
            .AlphaMode = .IGNORE,
            .Flags = 0,
        };
        var swap: ?*win32.IDXGISwapChain1 = null;
        hr = dxgi_factory.?.CreateSwapChainForHwnd(@ptrCast(d3d_device.?), hwnd, &desc, null, null, @ptrCast(&swap));
        if (hr != win32.S_OK) return error.CreateSwapChainFailed;
        _ = (@as(*const U, @ptrCast(dxgi_factory.?))).Release();

        var d2d_factory: ?*win32.ID2D1Factory1 = null;
        hr = win32.D2D1CreateFactory(.SINGLE_THREADED, win32.IID_ID2D1Factory1, null, @ptrCast(&d2d_factory));
        if (hr != win32.S_OK) return error.CreateD2DFactoryFailed;

        var d2d_device: ?*win32.ID2D1Device = null;
        hr = d2d_factory.?.CreateDevice(@ptrCast(dxgi_device.?), @ptrCast(&d2d_device));
        if (hr != win32.S_OK) return error.CreateD2DDeviceFailed;
        _ = (@as(*const U, @ptrCast(d2d_factory.?))).Release();
        _ = (@as(*const U, @ptrCast(dxgi_device.?))).Release();

        var ctx: ?*win32.ID2D1DeviceContext = null;
        hr = d2d_device.?.CreateDeviceContext(.{}, @ptrCast(&ctx));
        if (hr != win32.S_OK) return error.CreateD2DDeviceContextFailed;
        _ = (@as(*const U, @ptrCast(d2d_device.?))).Release();

        var wf: ?*win32.IWICImagingFactory = null;
        hr = win32.CoCreateInstance(&win32.CLSID_WICImagingFactory, null, win32.CLSCTX_INPROC_SERVER, win32.IID_IWICImagingFactory, @ptrCast(&wf));
        if (hr != win32.S_OK) return error.CreateWicFactoryFailed;

        var result = D2DContext{
            .ctx = ctx.?,
            .swap = swap.?,
            .wf = wf.?,
            .bg = null,
            .bg_blur = null,
            .width = width,
            .height = height,
            .img_w = 0,
            .img_h = 0,
            .d3d_device = d3d_device.?,
            .d3d_context = d3d_context.?,
            .wallpaper_bmp = null,
            .noise_bmp = null,
            .blur_effect = null,
            .blend_luminosity = null,
            .blend_color = null,
            .blend_noise = null,
            .flood_tint = null,
            .flood_luminosity = null,
            .border_effect = null,
            .opacity_effect = null,
            .acrylic_ready = false,
        };
        if (!result.refreshTarget()) return error.CreateTargetFailed;
        return result;
    }

    pub fn deinit(self: *D2DContext) void {
        if (self.bg_blur) |e| _ = (@as(*const U, @ptrCast(e))).Release();
        if (self.bg) |b| _ = (@as(*const U, @ptrCast(b))).Release();
        if (self.wallpaper_bmp) |b| _ = (@as(*const U, @ptrCast(b))).Release();
        if (self.noise_bmp) |b| _ = (@as(*const U, @ptrCast(b))).Release();
        if (self.blur_effect) |e| _ = (@as(*const U, @ptrCast(e))).Release();
        if (self.blend_luminosity) |e| _ = (@as(*const U, @ptrCast(e))).Release();
        if (self.blend_color) |e| _ = (@as(*const U, @ptrCast(e))).Release();
        if (self.blend_noise) |e| _ = (@as(*const U, @ptrCast(e))).Release();
        if (self.flood_tint) |e| _ = (@as(*const U, @ptrCast(e))).Release();
        if (self.flood_luminosity) |e| _ = (@as(*const U, @ptrCast(e))).Release();
        if (self.border_effect) |e| _ = (@as(*const U, @ptrCast(e))).Release();
        if (self.opacity_effect) |e| _ = (@as(*const U, @ptrCast(e))).Release();
        self.ctx.SetTarget(null);
        _ = (@as(*const U, @ptrCast(self.ctx))).Release();
        _ = (@as(*const U, @ptrCast(self.swap))).Release();
        _ = (@as(*const U, @ptrCast(self.wf))).Release();
        _ = (@as(*const U, @ptrCast(self.d3d_context))).Release();
        _ = (@as(*const U, @ptrCast(self.d3d_device))).Release();
    }

    pub fn resize(self: *D2DContext, w: u32, h: u32) void {
        if (w == 0 or h == 0) return;
        self.width = w;
        self.height = h;
        self.ctx.SetTarget(null);
        _ = self.swap.IDXGISwapChain.ResizeBuffers(0, w, h, .UNKNOWN, 0);
        _ = self.refreshTarget();
    }

    pub fn beginDraw(self: *D2DContext) void {
        self.ctx.ID2D1RenderTarget.BeginDraw();
        self.initAcrylic();
        self.renderAcrylic();
    }

    pub fn endDraw(self: *D2DContext) void {
        _ = self.ctx.ID2D1RenderTarget.EndDraw(null, null);
        _ = self.swap.IDXGISwapChain.Present(1, 0);
        _ = self.refreshTarget();
    }

    fn refreshTarget(self: *D2DContext) bool {
        var back_buffer: ?*win32.ID3D11Texture2D = null;
        if (self.swap.IDXGISwapChain.GetBuffer(0, win32.IID_ID3D11Texture2D, @ptrCast(&back_buffer)) != win32.S_OK) return false;
        defer _ = (@as(*const U, @ptrCast(back_buffer.?))).Release();

        var surface: ?*win32.IDXGISurface = null;
        if (back_buffer.?.IUnknown.QueryInterface(win32.IID_IDXGISurface, @ptrCast(&surface)) != win32.S_OK) return false;
        defer _ = (@as(*const U, @ptrCast(surface.?))).Release();

        const target_props = win32.D2D1_BITMAP_PROPERTIES1{
            .pixelFormat = .{ .format = .B8G8R8A8_UNORM, .alphaMode = .IGNORE },
            .dpiX = 96,
            .dpiY = 96,
            .bitmapOptions = .{ .TARGET = 1, .CANNOT_DRAW = 1 },
            .colorContext = null,
        };
        var target: ?*win32.ID2D1Bitmap1 = null;
        if (self.ctx.CreateBitmapFromDxgiSurface(surface, &target_props, @ptrCast(&target)) != win32.S_OK) return false;
        self.ctx.SetTarget(@ptrCast(target.?));
        _ = (@as(*const U, @ptrCast(target.?))).Release();
        return true;
    }

    pub fn loadBackground(self: *D2DContext, wpath: [:0]const u16) void {
        var decoder: ?*win32.IWICBitmapDecoder = null;
        if (self.wf.CreateDecoderFromFilename(wpath.ptr, null, 0x80000000, .DecodeMetadataCacheOnLoad, &decoder) != win32.S_OK) return;
        defer _ = (@as(*const U, @ptrCast(decoder.?))).Release();

        var frame: ?*win32.IWICBitmapFrameDecode = null;
        if (decoder.?.GetFrame(0, &frame) != win32.S_OK) return;
        defer _ = (@as(*const U, @ptrCast(frame.?))).Release();

        _ = frame.?.IWICBitmapSource.GetSize(&self.img_w, &self.img_h);

        var converter: ?*win32.IWICFormatConverter = null;
        if (self.wf.CreateFormatConverter(&converter) != win32.S_OK) return;
        defer _ = (@as(*const U, @ptrCast(converter.?))).Release();

        const fmt: *win32.zig.Guid = @ptrCast(@constCast(&win32.GUID_WICPixelFormat32bppPBGRA));
        if (converter.?.Initialize(@ptrCast(frame.?), fmt, .itmapDitherTypeNone, null, 0.0, .itmapPaletteTypeCustom) != win32.S_OK) return;

        const bitmap_props = win32.D2D1_BITMAP_PROPERTIES1{
            .pixelFormat = .{ .format = .B8G8R8A8_UNORM, .alphaMode = .PREMULTIPLIED },
            .dpiX = 96,
            .dpiY = 96,
            .bitmapOptions = .{},
            .colorContext = null,
        };
        var bitmap: ?*win32.ID2D1Bitmap1 = null;
        if (self.ctx.CreateBitmapFromWicBitmap(@ptrCast(converter.?), &bitmap_props, @ptrCast(&bitmap)) != win32.S_OK) return;

        var effect: ?*win32.ID2D1Effect = null;
        if (self.ctx.CreateEffect(&win32.CLSID_D2D1GaussianBlur, @ptrCast(&effect)) != win32.S_OK) {
            if (self.bg) |old| _ = (@as(*const U, @ptrCast(old))).Release();
            self.bg = bitmap;
            return;
        }

        effect.?.SetInput(0, @ptrCast(bitmap.?), 0);
        const sigma: f32 = 14.0;
        var border_mode: u32 = @intFromEnum(win32.common.D2D1_BORDER_MODE.HARD);
        _ = effect.?.ID2D1Properties.SetValue(@intFromEnum(win32.D2D1_GAUSSIANBLUR_PROP.STANDARD_DEVIATION), .FLOAT, @ptrCast(&sigma), @sizeOf(f32));
        _ = effect.?.ID2D1Properties.SetValue(@intFromEnum(win32.D2D1_GAUSSIANBLUR_PROP_BORDER_MODE), .ENUM, @ptrCast(&border_mode), @sizeOf(u32));

        if (self.bg_blur) |old| _ = (@as(*const U, @ptrCast(old))).Release();
        if (self.bg) |old| _ = (@as(*const U, @ptrCast(old))).Release();
        self.bg = bitmap;
        self.bg_blur = effect;
    }

    pub fn drawBackground(self: *D2DContext) void {
        if (self.bg) |bmp| {
            const iw = @as(f32, @floatFromInt(self.img_w));
            const ih = @as(f32, @floatFromInt(self.img_h));
            const ww = @as(f32, @floatFromInt(self.width));
            const wh = @as(f32, @floatFromInt(self.height));
            const dx = if (iw > ww) 0 else (ww - iw) / 2;
            const dy = wh - ih;
            if (self.bg_blur) |effect| {
                const p = win32.common.D2D_POINT_2F{ .x = dx, .y = dy };
                var output: ?*win32.ID2D1Image = null;
                effect.GetOutput(&output);
                if (output) |image| {
                    self.ctx.DrawImage(image, &p, null, .LINEAR, .SOURCE_OVER);
                    _ = (@as(*const U, @ptrCast(image))).Release();
                }
            } else {
                const r = win32.common.D2D_RECT_F{ .left = dx, .top = dy, .right = dx + iw, .bottom = dy + ih };
                self.ctx.ID2D1RenderTarget.DrawBitmap(@ptrCast(bmp), &r, 1.0, .LINEAR, null);
            }
        }
    }

    pub fn getBrush(self: *D2DContext) !*win32.ID2D1SolidColorBrush {
        var brush: ?*win32.ID2D1SolidColorBrush = null;
        const hr = self.ctx.ID2D1RenderTarget.CreateSolidColorBrush(&.{ .r = 0.15, .g = 0.15, .b = 0.18, .a = 0.6 }, null, @ptrCast(&brush));
        if (hr != win32.S_OK) return error.CreateTargetFailed;
        return brush.?;
    }

    pub fn loadIcon(self: *D2DContext, wpath: [:0]const u16) !*win32.ID2D1Bitmap {
        var decoder: ?*win32.IWICBitmapDecoder = null;
        var hr = self.wf.CreateDecoderFromFilename(wpath.ptr, null, 0x80000000, .DecodeMetadataCacheOnLoad, &decoder);
        if (hr != win32.S_OK) return error.Failed;
        defer _ = (@as(*const U, @ptrCast(decoder.?))).Release();

        var frame: ?*win32.IWICBitmapFrameDecode = null;
        hr = decoder.?.GetFrame(0, &frame);
        if (hr != win32.S_OK) return error.Failed;
        defer _ = (@as(*const U, @ptrCast(frame.?))).Release();

        var converter: ?*win32.IWICFormatConverter = null;
        hr = self.wf.CreateFormatConverter(&converter);
        if (hr != win32.S_OK) return error.Failed;
        defer _ = (@as(*const U, @ptrCast(converter.?))).Release();

        const fmt: *win32.zig.Guid = @ptrCast(@constCast(&win32.GUID_WICPixelFormat32bppPBGRA));
        hr = converter.?.Initialize(@ptrCast(frame.?), fmt, .itmapDitherTypeNone, null, 0.0, .itmapPaletteTypeCustom);
        if (hr != win32.S_OK) return error.Failed;

        var bitmap: ?*win32.ID2D1Bitmap1 = null;
        const props = win32.D2D1_BITMAP_PROPERTIES1{
            .pixelFormat = .{ .format = .B8G8R8A8_UNORM, .alphaMode = .PREMULTIPLIED },
            .dpiX = 96,
            .dpiY = 96,
            .bitmapOptions = .{},
            .colorContext = null,
        };
        hr = self.ctx.CreateBitmapFromWicBitmap(@ptrCast(converter.?), &props, @ptrCast(&bitmap));
        if (hr != win32.S_OK) return error.Failed;

        return @ptrCast(bitmap.?);
    }

    /// 将 HICON 转换为 ID2D1Bitmap，支持 LINEAR 插值缩放
    pub fn hiconToBitmap(self: *D2DContext, hIcon: win32.HICON) !*win32.ID2D1Bitmap {
        var wic_bitmap: ?*win32.IWICBitmap = null;
        var hr = self.wf.CreateBitmapFromHICON(hIcon, @ptrCast(&wic_bitmap));
        if (hr != win32.S_OK) return error.Failed;
        defer _ = (@as(*const U, @ptrCast(wic_bitmap.?))).Release();

        var bitmap: ?*win32.ID2D1Bitmap1 = null;
        const props = win32.D2D1_BITMAP_PROPERTIES1{
            .pixelFormat = .{ .format = .B8G8R8A8_UNORM, .alphaMode = .PREMULTIPLIED },
            .dpiX = 96,
            .dpiY = 96,
            .bitmapOptions = .{},
            .colorContext = null,
        };
        hr = self.ctx.CreateBitmapFromWicBitmap(@ptrCast(wic_bitmap.?), &props, @ptrCast(&bitmap));
        if (hr != win32.S_OK) return error.Failed;
        return @ptrCast(bitmap.?);
    }

    // ──────────── Acrylic Background ────────────

    /// 加载桌面壁纸作为 acrylic 背景源
    pub fn loadWallpaper(self: *D2DContext) void {
        // 获取壁纸路径
        var buf: [512:0]u16 = @splat(0);
        _ = win32.SystemParametersInfoW(win32.SPI_GETDESKWALLPAPER, buf.len, &buf, .{});
        if (buf[0] == 0) return;

        // 通过 WIC 解码壁纸
        var decoder: ?*win32.IWICBitmapDecoder = null;
        if (self.wf.CreateDecoderFromFilename(&buf, null, 0x80000000, .DecodeMetadataCacheOnLoad, &decoder) != win32.S_OK) return;
        defer _ = (@as(*const U, @ptrCast(decoder.?))).Release();

        var frame: ?*win32.IWICBitmapFrameDecode = null;
        if (decoder.?.GetFrame(0, &frame) != win32.S_OK) return;
        defer _ = (@as(*const U, @ptrCast(frame.?))).Release();

        var converter: ?*win32.IWICFormatConverter = null;
        if (self.wf.CreateFormatConverter(&converter) != win32.S_OK) return;
        defer _ = (@as(*const U, @ptrCast(converter.?))).Release();

        const fmt: *win32.zig.Guid = @ptrCast(@constCast(&win32.GUID_WICPixelFormat32bppPBGRA));
        if (converter.?.Initialize(@ptrCast(frame.?), fmt, .itmapDitherTypeNone, null, 0.0, .itmapPaletteTypeCustom) != win32.S_OK) return;

        const props = win32.D2D1_BITMAP_PROPERTIES1{
            .pixelFormat = .{ .format = .B8G8R8A8_UNORM, .alphaMode = .PREMULTIPLIED },
            .dpiX = 96,
            .dpiY = 96,
            .bitmapOptions = .{},
            .colorContext = null,
        };
        var bmp: ?*win32.ID2D1Bitmap1 = null;
        if (self.ctx.CreateBitmapFromWicBitmap(@ptrCast(converter.?), &props, @ptrCast(&bmp)) == win32.S_OK) {
            if (self.wallpaper_bmp) |old| _ = (@as(*const U, @ptrCast(old))).Release();
            self.wallpaper_bmp = bmp;
            std.log.scoped(.D2D).info("壁纸加载成功", .{});
        }
    }

    /// 从系统 DLL 加载噪声纹理
    pub fn loadNoiseTexture(self: *D2DContext) void {
        const dll = win32.LoadLibraryExW(win32.L(NOISE_DLL), null, win32.LOAD_LIBRARY_FLAGS{ .LOAD_LIBRARY_SEARCH_SYSTEM32 = 1, .LOAD_LIBRARY_AS_DATAFILE = 1, .LOAD_LIBRARY_AS_IMAGE_RESOURCE = 1 });
        if (dll == null) {
            std.log.scoped(.D2D).err("加载噪声DLL失败", .{});
            return;
        }
        defer _ = win32.FreeLibrary(dll.?);

        const res = win32.FindResourceW(dll.?, @ptrFromInt(NOISE_RESOURCE_ID), win32.RT_RCDATA);
        if (res == null) return;
        const glob = win32.LoadResource(dll.?, res.?);
        if (glob == 0) return;
        const size = win32.SizeofResource(dll.?, res.?);
        if (size == 0) return;
        const data = win32.LockResource(glob);
        if (data == null) return;

        var stream: ?*win32.IStream = null;
        stream = win32.SHCreateMemStream(@ptrCast(data.?), size);
        if (stream == null) return;
        defer _ = stream.?.IUnknown.Release();

        var decoder: ?*win32.IWICBitmapDecoder = null;
        if (self.wf.CreateDecoderFromStream(stream.?, null, .DecodeMetadataCacheOnDemand, &decoder) != win32.S_OK) return;
        defer _ = (@as(*const U, @ptrCast(decoder.?))).Release();

        var frame: ?*win32.IWICBitmapFrameDecode = null;
        if (decoder.?.GetFrame(0, &frame) != win32.S_OK) return;
        defer _ = (@as(*const U, @ptrCast(frame.?))).Release();

        var converter: ?*win32.IWICFormatConverter = null;
        if (self.wf.CreateFormatConverter(&converter) != win32.S_OK) return;
        defer _ = (@as(*const U, @ptrCast(converter.?))).Release();

        const fmt: *win32.zig.Guid = @ptrCast(@constCast(&win32.GUID_WICPixelFormat32bppPBGRA));
        if (converter.?.Initialize(@ptrCast(frame.?), fmt, .itmapDitherTypeNone, null, 0.0, .itmapPaletteTypeCustom) != win32.S_OK) return;

        const props = win32.D2D1_BITMAP_PROPERTIES1{
            .pixelFormat = .{ .format = .B8G8R8A8_UNORM, .alphaMode = .PREMULTIPLIED },
            .dpiX = 96,
            .dpiY = 96,
            .bitmapOptions = .{},
            .colorContext = null,
        };
        var bmp: ?*win32.ID2D1Bitmap1 = null;
        if (self.ctx.CreateBitmapFromWicBitmap(@ptrCast(converter.?), &props, @ptrCast(&bmp)) == win32.S_OK) {
            if (self.noise_bmp) |old| _ = (@as(*const U, @ptrCast(old))).Release();
            self.noise_bmp = bmp;
            std.log.scoped(.D2D).info("噪声纹理加载成功", .{});
        }
    }

    /// 通过 GetOutput 获取 effect 的输出图像并设为另一 effect 的输入
    fn setEffectInput(dst: *win32.ID2D1Effect, idx: u32, src: *win32.ID2D1Effect) void {
        var out: ?*win32.ID2D1Image = null;
        src.GetOutput(&out);
        dst.SetInput(idx, out.?, 0);
        _ = (@as(*const U, @ptrCast(out.?))).Release();
    }

    /// 创建 acrylic D2D effect 链（缓存复用）
    pub fn initAcrylic(self: *D2DContext) void {
        if (self.acrylic_ready) return;

        self.loadWallpaper();
        self.loadNoiseTexture();
        if (self.wallpaper_bmp == null) {
            std.log.scoped(.D2D).info("无壁纸，使用暗色背景", .{});
            return;
        }

        // 1. 高斯模糊
        var effect: ?*win32.ID2D1Effect = null;
        if (self.ctx.CreateEffect(&win32.CLSID_D2D1GaussianBlur, @ptrCast(&effect)) != win32.S_OK) return;
        const sigma = BLUR_AMOUNT;
        var border_mode: u32 = @intFromEnum(win32.D2D1_BORDER_MODE.HARD);
        effect.?.SetInput(0, @ptrCast(self.wallpaper_bmp.?), 0); // bitmap → 直接传
        _ = effect.?.ID2D1Properties.SetValue(@intFromEnum(win32.D2D1_GAUSSIANBLUR_PROP.STANDARD_DEVIATION), .FLOAT, @ptrCast(&sigma), @sizeOf(f32));
        _ = effect.?.ID2D1Properties.SetValue(@intFromEnum(win32.D2D1_GAUSSIANBLUR_PROP_BORDER_MODE), .ENUM, @ptrCast(&border_mode), @sizeOf(u32));
        self.blur_effect = effect;

        // 2. 亮度颜色 Flood
        effect = null;
        if (self.ctx.CreateEffect(&win32.CLSID_D2D1Flood, @ptrCast(&effect)) != win32.S_OK) return;
        {
            var col = [4]f32{ LUMINOSITY_COLOR.r, LUMINOSITY_COLOR.g, LUMINOSITY_COLOR.b, LUMINOSITY_COLOR.a };
            _ = effect.?.ID2D1Properties.SetValue(@intFromEnum(win32.D2D1_FLOOD_PROP.COLOR), .VECTOR4, @ptrCast(&col), @sizeOf([4]f32));
        }
        self.flood_luminosity = effect;

        // 3. 亮度混合（Blend Color 模式 → 因 bug 实为 Luminosity）
        effect = null;
        if (self.ctx.CreateEffect(&win32.CLSID_D2D1Blend, @ptrCast(&effect)) != win32.S_OK) return;
        {
            var mode: u32 = @intFromEnum(win32.D2D1_BLEND_MODE.COLOR);
            _ = effect.?.ID2D1Properties.SetValue(@intFromEnum(win32.D2D1_BLEND_PROP.MODE), .ENUM, @ptrCast(&mode), @sizeOf(u32));
            setEffectInput(effect.?, 0, self.blur_effect.?);
            setEffectInput(effect.?, 1, self.flood_luminosity.?);
        }
        self.blend_luminosity = effect;

        // 4. 色调颜色 Flood
        effect = null;
        if (self.ctx.CreateEffect(&win32.CLSID_D2D1Flood, @ptrCast(&effect)) != win32.S_OK) return;
        {
            var col = [4]f32{ TINT_COLOR.r, TINT_COLOR.g, TINT_COLOR.b, TINT_COLOR.a };
            _ = effect.?.ID2D1Properties.SetValue(@intFromEnum(win32.D2D1_FLOOD_PROP.COLOR), .VECTOR4, @ptrCast(&col), @sizeOf([4]f32));
        }
        self.flood_tint = effect;

        // 5. 颜色混合（Blend Luminosity 模式 → 因 bug 实为 Color）
        effect = null;
        if (self.ctx.CreateEffect(&win32.CLSID_D2D1Blend, @ptrCast(&effect)) != win32.S_OK) return;
        {
            var mode: u32 = @intFromEnum(win32.D2D1_BLEND_MODE.LUMINOSITY);
            _ = effect.?.ID2D1Properties.SetValue(@intFromEnum(win32.D2D1_BLEND_PROP.MODE), .ENUM, @ptrCast(&mode), @sizeOf(u32));
            setEffectInput(effect.?, 0, self.blend_luminosity.?);
            setEffectInput(effect.?, 1, self.flood_tint.?);
        }
        self.blend_color = effect;

        // 6. 噪声 Border（Wrap 模式）
        if (self.noise_bmp) |nb| {
            effect = null;
            if (self.ctx.CreateEffect(&win32.CLSID_D2D1Border, @ptrCast(&effect)) != win32.S_OK) return;
            {
                var edge_x: u32 = @intFromEnum(win32.D2D1_BORDER_EDGE_MODE.WRAP);
                var edge_y: u32 = @intFromEnum(win32.D2D1_BORDER_EDGE_MODE.WRAP);
                _ = effect.?.ID2D1Properties.SetValue(0, .ENUM, @ptrCast(&edge_x), @sizeOf(u32));
                _ = effect.?.ID2D1Properties.SetValue(1, .ENUM, @ptrCast(&edge_y), @sizeOf(u32));
                effect.?.SetInput(0, @ptrCast(nb), 0); // bitmap → 直接传
            }
            self.border_effect = effect;

            // 7. 噪声不透明度
            effect = null;
            if (self.ctx.CreateEffect(&win32.CLSID_D2D1Opacity, @ptrCast(&effect)) != win32.S_OK) return;
            {
                var opacity = NOISE_OPACITY;
                _ = effect.?.ID2D1Properties.SetValue(@intFromEnum(win32.D2D1_OPACITY_PROP.OPACITY), .FLOAT, @ptrCast(&opacity), @sizeOf(f32));
                setEffectInput(effect.?, 0, self.border_effect.?);
            }
            self.opacity_effect = effect;
        }

        // 8. 最终噪声混合（Multiply）
        effect = null;
        if (self.ctx.CreateEffect(&win32.CLSID_D2D1Blend, @ptrCast(&effect)) != win32.S_OK) return;
        {
            var mode: u32 = @intFromEnum(win32.D2D1_BLEND_MODE.MULTIPLY);
            _ = effect.?.ID2D1Properties.SetValue(@intFromEnum(win32.D2D1_BLEND_PROP.MODE), .ENUM, @ptrCast(&mode), @sizeOf(u32));
            setEffectInput(effect.?, 0, self.blend_color.?);
            if (self.opacity_effect) |oe|
                setEffectInput(effect.?, 1, oe);
        }
        self.blend_noise = effect;

        self.acrylic_ready = true;
        std.log.scoped(.D2D).info("Acrylic 效果链初始化完成", .{});
    }

    /// 渲染 acrylic 背景（取代 beginDraw 中的 Clear）
    pub fn renderAcrylic(self: *D2DContext) void {
        if (!self.acrylic_ready) {
            self.ctx.ID2D1RenderTarget.Clear(&.{ .r = 0.12, .g = 0.12, .b = 0.15, .a = 1.0 });
            return;
        }
        // 用最终 Blend effect 的输出来 DrawImage
        var output: ?*win32.ID2D1Image = null;
        self.blend_noise.?.GetOutput(&output);
        defer _ = (@as(*const U, @ptrCast(output.?))).Release();
        self.ctx.DrawImage(output.?, null, null, .LINEAR, .SOURCE_OVER);
    }

    // ─── D2D 便利方法 ────────────────────────────

    pub fn fillRoundedRect(self: *D2DContext, rect: win32.D2D_RECT_F, radius: f32, brush: *win32.ID2D1Brush) void {
        const rr = win32.D2D1_ROUNDED_RECT{ .rect = rect, .radiusX = radius, .radiusY = radius };
        self.ctx.ID2D1RenderTarget.FillRoundedRectangle(&rr, brush);
    }

    pub fn drawRoundedRect(self: *D2DContext, rect: win32.D2D_RECT_F, radius: f32, brush: *win32.ID2D1Brush, width: f32) void {
        const rr = win32.D2D1_ROUNDED_RECT{ .rect = rect, .radiusX = radius, .radiusY = radius };
        self.ctx.ID2D1RenderTarget.DrawRoundedRectangle(&rr, brush, width, null);
    }

    pub fn drawBitmap(self: *D2DContext, bmp: *win32.ID2D1Bitmap, rect: *const win32.D2D_RECT_F, opacity: f32) void {
        self.ctx.ID2D1RenderTarget.DrawBitmap(bmp, rect, opacity, win32.D2D1_BITMAP_INTERPOLATION_MODE.LINEAR, null);
    }

    pub fn fillRect(self: *D2DContext, rect: win32.D2D_RECT_F, brush: *win32.ID2D1Brush) void {
        self.ctx.ID2D1RenderTarget.FillRectangle(&rect, brush);
    }

};
