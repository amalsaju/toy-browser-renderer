//const win = @import("win32api.zig");
const win = @cImport(@cInclude("windows.h"));
const helpers = @import("helpers.zig");

const std = @import("std");
const uni = std.unicode;

const WIDTH_MIN = 640;
const HEIGHT_MIN = 360;

pub const WIDTH_MAX = 1920;
pub const HEIGHT_MAX = 1080;
const BYTES_PER_PIXEL = 4;

// I think windows make it signed int
// so that they can rotate the images
// check stretchdibits
var width_current: i32 = 0;
var height_current: i32 = 0;
var bitmap_info: win.BITMAPINFO = undefined;
var bitmap_memory: [HEIGHT_MAX * WIDTH_MAX]u32 = undefined;
var running: bool = true;

const rgb_value = struct {
    // a is not used
    // just trying to make it 32 bit
    // I think its better for alignment ?
    // not sure
    a: u8 = undefined,
    r: u8,
    g: u8,
    b: u8,
};

fn render_box(x: i32, y: i32, width: i32, height: i32, rgb: rgb_value) void {
    var y_offset: i32 = y;
    while (y_offset < height_current) : (y_offset += 1) {
        var x_offset: i32 = x;

        while (x_offset < x + width_current) : (x_offset += 1) {
            const pixel: u32 = @intCast(y_offset * width_current + x_offset);

            if ((y_offset >= y and y_offset < (y + height)) and (x_offset >= x and x_offset < (x + width))) {
                bitmap_memory[pixel] =
                    (@as(u32, rgb.r) << 16) |
                    (@as(u16, rgb.g) << 8) |
                    rgb.b;
            }
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

    if (width > WIDTH_MAX or height > HEIGHT_MAX) {
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
    render_box(0, 0, WIDTH_MAX, HEIGHT_MAX, rgb_value{ .r = 255, .g = 255, .b = 255 });
}

fn update_window(device_context: win.HDC, window_rect: win.RECT, x: i32, y: i32) void {
    const window_width: i32 = window_rect.right - window_rect.left;
    const window_height: i32 = window_rect.bottom - window_rect.top;

    // rectangle to rectangle copy- can be different size due to the stretch func
    _ = win.StretchDIBits(
        device_context,
        x,
        y,
        width_current,
        height_current,
        x,
        y,
        window_width,
        window_height,
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
            if (width > WIDTH_MAX) {
                width = WIDTH_MAX;
            }
            if (height > HEIGHT_MAX) {
                height = HEIGHT_MAX;
            }

            resize_dib_section(width, height);
        },
        win.WM_GETMINMAXINFO => {
            // gets a pointer to the window minmaxinfo
            const minmax_info: *win.MINMAXINFO =
                @ptrFromInt(@as(usize, @bitCast(lparam)));

            // set the min
            minmax_info.ptMinTrackSize.x = WIDTH_MIN;
            minmax_info.ptMinTrackSize.y = HEIGHT_MIN;

            // set the max.
            minmax_info.ptMaxTrackSize.x = WIDTH_MAX;
            minmax_info.ptMaxTrackSize.y = HEIGHT_MAX;

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

    const window_handle: win.HWND = win.CreateWindowW(
        window_class.lpszClassName,
        window_name,
        win.WS_OVERLAPPEDWINDOW | win.WS_VISIBLE,
        win.CW_USEDEFAULT,
        win.CW_USEDEFAULT,
        800,
        450,
        null, // hWndParent
        null, // hMenu
        window_class.hInstance,
        null, // lpParam
    );
    if (window_handle != null) {
        var frequency_processor: win.LARGE_INTEGER = undefined;
        var count_previous: win.LARGE_INTEGER = undefined;
        // the frequency is fixed at system boot
        _ = win.QueryPerformanceFrequency(&frequency_processor);
        _ = win.QueryPerformanceFrequency(&count_previous);

        //const frequency: i64 = frequency_processor.QuadPart;

        //var cycle_count_previous: u64 = helpers.rdtsc();

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
            update_window(device_context, client_rect, 0, 0);

            //render_gradient(x_offset, 0);
            //render_box(100, 100, 300, 500, rgb_value{ .r = 0, .g = 255, .b = 0 });
            //render_box(200, 200, 500, 50, rgb_value{ .r = 100, .g = 100, .b = 100 });

            _ = win.TextOutW(device_context, 100, 100, uni.utf8ToUtf16LeStringLiteral("Hellow").ptr, 6);

            const hFont1: win.HFONT = win.CreateFontW(48, 0, 0, 0, win.FW_NORMAL, win.FALSE, win.TRUE, win.FALSE, win.DEFAULT_CHARSET, win.OUT_OUTLINE_PRECIS, win.CLIP_DEFAULT_PRECIS, win.CLEARTYPE_QUALITY, win.VARIABLE_PITCH, win.TEXT(std.unicode.utf8ToUtf16LeStringLiteral("Segoe UI")));
            _ = win.SelectObject(device_context, hFont1);
            var rect: win.RECT = undefined;

            //Sets the coordinates for the rectangle in which the text is to be formatted.
            _ = win.SetRect(&rect, 100, 100, 700, 200);
            _ = win.SetTextColor(device_context, win.RGB(255, 0, 0));
            _ = win.DrawTextW(device_context, win.TEXT(uni.utf8ToUtf16LeStringLiteral("Drawing Text with Impact")), -1, &rect, win.DT_NOCLIP);

            _ = win.DeleteObject(hFont1);

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

const FILE_SIZE_MAX = 5 * 1024;

pub fn read_file(buffer: *[FILE_SIZE_MAX]u8, is_html: bool) u32 {
    var file: win.HANDLE = undefined;
    if (is_html) {
        file = win.CreateFileW(std.unicode.utf8ToUtf16LeStringLiteral("src/melbjs_html.html"), win.GENERIC_READ, win.FILE_SHARE_READ, null, win.OPEN_EXISTING, win.FILE_ATTRIBUTE_NORMAL, null);
    } else {
        file = win.CreateFileW(std.unicode.utf8ToUtf16LeStringLiteral("src/melbjs_css.css"), win.GENERIC_READ, win.FILE_SHARE_READ, null, win.OPEN_EXISTING, win.FILE_ATTRIBUTE_NORMAL, null);
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
