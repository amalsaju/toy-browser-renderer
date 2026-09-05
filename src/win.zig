//const win = @import("win32api.zig")VG
const win = @cImport(@cInclude("windows.h"));
const helpers = @import("helpers.zig");
const main = @import("main.zig");

const std = @import("std");
const uni = std.unicode;

const WIDTH_MIN = 540;
const HEIGHT_MIN = 360;

pub const RENDER_WIDTH_MAX = 1920;
pub const RENDER_HEIGHT_MAX = 1080;

pub var WINDOW_WIDTH_MAX: i32 = undefined;
pub var WINDOW_HEIGHT_MAX: i32 = undefined;
const BYTES_PER_PIXEL = 4;

// I think windows make it signed int
// so that they can rotate the images
// check stretchdibits
pub var width_current: i32 = 0;
pub var height_current: i32 = 0;
var bitmap_info: win.BITMAPINFO = undefined;
var bitmap_memory: [RENDER_HEIGHT_MAX * RENDER_WIDTH_MAX]u32 = undefined;
pub var running: bool = true;

var layout_dirty = true;
var scroll_position_y: i32 = 0;
var amount_scroll: u8 = 50;

pub const rgb_value = struct {
    // a is not used
    // just trying to make it 32 bit
    // I think its better for alignment ?
    // not sure
    a: u8 = 0,
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
};

pub const Position = struct {
    x: i32 = 0,
    y: i32 = 0,
};

const FontProperties = struct {
    font_position: Position = .{},
    font_color: rgb_value = .{},
    font_weight: i16 = 400,
    font_size: i32 = 16,
    // 400 is normal
    font_italics: u1 = 0,
    font_underline: u1 = 0,
    font_strikethrough: u1 = 0,
};

pub fn test_draw() void {}

const FontRenderer = struct {
    font_properties: FontProperties = .{},
    device_context: win.HDC,
    text: [100]u8,
    text_length: usize,

    pub fn render_text(self: FontRenderer) void {
        const hFont: win.HFONT = win.CreateFontW(
            -(self.font_properties.font_size),
            0,
            0,
            0,
            self.font_properties.font_weight,
            self.font_properties.font_italics,
            self.font_properties.font_underline,
            self.font_properties.font_strikethrough,
            win.DEFAULT_CHARSET,
            win.OUT_OUTLINE_PRECIS,
            win.CLIP_DEFAULT_PRECIS,
            win.CLEARTYPE_QUALITY,
            win.VARIABLE_PITCH,
            win.TEXT(std.unicode.utf8ToUtf16LeStringLiteral("Segoe UI")),
        );
        const old_font = win.SelectObject(self.device_context, hFont);
        defer _ = win.SelectObject(self.device_context, old_font);

        defer _ = win.DeleteObject(hFont);
        _ = win.SetBkMode(
            self.device_context,
            win.TRANSPARENT,
        );

        //Sets the coordinates for the rectangle in which the text is to be formatted.
        _ = win.SetTextColor(self.device_context, win.RGB(
            self.font_properties.font_color.r,
            self.font_properties.font_color.g,
            self.font_properties.font_color.b,
        ));
        // Convert UTF-8 → UTF-16
        var utf16_buffer: [100]u16 = undefined;

        const utf16_length = std.unicode.utf8ToUtf16Le(
            &utf16_buffer,
            self.text[0..self.text_length],
        ) catch return;

        _ = win.TextOutW(
            self.device_context,
            self.font_properties.font_position.x,
            self.font_properties.font_position.y,
            &utf16_buffer,
            @intCast(utf16_length),
        );
    }

    pub fn measure_text(self: FontRenderer) win.SIZE {
        const hFont: win.HFONT = win.CreateFontW(
            -(self.font_properties.font_size),
            0,
            0,
            0,
            self.font_properties.font_weight,
            self.font_properties.font_italics,
            self.font_properties.font_underline,
            self.font_properties.font_strikethrough,
            win.DEFAULT_CHARSET,
            win.OUT_OUTLINE_PRECIS,
            win.CLIP_DEFAULT_PRECIS,
            win.ANTIALIASED_QUALITY,
            win.VARIABLE_PITCH,
            win.TEXT(std.unicode.utf8ToUtf16LeStringLiteral("Segoe UI")),
        );
        const old_font = win.SelectObject(self.device_context, hFont);
        defer _ = win.SelectObject(self.device_context, old_font);

        defer _ = win.DeleteObject(hFont);

        // Convert UTF-8 → UTF-16
        var utf16_buffer: [100]u16 = undefined;

        const utf16_length = std.unicode.utf8ToUtf16Le(
            &utf16_buffer,
            self.text[0..self.text_length],
        ) catch {
            return .{
                .cx = 0,
                .cy = 0,
            };
        };

        var text_size: win.SIZE = undefined;

        const success = win.GetTextExtentPoint32W(
            self.device_context,
            &utf16_buffer,
            @intCast(utf16_length),
            &text_size,
        );

        if (success == 0) {
            return .{
                .cx = 0,
                .cy = 0,
            };
        }

        return text_size;
    }
};

