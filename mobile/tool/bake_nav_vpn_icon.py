"""Bake bottom-nav Teremok + DOM cutout from mono silhouette.

Output: assets/icon/nav_vpn_teremok.png (white glyph, transparent DOM holes)
so Flutter ColorFiltered(srcIn) can theme the house while letters punch through.
"""
from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
MONO = os.path.join(ROOT, "assets", "icon", "mono_teremok.png")
OUT = os.path.join(ROOT, "assets", "icon", "nav_vpn_teremok.png")


def _load_font(size: int) -> ImageFont.ImageFont:
    candidates = [
        r"C:\Windows\Fonts\impact.ttf",
        r"C:\Windows\Fonts\arialbd.ttf",
        r"C:\Windows\Fonts\segoeuib.ttf",
        r"C:\Windows\Fonts\arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ]
    for path in candidates:
        if os.path.isfile(path):
            return ImageFont.truetype(path, size=size)
    return ImageFont.load_default()


def punch_vpn(mono: Image.Image) -> Image.Image:
    out = mono.copy()
    alpha = out.split()[-1]
    bbox = alpha.getbbox()
    if not bbox:
        raise SystemExit("mono_teremok has empty alpha")
    left, top, right, bottom = bbox
    content_w, content_h = right - left, bottom - top
    cx = left + content_w // 2
    # Face sits in the body under the roof peak.
    cy = top + int(content_h * 0.58)
    target_w = int(content_w * 0.58)

    font_size = max(24, int(content_h * 0.22))
    font = _load_font(font_size)
    probe = ImageDraw.Draw(Image.new("L", (8, 8)))
    for _ in range(14):
        box = probe.textbbox((0, 0), "DOM", font=font)
        text_w = box[2] - box[0]
        if text_w <= 0:
            break
        if abs(text_w - target_w) < 6:
            break
        font_size = max(12, int(font_size * target_w / text_w))
        font = _load_font(font_size)

    mask = Image.new("L", out.size, 0)
    draw = ImageDraw.Draw(mask)
    # Fat cutout so DOM stays readable at ~40dp.
    for dx, dy in (
        (0, 0),
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1),
        (2, 0),
        (-2, 0),
        (1, 1),
        (-1, 1),
    ):
        draw.text((cx + dx, cy + dy), "DOM", font=font, fill=255, anchor="mm")
    mask = mask.filter(ImageFilter.GaussianBlur(radius=0.55))

    pixels = out.load()
    mask_px = mask.load()
    width, height = out.size
    for y in range(height):
        for x in range(width):
            m = mask_px[x, y]
            if m > 16:
                _, _, _, a = pixels[x, y]
                na = int(a * (1.0 - min(255, m) / 255.0))
                pixels[x, y] = (255, 255, 255, na)
    return out


def main() -> None:
    mono = Image.open(MONO).convert("RGBA")
    baked = punch_vpn(mono)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    baked.save(OUT, optimize=True)
    print("wrote", OUT, os.path.getsize(OUT), "bbox", baked.split()[-1].getbbox())


if __name__ == "__main__":
    main()
