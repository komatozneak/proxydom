"""Bake the Прокси Дом mark into the Windows runner icon.

Source: `assets/icon/nav_vpn_proxydom.png` — the same DOM cutout the bottom nav
uses, with the charcoal panel already baked in. Output: a multi-size
`windows/runner/resources/app_icon.ico`.

Why not a single 256px entry: Explorer, the taskbar, the Start menu and the
Alt+Tab switcher ask for 16/24/32/48. A lone 256 entry is downscaled by the
shell and the DOM cutout turns to mush at those sizes.

Why the transparent corners: the source PNG is opaque edge to edge — the
rounded square sits on a black field. Shipped as-is, Windows paints that black
square onto the taskbar. The bake opens the border and clears it, so the mark
adapts to light and dark shells.

Run: `python mobile/tool/bake_windows_icon.py`
"""
from __future__ import annotations

import os
import struct
from collections import deque

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(ROOT, "assets", "icon", "nav_vpn_proxydom.png")
OUT = os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico")

# Sizes Explorer actually asks for. 256 is the last one that may be PNG;
# everything below stays a DIB so rc.exe and the WiX icon extractor are happy.
DIB_SIZES = (16, 20, 24, 32, 40, 48, 64, 128)
PNG_SIZES = (256,)

# The source is opaque; anything this dark belongs to the surrounding field.
BACKDROP_MAX_LUMA = 8


def open_corners(img: Image.Image) -> Image.Image:
    """Clear the opaque field around the rounded square, keeping the panel.

    Flood fill from the border rather than a global threshold: the DOM cutout
    is dark too, and a naive cutoff would punch holes through the letters.
    """
    rgba = np.asarray(img.convert("RGBA")).copy()
    lum = rgba[:, :, :3].max(axis=2)
    passable = lum <= BACKDROP_MAX_LUMA

    height, width = passable.shape
    seen = np.zeros_like(passable)
    queue: deque[tuple[int, int]] = deque()
    for x in range(width):
        for y in (0, height - 1):
            if passable[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    for y in range(height):
        for x in (0, width - 1):
            if passable[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))

    while queue:
        y, x = queue.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < height and 0 <= nx < width and not seen[ny, nx] and passable[ny, nx]:
                seen[ny, nx] = True
                queue.append((ny, nx))

    out = Image.fromarray(rgba, "RGBA")
    alpha = np.asarray(out.split()[-1]).copy()
    alpha[seen] = 0
    out.putalpha(Image.fromarray(alpha, "L"))
    return out


def dib_bytes(img: Image.Image) -> bytes:
    """One 32-bit BI_RGB icon image: header, bottom-up BGRA, empty AND mask."""
    img = img.convert("RGBA")
    width, height = img.size
    header = struct.pack(
        "<IiiHHIIiiII",
        40,  # biSize
        width,  # biWidth
        height * 2,  # biHeight — XOR bitmap plus AND mask
        1,  # biPlanes
        32,  # biBitCount
        0,  # biCompression = BI_RGB
        0,  # biSizeImage
        0,  # biXPelsPerMeter
        0,  # biYPelsPerMeter
        0,  # biClrUsed
        0,  # biClrImportant
    )
    rgba = np.asarray(img, dtype=np.uint8)[::-1]  # DIB stores rows bottom-up
    bgra = rgba[:, :, [2, 1, 0, 3]].tobytes()
    mask_stride = ((width + 31) // 32) * 4
    mask = bytes(mask_stride * height)  # 32bpp alpha carries the shape
    return header + bgra + mask


def png_bytes(img: Image.Image) -> bytes:
    import io

    buffer = io.BytesIO()
    img.convert("RGBA").save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def build_ico(frames: list[tuple[int, bytes]]) -> bytes:
    out = bytearray(struct.pack("<HHH", 0, 1, len(frames)))
    offset = 6 + 16 * len(frames)
    for size, payload in frames:
        out += struct.pack(
            "<BBBBHHII",
            0 if size >= 256 else size,
            0 if size >= 256 else size,
            0,  # colour count — truecolour
            0,  # reserved
            1,  # planes
            32,  # bit count
            len(payload),
            offset,
        )
        offset += len(payload)
    for _, payload in frames:
        out += payload
    return bytes(out)


def main() -> None:
    base = open_corners(Image.open(SRC))
    if base.split()[-1].getbbox() is None:
        raise SystemExit(f"{SRC} is empty after the corner pass")

    frames: list[tuple[int, bytes]] = []
    for size in DIB_SIZES:
        frames.append((size, dib_bytes(base.resize((size, size), Image.LANCZOS))))
    for size in PNG_SIZES:
        frames.append((size, png_bytes(base.resize((size, size), Image.LANCZOS))))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as handle:
        handle.write(build_ico(frames))
    print("wrote", OUT, os.path.getsize(OUT), "sizes", [s for s, _ in frames])


if __name__ == "__main__":
    main()