pub fn render_box(x: i32, y: i32, width: i32, height: i32, rgb: rgb_value) void {
    var y_offset: i32 = y - scroll_position_y;
    while (y_offset < y + height - scroll_position_y) : (y_offset += 1) {
        var x_offset: i32 = x;

        while (x_offset < x + width) : (x_offset += 1) {
            if (x_offset < 0 or y_offset < 0 or x_offset >= width_current or y_offset >= height_current) {
                continue;
            }
            const pixel: u32 = @intCast(y_offset * width_current + x_offset);
            bitmap_memory[pixel] =
                (@as(u32, rgb.r) << 16) |
                (@as(u16, rgb.g) << 8) |
                rgb.b;
        }
    }
}

fn render_gradient(x_offset: u8, y_offset: u8) void {
    var y: i32 = 0;
    //var pixel: u32 = 0;
    while (y < height_current) : (y += 1) {
        var x: i32 = 0;
        while (x < width_current) : (x += 1) {
            //TODO: Probably need to figure out something here
            // to convert from hex value to this representation
            // padding, red,green,blue
            const pixel: u32 = @intCast(y * width_current + x);

            const blue: u32 = @intCast(@mod(
                x + @as(i32, @intCast(x + x_offset)),
                256,
            ));

            const green: u32 = @intCast(@mod(
                y + @as(i32, @intCast(y + y_offset)),
                256,
            ));

            bitmap_memory[pixel] =
                (green << 8) |
                blue;
        }
    }
}

// DIB => Device Independent Bitmap
fn resize_dib_section(width: i32, height: i32) void {
    if (width <= 0 or height <= 0) {
        return;
    }

    bitmap_info.bmiHeader.biSize = @sizeOf(win.BITMAPINFOHEADER);
    bitmap_info.bmiHeader.biWidth = width;
    bitmap_info.bmiHeader.biHeight = -height; // Top-Down
    bitmap_info.bmiHeader.biPlanes = 1;
    // we set 32 for alignment with 4 bytes
    bitmap_info.bmiHeader.biBitCount = 32;
    bitmap_info.bmiHeader.biCompression = win.BI_RGB;
    bitmap_info.bmiHeader.biSizeImage = 0;
    bitmap_info.bmiHeader.biXPelsPerMeter = 0;
    bitmap_info.bmiHeader.biYPelsPerMeter = 0;
    bitmap_info.bmiHeader.biClrUsed = 0;
    bitmap_info.bmiHeader.biClrImportant = 0;

    width_current = width;
    height_current = height;

    // we've already set the max amount of data the bitmap memory can hold which is 720p
    // So here we can play around with any resolution upto 720p
    // u8 is 1 byte => 8 means 8 bits
    // each pixel is 4 bytes, actually only 3 for rgb but using 4 for alignment

    //const bitmap_memory_bytes: u8 = (width_current * height_current) * 4;

    //const pitch: u8 = BYTES_PER_PIXEL * width;
    //render_box(0, 0, WIDTH_MAX, HEIGHT_MAX, rgb_value{ .r = 255, .g = 255, .b = 255 });
}

fn update_window(device_context: win.HDC, window_rect: win.RECT, x: i32, y: i32) void {
    const width_window: i32 = window_rect.right - window_rect.left;
    const height_window: i32 = window_rect.bottom - window_rect.top;

    // rectangle to rectangle copy- can be different size due to the stretch func
    _ = win.StretchDIBits(
        device_context,
        // destination
        x,
        y,
        width_window,
        height_window,
        // source
        x,
        y,
        width_current,
        height_current,
        &bitmap_memory,
        &bitmap_info,
        win.DIB_RGB_COLORS,
        win.SRCCOPY,
    );
}

