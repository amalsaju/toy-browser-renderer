const win = @cImport(@cInclude("windows.h"));
const uni = @import("std").unicode;

const renderer = @import("win32.zig");

const FONT_STYLE_BOLD = 0;
const FONT_STYLE_ITALICS = 1;
const FONT_STYLE_UNDERLINE = 2;
const FONT_STYLE_STRIKEOUT = 3;

pub var TextStyle = struct {
    font_size: i32 = 16,
    font_weight: i32 = win.FW_NORMAL,
    // bold, italics, underline
    font_decoration: [4]u1 = .{ 0, 0, 0, 0 },
    color: u32 = win.RGB(0, 0, 0),
};

pub const TextSize = struct {
    width: i32,
    height: i32,
};

var text_dc: win.HDC = null;
var current_font: win.HFONT = null;

pub fn init() void {
    // This DC is only used by GDI for font operations.
    // It is NOT the window DC.
    text_dc = win.CreateCompatibleDC(null);

    if (text_dc == null) {
        return;
    }
}

pub fn deinit() void {
    if (current_font != null) {
        _ = win.DeleteObject(current_font);
        current_font = null;
    }

    if (text_dc != null) {
        _ = win.DeleteDC(text_dc);
        text_dc = null;
    }
}

fn create_font(style: TextStyle) win.HFONT {
    return win.CreateFontW(
        -style.font_size,

        0, // width
        0, // escapement
        0, // orientation

        if (style.font_decoration[FONT_STYLE_BOLD] == 0) style.font_weight orelse win.FW_BOLD,

        if (style.font_decoration[FONT_STYLE_ITALICS] == 0) win.FALSE orelse win.TRUE, // italic
        if (style.font_decoration[FONT_STYLE_UNDERLINE] == 0) win.FALSE orelse win.TRUE, // underline
        if (style.font_decoration[FONT_STYLE_STRIKEOUT] == 0) win.FALSE orelse win.TRUE, // strikeout

        win.DEFAULT_CHARSET,
        win.OUT_OUTLINE_PRECIS,
        win.CLIP_DEFAULT_PRECIS,
        win.ANTIALIASED_QUALITY,
        win.DEFAULT_PITCH,

        win.TEXT(
            uni.utf8ToUtf16LeStringLiteral("Segoe UI"),
        ),
    );
}

fn get_font(style: TextStyle) win.HFONT {
    // Very naïve implementation:
    // recreate the font when the requested style changes.

    if (current_font != null) {
        _ = win.DeleteObject(current_font);
        current_font = null;
    }

    current_font = create_font(style);

    return current_font;
}

pub fn measure_text(
    text: []const u16,
    style: TextStyle,
) TextSize {
    if (text_dc == null) {
        return .{
            .width = 0,
            .height = 0,
        };
    }

    const font = get_font(style);

    if (font == null) {
        return .{
            .width = 0,
            .height = 0,
        };
    }

    _ = win.SelectObject(text_dc, font);

    var size: win.SIZE = undefined;

    _ = win.GetTextExtentPoint32W(
        text_dc,
        text.ptr,
        @intCast(text.len),
        &size,
    );

    return .{
        .width = size.cx,
        .height = size.cy,
    };
}

pub fn draw_text(
    text: []const u16,
    x: i32,
    y: i32,
    style: TextStyle,
) void {
    if (text_dc == null) {
        return;
    }

    const font = get_font(style);

    if (font == null) {
        return;
    }

    _ = win.SelectObject(text_dc, font);

    var cursor_x = x;

    for (text) |codepoint| {
        const glyph = draw_glyph(
            text_dc,
            font,
            codepoint,
            cursor_x,
            y,
            style.color,
        );

        if (glyph) |g| {
            cursor_x += g.advance_x;
        }
    }
}

const GlyphResult = struct {
    width: i32,
    height: i32,
    advance_x: i32,
};

