"""Build the Прокси Дом header mark: house silhouette, DOM knocked out as negative.

Source of truth is the same cutout `bake_web_icon.py` bakes the PNG marks from —
`assets/icon/nav_vpn_proxydom.png`, which reaches this script through the baked
512px `web/proxydom/assets/img/app-icon.png`. The house is traced from that icon
rather than from `mascot-mask.png`: the mask is a derived raster that lost the
door under the O, and the icon is the master the launcher is baked from. The door
is part of the outer contour there, so tracing the icon's own house outline
carries it for free.

Output is a mask, not a picture: CSS paints it in `currentColor`, so the site
keeps one ink for the lockup and the mark stays sharp at any zoom.

Run: `python mobile/tool/build_logo_mark.py` (from mobile/tool, or repo root —
paths resolve off this file, not the cwd).
"""
from __future__ import annotations

import math
import re
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ICON = ROOT / "web" / "proxydom" / "assets" / "img" / "app-icon.png"

# One drawing, two consumers: the landing paints it as a CSS mask, the desktop
# build paints it as an SvgPicture. Generating both from the same trace is the
# whole point — the header of the window and the header of the site are one mark.
WEB_OUT = ROOT / "web" / "proxydom" / "assets" / "img" / "logo-mark.svg"
APP_OUT = ROOT / "mobile" / "assets" / "icon" / "logo_mark_word.svg"

# Same box the button marks use, so the header and the buttons share a silhouette.
VB_W, VB_H = 299.0, 279.0
NB8 = [(-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1)]

# The traced outline is a stair of one-unit wobbles. Resample evenly, low-pass it
# as a closed loop, then refit as cubic segments (Schneider). These are the values
# the button marks shipped with — the house here is the same drawing, so it must
# be smoothed the same way or the two will not match edge for edge.
HOUSE_STEP_PX, HOUSE_TOL_PX, HOUSE_ITERS, HOUSE_SPAN = 3.0, 1.2, 12, 4
# Letterforms are not a wobble, they are a font: resample and fit, no low-pass.
LETTER_STEP, LETTER_TOL = 1.6, 0.8