export fn Wndproc(window: win.HWND, message: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) win.LRESULT {
    var result: win.LRESULT = 0;
    switch (message) {
        win.WM_SIZE => {
            // comptime conversion
            var client_rect: win.RECT = undefined;
            _ = win.GetClientRect(window, &client_rect);
            var width: i32 = client_rect.right - client_rect.left;
            var height: i32 = client_rect.bottom - client_rect.top;
            if (width > RENDER_WIDTH_MAX) {
                width = RENDER_WIDTH_MAX;
            }
            if (height > RENDER_HEIGHT_MAX) {
                height = RENDER_HEIGHT_MAX;
            }

            resize_dib_section(width, height);

            // update the layout
            layout_dirty = true;
        },
        win.WM_KEYDOWN => {
            switch (wparam) {
                win.VK_UP, 'W' => {
                    if (scroll_position_y - amount_scroll >= 0) {
                        scroll_position_y -= amount_scroll;
                    }
                    std.debug.print("Key is presssed", .{});
                    layout_dirty = true;
                },
                win.VK_DOWN, 'S' => {
                    if (scroll_position_y + height_current + amount_scroll <= main.return_html_height()) {
                        scroll_position_y += amount_scroll;
                    }
                    std.debug.print("Down Pressed. Current scroll position: {d}\n", .{scroll_position_y});
                    layout_dirty = true;
                },
                else => {},
            }
        },
        win.WM_GETMINMAXINFO => {
            // gets a pointer to the window minmaxinfo
            const minmax_info: *win.MINMAXINFO =
                @ptrFromInt(@as(usize, @bitCast(lparam)));

            // set the min
            minmax_info.ptMinTrackSize.x = WIDTH_MIN;
            minmax_info.ptMinTrackSize.y = HEIGHT_MIN;

            // set the max.
            minmax_info.ptMaxTrackSize.x = WINDOW_WIDTH_MAX;
            minmax_info.ptMaxTrackSize.y = WINDOW_HEIGHT_MAX;

            return 0;
        },
        win.WM_DESTROY => {
            result = 0;
            win.PostQuitMessage(0);
        },
        win.WM_CLOSE => {
            running = false;
            _ = win.DestroyWindow(window);
            result = 0;
        },
        win.WM_PAINT => {
            var paint: win.PAINTSTRUCT = undefined;
            const device_context: win.HDC = win.BeginPaint(window, &paint);

            var client_rect: win.RECT = undefined;
            _ = win.GetClientRect(window, &client_rect);

            update_window(device_context, client_rect, 0, 0);
            _ = win.EndPaint(window, &paint);
            result = 0;
        },
        win.WM_ACTIVATEAPP => {},
        else => {
            return win.DefWindowProcW(
                window,
                message,
                wparam,
                lparam,
            );
        },
    }
    return result;
}

pub var font_renderer: FontRenderer = undefined;