fn draw_glyph(
    dc: win.HDC,
    font: win.HFONT,
    codepoint: u16,
    x: i32,
    y: i32,
    color: u32,
) ?GlyphResult {
    _ = win.SelectObject(dc, font);

    var glyph_metrics: win.GLYPHMETRICS = undefined;

    // First call asks GDI how much memory is needed.
    const buffer_size = win.GetGlyphOutlineW(
        dc,
        codepoint,
        win.GGO_GRAY8_BITMAP,
        &glyph_metrics,
        0,
        null,
        null,
    );

    if (buffer_size == win.GDI_ERROR) {
        return null;
    }

    if (buffer_size > 4096) {
        return null;
    }

    var glyph_buffer: [4096]u8 = undefined;

    // Second call actually retrieves the glyph bitmap.
    const result = win.GetGlyphOutlineW(
        dc,
        codepoint,
        win.GGO_GRAY8_BITMAP,
        &glyph_metrics,
        buffer_size,
        &glyph_buffer,
        null,
    );

    if (result == win.GDI_ERROR) {
        return null;
    }

    const glyph_width: i32 =
        @intCast(glyph_metrics.gmBlackBoxX);

    const glyph_height: i32 =
        @intCast(glyph_metrics.gmBlackBoxY);

    if (glyph_width == 0 or glyph_height == 0) {
        return .{
            .width = glyph_width,
            .height = glyph_height,
            .advance_x = glyph_metrics.gmCellIncX,
        };
    }

    // GGO_GRAY8_BITMAP rows are DWORD aligned.
    const row_bytes: usize =
        (@as(usize, @intCast(glyph_width)) + 3) & ~@as(usize, 3);

    var gy: i32 = 0;

    while (gy < glyph_height) : (gy += 1) {
        var gx: i32 = 0;

        while (gx < glyph_width) : (gx += 1) {
            const source_index =
                @as(usize, @intCast(gy)) * row_bytes +
                @as(usize, @intCast(gx));

            const coverage = glyph_buffer[source_index];

            if (coverage == 0) {
                continue;
            }

            // GDI grayscale glyph coverage is 0..64.
            // Convert it to alpha 0..255.
            const alpha: u32 =
                (@as(u32, coverage) * 255) / 64;

            //
            // GGO's glyph origin is relative to the baseline.
            //
            const pixel_x =
                x + glyph_metrics.gmptGlyphOrigin.x + gx;

            const pixel_y =
                y - glyph_metrics.gmptGlyphOrigin.y +
                gy;

            // Bounds check.
            if (pixel_x < 0 or
                pixel_y < 0 or
                pixel_x >= renderer.width_current or
                pixel_y >= renderer.height_current)
            {
                continue;
            }

            const pixel_index: usize =
                @intCast(
                    pixel_y * renderer.width_current +
                        pixel_x,
                );

            //
            // Extract source text color.
            //
            const src_r = (color >> 16) & 0xff;
            const src_g = (color >> 8) & 0xff;
            const src_b = color & 0xff;

            //
            // Extract existing pixel.
            //
            const dst = renderer.bitmap_memory[pixel_index];

            const dst_r = (dst >> 16) & 0xff;
            const dst_g = (dst >> 8) & 0xff;
            const dst_b = dst & 0xff;

            //
            // Alpha blend text over existing pixel.
            //
            const inverse_alpha = 255 - alpha;

            const r =
                (src_r * alpha + dst_r * inverse_alpha) / 255;

            const g =
                (src_g * alpha + dst_g * inverse_alpha) / 255;

            const b =
                (src_b * alpha + dst_b * inverse_alpha) / 255;

            //
            // Store directly into YOUR framebuffer.
            //
            renderer.bitmap_memory[pixel_index] =
                (r << 16) |
                (g << 8) |
                b;
        }
    }

    return .{
        .width = glyph_width,
        .height = glyph_height,
        .advance_x = glyph_metrics.gmCellIncX,
    };
}
