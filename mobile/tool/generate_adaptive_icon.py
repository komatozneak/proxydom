"""Generate Android adaptive icon layers from Living House mascot PNG.

Source: assets/brand/connect/s1-flat-launcher.png (mustard house, white door).
Crops to content bbox first — the source PNG has large transparent margins.
"""
from __future__ import annotations

import os

from PIL import Image, ImageFilter

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(ROOT, "assets", "brand", "connect", "s1-flat-launcher.png")
OUT = os.path.join(ROOT, "assets", "icon")
ANDROID_DRAWABLE = os.path.normpath(
    os.path.join(ROOT, "android", "app", "src", "main", "res"),
)
SIZE = 1024
# Adaptive icon: SAFE_SCALE 0.72 + XML inset 12% (re-force inset after
# flutter_launcher_icons overwrites mipmap-anydpi-v26/ic_launcher.xml).
SAFE_SCALE = 0.72
CROP_PAD = 0.04  # relative padding around content bbox


def _load_mascot() -> Image.Image:
    im = Image.open(SRC).convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(int(h * 0.68), int(h * 0.82)):
        for x in range(int(w * 0.38), int(w * 0.62)):
            r, g, b, a = px[x, y]
            if a > 40 and r > 180 and g > 180 and b > 180:
                px[x, y] = (255, 255, 255, 255)
    return _crop_to_content(im)


def _crop_to_content(im: Image.Image) -> Image.Image:
    # Ignore faint AA dust so crop is tight around the house.
    mask = im.split()[-1].point(lambda a: 255 if a > 32 else 0)
    bbox = mask.getbbox()
    if not bbox:
        return im
    l, t, r, b = bbox
    pad = int(max(r - l, b - t) * CROP_PAD)
    l = max(0, l - pad)
    t = max(0, t - pad)
    r = min(im.width, r + pad)
    b = min(im.height, b + pad)
    cropped = im.crop((l, t, r, b))
    print(f"crop {im.size} -> {cropped.size} bbox={bbox}")
    return cropped


def _fit_on_canvas(src: Image.Image, size: int, scale: float) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    target = max(1, int(size * scale))
    # thumbnail() only shrinks — cropped mascot must be scaled UP to fill.
    fitted = src.copy()
    tw, th = fitted.size
    factor = min(target / tw, target / th)
    new_size = (
        max(1, int(round(tw * factor))),
        max(1, int(round(th * factor))),
    )
    fitted = fitted.resize(new_size, Image.Resampling.LANCZOS)
    x = (size - fitted.width) // 2
    y = (size - fitted.height) // 2
    canvas.paste(fitted, (x, y), fitted)
    return canvas


def _monochrome_silhouette(src: Image.Image) -> Image.Image:
    w, h = src.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sp = src.load()
    op = out.load()
    for y in range(h):
        for x in range(w):
            a = sp[x, y][3]
            if a > 24:
                op[x, y] = (255, 255, 255, a)
    return out.filter(ImageFilter.SMOOTH_MORE)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    mascot = _load_mascot()
    fg = _fit_on_canvas(mascot, SIZE, SAFE_SCALE)
    mono = _fit_on_canvas(_monochrome_silhouette(mascot), SIZE, SAFE_SCALE)

    fg_path = os.path.join(OUT, "fg_teremok.png")
    mono_path = os.path.join(OUT, "mono_teremok.png")
    fg.save(fg_path, optimize=True)
    mono.save(mono_path, optimize=True)
    fg.save(os.path.join(OUT, "fg_oak_moss.png"), optimize=True)
    mono.save(os.path.join(OUT, "mono.png"), optimize=True)
    # Do NOT write ic_notification_mascot — largeIcon duplicates the shade glyph
    # and revived the old oak/moss avatar beside ic_stat_teremok.

    print("wrote", fg_path, os.path.getsize(fg_path))
    print("wrote", mono_path, os.path.getsize(mono_path))
    print("SAFE_SCALE", SAFE_SCALE, "content-cropped")
    print(
        "note: bottom-nav VPN glyph is curated at assets/icon/nav_vpn_teremok.png; "
        "optional PIL cutout: python tool/bake_nav_vpn_icon.py"
    )


if __name__ == "__main__":
    main()