pub fn Create() void {
    const window_name = uni.utf8ToUtf16LeStringLiteral("Tiny Browser Renderer Test");
    const lpsz_class_name = uni.utf8ToUtf16LeStringLiteral("lpsz_class_name");
    var window_class = win.WNDCLASSW{
        .style = win.CS_HREDRAW | win.CS_VREDRAW,
        .lpfnWndProc = Wndproc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = win.GetModuleHandleW(null),
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = lpsz_class_name,
    };

    // hInstance is usually passed in by callback in
    // but if you don't have it, you can get it with
    // GetModuleHandle. Its takes in something related to exe
    // but to get our program we can pass in 0
    // Need to call GetModuleHandleW explicitly because thats why zig supports
    //TODO: Maybe in the future do drag and drop html files

    // returns 0 if RegisterClass fails
    _ = win.RegisterClassW(&window_class);

    var rect = win.RECT{
        .left = 0,
        .top = 0,
        .right = 1920,
        .bottom = 1080,
    };

    _ = win.AdjustWindowRectEx(
        &rect,
        win.WS_OVERLAPPEDWINDOW,
        0,
        0,
    );

    WINDOW_HEIGHT_MAX = rect.bottom - rect.top;
    WINDOW_WIDTH_MAX = rect.right - rect.left;

    const window_handle: win.HWND = win.CreateWindowW(
        window_class.lpszClassName,
        window_name,
        win.WS_OVERLAPPEDWINDOW | win.WS_VISIBLE,
        win.CW_USEDEFAULT,
        win.CW_USEDEFAULT,
        1080,
        720,
        null, // hWndParent
        null, // hMenu
        window_class.hInstance,
        null, // lpParam
    );

    const text_device_context: win.HDC = win.GetDC(window_handle);
    font_renderer.device_context = text_device_context;
    defer _ = win.ReleaseDC(window_handle, font_renderer.device_context);

    if (window_handle != null) {
        var frequency_processor: win.LARGE_INTEGER = undefined;
        var count_previous: win.LARGE_INTEGER = undefined;
        // the frequency is fixed at system boot
        _ = win.QueryPerformanceFrequency(&frequency_processor);
        _ = win.QueryPerformanceFrequency(&count_previous);

        //const frequency: i64 = frequency_processor.QuadPart;

        main.calculate_layout();
        main.render_layout();

        while (running) {
            var message: win.MSG = undefined;
            while (win.PeekMessageW(&message, 0, 0, 0, win.PM_REMOVE) > 0) {
                if (message.message == win.WM_QUIT) {
                    running = false;
                }
                _ = win.TranslateMessage(&message);
                _ = win.DispatchMessageW(&message);
            }

            const device_context: win.HDC = win.GetDC(window_handle);
            _ = win.SetBkMode(
                device_context,
                win.TRANSPARENT,
            );

            var client_rect: win.RECT = undefined;
            _ = win.GetClientRect(window_handle, &client_rect);

            if (layout_dirty) {
                render_box(0, 0, RENDER_WIDTH_MAX, RENDER_HEIGHT_MAX, rgb_value{ .r = 255, .g = 255, .b = 255 });

                main.calculate_layout();
                main.render_layout();
                layout_dirty = false;
                _ = win.InvalidateRect(window_handle, null, win.FALSE);
            }
            //render_gradient(x_offset, 0);
            //render_box(100, 100, 300, 500, rgb_value{ .r = 0, .g = 255, .b = 0 });
            //render_box(200, 200, 500, 50, rgb_value{ .r = 100, .g = 100, .b = 100 });
            //

            _ = win.ReleaseDC(window_handle, device_context);
            // var count_current: win.LARGE_INTEGER = undefined;
            // const cycle_count_current: u64 = helpers.rdtsc();
            // const elapsed_cycles = cycle_count_current - cycle_count_previous;
            // const elapsed_cycles_million: u64 = elapsed_cycles / (1000 * 1000);
            //
            // _ = win.QueryPerformanceCounter(&count_current);
            // const elapsed_counter: i64 = (count_current.QuadPart - count_previous.QuadPart);
            // const elapsed_time_milliseconds: i64 = @divTrunc(elapsed_counter * 1000, frequency);
            // const frame_time_milliseconds: i64 = @divTrunc(frequency, elapsed_counter);
            //
            // //std.debug.print("{d}ms per frame / {d}FPS - {d}M/frame \n", .{ elapsed_time_milliseconds, frame_time_milliseconds, elapsed_cycles_million });
            //
            // count_previous = count_current;
            // cycle_count_previous = cycle_count_current;
        }
    }
}

// font family
// font size
// underline
// bold
// italics
// weight
//
// pub fn draw_text() void {
//     // get the current device context
//     const device_context: win.HDC = win.GetDC(window_handle);
//     const hFont1: win.HFONT = win.CreateFontW(20, 0, 0, 0, win.FW_NORMAL, win.FALSE, win.TRUE, win.FALSE, win.DEFAULT_CHARSET, win.OUT_OUTLINE_PRECIS, win.CLIP_DEFAULT_PRECIS, win.CLEARTYPE_QUALITY, win.VARIABLE_PITCH, win.TEXT(std.unicode.utf8ToUtf16LeStringLiteral("Segoe UI")));
//     _ = win.SelectObject(device_context, hFont1);
//
//     _ = win.SelectObject(device_context, &bitmap_memory);
//     _ = win.SetTextColor(device_context, win.RGB(255, 0, 0));
//     _ = win.TextOutW(device_context, 100, 300, uni.utf8ToUtf16LeStringLiteral("Hellow").ptr, 6);
//     _ = win.DeleteObject(hFont1);
// }

const FILE_SIZE_MAX = 5 * 1024;

pub fn read_file(buffer: *[FILE_SIZE_MAX]u8, is_html: bool) u32 {
    var file: win.HANDLE = undefined;
    if (is_html) {
        file = win.CreateFileW(std.unicode.utf8ToUtf16LeStringLiteral("src/test1.html"), win.GENERIC_READ, win.FILE_SHARE_READ, null, win.OPEN_EXISTING, win.FILE_ATTRIBUTE_NORMAL, null);
    } else {
        file = win.CreateFileW(std.unicode.utf8ToUtf16LeStringLiteral("src/test1.css"), win.GENERIC_READ, win.FILE_SHARE_READ, null, win.OPEN_EXISTING, win.FILE_ATTRIBUTE_NORMAL, null);
    }
    defer _ = win.CloseHandle(file);

    var bytes_read: win.DWORD = 0;

    _ = win.ReadFile(
        file,
        buffer,
        @intCast(buffer.len),
        &bytes_read,
        null,
    );

    return bytes_read;
}