# ---------------------------------------------------------------- tracing
def flood(mask: np.ndarray, shape) -> np.ndarray:
    """Everything reachable from the border."""
    h, w = shape
    seen = np.zeros_like(mask)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if mask[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if mask[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in NB8:
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return seen


def largest_component(mask: np.ndarray) -> np.ndarray:
    seen = np.zeros_like(mask)
    best: list[tuple[int, int]] = []
    h, w = mask.shape
    for sy in range(h):
        for sx in range(w):
            if not mask[sy, sx] or seen[sy, sx]:
                continue
            q = deque([(sy, sx)])
            seen[sy, sx] = True
            comp = []
            while q:
                y, x = q.popleft()
                comp.append((y, x))
                for dy, dx in NB8:
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        q.append((ny, nx))
            if len(comp) > len(best):
                best = comp
    out = np.zeros_like(mask)
    for y, x in best:
        out[y, x] = True
    return out


def trace_loops(mask: np.ndarray) -> list[list[tuple[float, float]]]:
    """Chain boundary edges into closed loops.

    Each foreground pixel with a background neighbour contributes one directed edge
    along its own side, and every such edge is unique — so chaining start -> end
    cannot be ambiguous. A Moore walk needs a backtrack heuristic to close, and a
    wrong backtrack silently emits thousands of degenerate loops instead of failing.
    """
    h, w = mask.shape
    pad = np.zeros((h + 2, w + 2), dtype=bool)
    pad[1:-1, 1:-1] = mask
    edges: dict[tuple[int, int], tuple[int, int]] = {}
    ys, xs = np.nonzero(pad)
    for y, x in zip(ys, xs):
        if not pad[y - 1, x]:
            edges[(x - 1, y - 1)] = (x, y - 1)
        if not pad[y, x + 1]:
            edges[(x, y - 1)] = (x, y)
        if not pad[y + 1, x]:
            edges[(x, y)] = (x - 1, y)
        if not pad[y, x - 1]:
            edges[(x - 1, y)] = (x - 1, y - 1)
    loops: list[list[tuple[float, float]]] = []
    while edges:
        start = next(iter(edges))
        loop = [start]
        cur = start
        while True:
            nxt = edges.pop(cur, None)
            if nxt is None:
                break
            loop.append(nxt)
            cur = nxt
            if cur == start:
                break
        if len(loop) >= 6:
            loops.append([(float(a), float(b)) for a, b in loop[:-1]])
    return loops


# ---------------------------------------------------------------- geometry
def area(points: list[tuple[float, float]]) -> float:
    s = 0.0
    n = len(points)
    for i in range(n):
        x0, y0 = points[i]
        x1, y1 = points[(i + 1) % n]
        s += x0 * y1 - x1 * y0
    return s / 2.0


def bbox(points: list[tuple[float, float]]) -> tuple[float, float, float, float]:
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return (min(xs), min(ys), max(xs), max(ys))


def resample(points, step):
    out = [points[0]]
    carry = 0.0
    for i in range(1, len(points) + 1):
        a, b = points[i - 1], points[i % len(points)]
        seg = math.dist(a, b)
        if seg == 0:
            continue
        pos = step - carry
        while pos < seg:
            t = pos / seg
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            pos += step
        carry = (carry + seg) % step
    if math.dist(out[-1], out[0]) < step * 0.5:
        out.pop()
    return out


def lowpass(pts, iters, weight=0.25):
    """Circular moving average. Closed loop on purpose: the outline has no ends."""
    for _ in range(iters):
        n = len(pts)
        pts = [
            (
                (1 - 2 * weight) * pts[i][0] + weight * pts[i - 1][0] + weight * pts[(i + 1) % n][0],
                (1 - 2 * weight) * pts[i][1] + weight * pts[i - 1][1] + weight * pts[(i + 1) % n][1],
            )
            for i in range(n)
        ]
    return pts


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def mul(a, s):
    return (a[0] * s, a[1] * s)


def norm(a):
    m = math.hypot(*a)
    return (a[0] / m, a[1] / m) if m else (0.0, 0.0)


def bez_at(bz, t):
    mt = 1 - t
    a, b, c, d = bz
    return (
        mt**3 * a[0] + 3 * mt**2 * t * b[0] + 3 * mt * t**2 * c[0] + t**3 * d[0],
        mt**3 * a[1] + 3 * mt**2 * t * b[1] + 3 * mt * t**2 * c[1] + t**3 * d[1],
    )


def chord_params(pts, first, last):
    u = [0.0]
    for i in range(first + 1, last + 1):
        u.append(u[-1] + math.dist(pts[i - 1], pts[i]))
    total = u[-1] or 1.0
    return [v / total for v in u]


def gen_bezier(pts, first, last, u, t1, t2):
    """Schneider's fit: the end handles are placed at the two estimated inflection
    points, then the two interior control magnitudes come from the least-squares
    solution of the normal equations. The tangent factors must appear in BOTH
    determinants — swapping one for a y value makes the fit split at nearly every
    sample and the tolerance stops doing anything."""
    a0 = pts[first]
    a1 = add(pts[last], mul(t2, -3 * (3 * u[-1] - 1 + 3 * u[-2] - u[-3])))
    a2 = add(pts[first], mul(t1, 3 * u[1] - 3 * u[2] + u[3]))
    tx1, tx2 = t1[0], t2[0]
    c00 = c01 = c11 = x0 = x1 = y0 = y1 = 0.0
    for i in range(first, last + 1):
        t = u[i - first]
        mt = 1 - t
        b0, b1, b2, b3 = mt**3, 3 * mt**2 * t, 3 * mt * t**2, t**3
        tmp_x = -a0[0] * (b0 + b1) + a1[0] * (b2 + b3) - pts[i][0]
        tmp_y = -a0[1] * (b0 + b1) + a1[1] * (b2 + b3) - pts[i][1]
        ax, bx = tx1 * b1, tx2 * b2
        c00 += ax * ax
        c01 += ax * bx
        c11 += bx * bx
        x0 += ax * tmp_x
        x1 += bx * tmp_x
        y0 += ax * tmp_y
        y1 += bx * tmp_y
    det = c00 * c11 - c01 * c01
    chord = math.dist(pts[last], pts[first]) / 3.0
    if abs(det) < 1e-12:
        a1v = a2v = chord
    else:
        a1v = (x0 * c11 - x1 * c01) / det
        a2v = (c00 * x1 - c01 * x0) / det
    if a1v < 1e-6 or a2v < 1e-6 or not math.isfinite(a1v + a2v):
        a1v = a2v = chord
    return [a0, add(a0, mul(t1, a1v)), add(a1, mul(t2, a2v)), pts[last]]


def max_err(pts, first, last, bz, u):
    worst, split = 0.0, (first + last) // 2
    for i in range(first, last + 1):
        e = math.dist(pts[i], bez_at(bz, u[i - first]))
        if e > worst:
            worst, split = e, i
    return worst, split


def newton(pts, first, last, bz, u):
    """Re-solve the parameter values; worth it when the chord lengths are lumpy."""
    p = list(u)
    for _ in range(4):
        for i in range(first, last + 1):
            t = p[i - first]
            q = bez_at(bz, t)
            mt = 1 - t
            d1 = (
                3 * mt**2 * (bz[1][0] - q[0]) + 6 * mt * t * (bz[2][0] - q[0]) + 3 * t**2 * (bz[3][0] - q[0]),
                3 * mt**2 * (bz[1][1] - q[1]) + 6 * mt * t * (bz[2][1] - q[1]) + 3 * t**2 * (bz[3][1] - q[1]),
            )
            d2 = (
                6 * mt * (bz[2][0] - 2 * bz[1][0] + q[0]) + 6 * t * (bz[3][0] - 2 * bz[2][0] + bz[1][0]),
                6 * mt * (bz[2][1] - 2 * bz[1][1] + q[1]) + 6 * t * (bz[3][1] - 2 * bz[2][1] + bz[1][1]),
            )
            ex, ey = q[0] - pts[i][0], q[1] - pts[i][1]
            den = d1[0] ** 2 + d1[1] ** 2 + ex * d2[0] + ey * d2[1]
            if abs(den) > 1e-12:
                p[i - first] = t - (ex * d1[0] + ey * d1[1]) / den
    return p


def fit(pts, first, last, t1, t2, tol, depth=0):
    """The last sample repeats the first, so its travel direction is the chord to
    itself — the wrap tangent has to be read from the second-to-last window, and it
    has to point BACK from the endpoint: pointed forward it hooks past the end and
    leaves a bump on every segment."""
    if last - first + 1 <= 3:
        d = math.dist(pts[last], pts[first]) / 3.0
        return [[pts[first], add(pts[first], mul(t1, d)), add(pts[last], mul(t2, -d)), pts[last]]]
    u = chord_params(pts, first, last)
    bz = gen_bezier(pts, first, last, u, t1, t2)
    err, split = max_err(pts, first, last, bz, u)
    if err < tol or depth > 12:
        return [bz]
    if err < tol * tol:
        u = newton(pts, first, last, bz, u)
        bz = gen_bezier(pts, first, last, u, t1, t2)
        if max_err(pts, first, last, bz, u)[0] < tol:
            return [bz]
    mid = norm(sub(pts[split + 1], pts[split - 1]))
    return fit(pts, first, split, t1, mid, tol, depth + 1) + fit(
        pts, split, last, mid, t2, tol, depth + 1
    )


def fmt(v: float) -> str:
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("", "-0") else s


def to_path(points, step, tol, span=2, pass_iters=0):
    flat = resample(points + [points[0]], step)
    if pass_iters:
        flat = lowpass(flat, pass_iters)
        flat.append(flat[0])
    n = len(flat)
    k = max(1, min(span, (n - 1) // 2))
    tangents = [norm(sub(flat[(i + k) % n], flat[(i - k) % n])) for i in range(n)]
    end_t = norm(sub(flat[n - 1], flat[n - 1 - k]))
    segs = fit(flat, 0, n - 1, tangents[0], end_t, tol)
    out = [f"M {fmt(flat[0][0])} {fmt(flat[0][1])}"]
    for seg in segs:
        _, b, c, e = seg
        out.append(f"C {fmt(b[0])} {fmt(b[1])} {fmt(c[0])} {fmt(c[1])} {fmt(e[0])} {fmt(e[1])}")
    out.append("Z")
    return " ".join(out), len(segs)


def remap_path(d: str, fn) -> str:
    """Apply a point transform to every coordinate pair of an emitted path."""
    toks = re.findall(r"[MCZ]|-?\d*\.?\d+", d)
    out: list[str] = []
    i = 0
    while i < len(toks):
        cmd = toks[i]
        i += 1
        if cmd in ("M", "C"):
            n = 2 if cmd == "M" else 6
            vals = [float(v) for v in toks[i : i + n]]
            i += n
            out.append(cmd)
            for k in range(0, n, 2):
                x, y = fn((vals[k], vals[k + 1]))
                out.append(fmt(x))
                out.append(fmt(y))
        else:
            out.append(cmd)
    return " ".join(out)


# ---------------------------------------------------------------- build
def build() -> None:
    im = Image.open(ICON).convert("RGBA")
    a = np.asarray(im).astype(np.float32)
    alpha = a[..., 3] > 128
    light = (a[..., :3].mean(axis=2) > 140) & alpha
    house = largest_component(light)
    # Fill the holes so the knockout reads as one region rather than a ring.
    solid = house | (~house & ~flood(~house, house.shape))
    letters_mask = solid & (~light) & alpha

    icon_house = max(trace_loops(house), key=lambda lp: abs(area(lp)))
    loops = trace_loops(letters_mask)
    loops.sort(key=lambda lp: abs(area(lp)), reverse=True)

    # Map by bounding box, not by area: the two houses are the same drawing but not
    # the same proportions, and area/centroid alignment drops the word off the body.
    ix0, iy0, ix1, iy1 = bbox(icon_house)
    sx = (VB_W - 1.0) / (ix1 - ix0)
    sy = (VB_H - 1.0) / (iy1 - iy0)

    def map_pt(p):
        return ((p[0] - ix0) * sx, (p[1] - iy0) * sy)

    # Fit the house in icon pixels, where the wobble is; the lengths below are the
    # button marks' viewBox values divided by that scale.
    house_d, house_n = to_path(
        icon_house, HOUSE_STEP_PX / sx, HOUSE_TOL_PX / sx, span=HOUSE_SPAN,
        pass_iters=HOUSE_ITERS,
    )
    house_d = remap_path(house_d, map_pt)

    parts = [house_d]
    curves = house_n
    for lp in loops:
        mapped = [map_pt(p) for p in lp]
        d, n = to_path(mapped, LETTER_STEP, LETTER_TOL)
        parts.append(d)
        curves += n
        bb = bbox(mapped)
        print(f"  letter uv bbox ({bb[0]:6.1f},{bb[1]:6.1f})-({bb[2]:6.1f},{bb[3]:6.1f}) -> {n} curves")

    body = " ".join(parts)
    lines, cur = [], ""
    for tok in body.split(" "):
        if cur and len(cur) + 1 + len(tok) > 104:
            lines.append(cur)
            cur = tok
        else:
            cur = f"{cur} {tok}".strip()
    if cur:
        lines.append(cur)
    svg = (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 299 279" '
        'fill-rule="evenodd">\n'
        f'  <path d="    {"\n    ".join(lines)}"/>\n'
        "</svg>\n"
    )
    for out in (WEB_OUT, APP_OUT):
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(svg, encoding="utf-8")
        print(f"wrote {out.relative_to(ROOT)} {len(svg.encode('utf-8'))} bytes")
    print(f"house {house_n} + letters {curves - house_n} curves")
    return None


if __name__ == "__main__":
    sys.exit(build())