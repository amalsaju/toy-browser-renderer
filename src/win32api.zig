const Handle = ?*anyopaque;

pub const HWND = Handle;
pub const HDC = Handle;
pub const HINSTANCE = Handle;
pub const HICON = Handle;
pub const HCURSOR = Handle;
pub const HBRUSH = Handle;
pub const HMENU = Handle;

pub const BOOL = i32;
pub const UINT = u32;
pub const DWORD = u32;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;

pub const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};

pub const POINT = extern struct {
    x: i32,
    y: i32,
};

pub const PAINTSTRUCT = extern struct {
    hdc: HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]u8,
};

pub const MSG = extern struct {
    hwnd: HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
};

pub const WNDPROC = *const fn (
    hwnd: HWND,
    message: UINT,
    wparam: WPARAM,
    lparam: LPARAM,
) callconv(.winapi) LRESULT;

pub const WNDCLASSW = extern struct {
    style: u32,
    lpfnWndProc: WNDPROC,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: HINSTANCE,
    hIcon: HICON,
    hCursor: HCURSOR,
    hbrBackground: HBRUSH,
    lpszMenuName: ?[*:0]const u16,
    lpszClassName: [*:0]const u16,
};

pub const WM_SIZE: UINT = 0x0005;
pub const WM_DESTROY: UINT = 0x0002;
pub const WM_PAINT: UINT = 0x000F;
pub const WM_CLOSE: UINT = 0x0010;
pub const WM_ACTIVATEAPP: UINT = 0x001C;

pub const WS_VISIBLE: u32 = 0x10000000;
pub const WS_OVERLAPPEDWINDOW: u32 = 0x00CF0000;

pub const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));

pub const BLACKNESS: DWORD = 0x00000042;

pub extern "kernel32" fn GetModuleHandleW(
    lpModuleName: ?[*:0]const u16,
) callconv(.winapi) HINSTANCE;

pub extern "kernel32" fn OutputDebugStringW(
    lpOutputString: [*:0]const u16,
) callconv(.winapi) void;

pub extern "user32" fn RegisterClassW(
    lpWndClass: *const WNDCLASSW,
) callconv(.winapi) u16;

pub extern "user32" fn CreateWindowExW(
    dwExStyle: u32,
    lpClassName: [*:0]const u16,
    lpWindowName: [*:0]const u16,
    dwStyle: u32,
    x: i32,
    y: i32,
    nWidth: i32,
    nHeight: i32,
    hWndParent: HWND,
    hMenu: HMENU,
    hInstance: HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(.winapi) HWND;

pub fn CreateWindowW(
    lpClassName: [*:0]const u16,
    lpWindowName: [*:0]const u16,
    dwStyle: u32,
    x: i32,
    y: i32,
    nWidth: i32,
    nHeight: i32,
    hWndParent: HWND,
    hMenu: HMENU,
    hInstance: HINSTANCE,
    lpParam: ?*anyopaque,
) HWND {
    return CreateWindowExW(
        0,
        lpClassName,
        lpWindowName,
        dwStyle,
        x,
        y,
        nWidth,
        nHeight,
        hWndParent,
        hMenu,
        hInstance,
        lpParam,
    );
}

pub extern "user32" fn DefWindowProcW(
    hWnd: HWND,
    Msg: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
) callconv(.winapi) LRESULT;

pub extern "user32" fn DestroyWindow(
    hWnd: HWND,
) callconv(.winapi) BOOL;

pub extern "user32" fn PostQuitMessage(
    nExitCode: i32,
) callconv(.winapi) void;

pub extern "user32" fn GetMessageW(
    lpMsg: *MSG,
    hWnd: HWND,
    wMsgFilterMin: UINT,
    wMsgFilterMax: UINT,
) callconv(.winapi) BOOL;

pub extern "user32" fn TranslateMessage(
    lpMsg: *const MSG,
) callconv(.winapi) BOOL;

pub extern "user32" fn DispatchMessageW(
    lpMsg: *const MSG,
) callconv(.winapi) LRESULT;

pub extern "user32" fn BeginPaint(
    hWnd: HWND,
    lpPaint: *PAINTSTRUCT,
) callconv(.winapi) HDC;

pub extern "user32" fn EndPaint(
    hWnd: HWND,
    lpPaint: *const PAINTSTRUCT,
) callconv(.winapi) BOOL;

pub extern "gdi32" fn PatBlt(
    hdc: HDC,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    rop: DWORD,
) callconv(.winapi) BOOL;
