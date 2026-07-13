"""Generate Android adaptive icon layers (no AI). Oak+moss brand colors."""
from __future__ import annotations

import os

from PIL import Image, ImageDraw

OUT = os.path.normpath(
    os.path.join(os.path.dirname(__file__), "..", "assets", "icon"),
)
SIZE = 432
CX = CY = SIZE // 2
SAFE_R = int(SIZE * (66 / 108) / 2)

OAK = (0x5D, 0x40, 0x37, 255)
MOSS = (0x55, 0x8B, 0x2F, 255)


def make_shield(draw: ImageDraw.ImageDraw, fill: tuple[int, int, int, int]) -> None:
    w = int(SAFE_R * 1.55)
    h = int(SAFE_R * 1.85)
    left, right = CX - w // 2, CX + w // 2
    top = CY - h // 2
    bottom = CY + h // 2
    pts = [
        (CX, top),
        (right, top + int(h * 0.18)),
        (right, top + int(h * 0.55)),
        (CX, bottom),
        (left, top + int(h * 0.55)),
        (left, top + int(h * 0.18)),
    ]
    draw.polygon(pts, fill=fill)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    badge_r = int(SAFE_R * 0.35)

    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(fg)
    make_shield(d, OAK)
    d.ellipse(
        (CX - badge_r, CY - badge_r - 10, CX + badge_r, CY + badge_r - 10),
        fill=MOSS,
    )
    fg_path = os.path.join(OUT, "fg_oak_moss.png")
    fg.save(fg_path)

    mono = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d2 = ImageDraw.Draw(mono)
    make_shield(d2, (255, 255, 255, 255))
    d2.ellipse(
        (CX - badge_r, CY - badge_r - 10, CX + badge_r, CY + badge_r - 10),
        fill=(255, 255, 255, 255),
    )
    mono_path = os.path.join(OUT, "mono.png")
    mono.save(mono_path)

    print("wrote", fg_path, os.path.getsize(fg_path))
    print("wrote", mono_path, os.path.getsize(mono_path))


if __name__ == "__main__":
    main()
