"""Bake the Прокси Дом app mark for the public site.

Source: `assets/icon/nav_vpn_proxydom.png` — the same cutout the Windows runner
icon is baked from. Two outputs, both from that one source, so the header
lockup, the download card and the browser tab can never drift apart:

  `web/proxydom/assets/img/app-icon.png`  — the card mark, 512px
  `web/proxydom/assets/img/favicon-32.png` — the tab mark, 32px

The corner pass lives in `bake_windows_icon` — both consumers want a mark that
adapts to the surface behind it, and a black field baked into the PNG does not.

Run: `python mobile/tool/bake_web_icon.py`
"""
from __future__ import annotations

import os

from PIL import Image

from bake_windows_icon import ROOT, open_corners, SRC

IMG_DIR = os.path.normpath(
    os.path.join(ROOT, "..", "web", "proxydom", "assets", "img")
)
# Two times the largest rendered edge (56px in the card, 34px in the lockup).
SIZE = 512
# Browsers pull the tab icon at 16 and 32; one 32px file covers both.
FAVICON_SIZE = 32


def main() -> None:
    mark = open_corners(Image.open(SRC))
    os.makedirs(IMG_DIR, exist_ok=True)

    card = mark.resize((SIZE, SIZE), Image.LANCZOS)
    card_path = os.path.join(IMG_DIR, "app-icon.png")
    card.save(card_path, format="PNG", optimize=True)
    print("wrote", card_path, os.path.getsize(card_path), card.size)

    fav = mark.resize((FAVICON_SIZE, FAVICON_SIZE), Image.LANCZOS)
    fav_path = os.path.join(IMG_DIR, "favicon-32.png")
    fav.save(fav_path, format="PNG", optimize=True)
    print("wrote", fav_path, os.path.getsize(fav_path), fav.size)


if __name__ == "__main__":
    main()