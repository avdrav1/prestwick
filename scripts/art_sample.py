#!/usr/bin/env python3
"""E5-S1 sample for the "procedural base" art option: one fairway frame made by a rule, not by hand.

Not final art and not read by the game. It writes a copy of the label-free Play surfaces sheet
(art/tiles/surfaces_play_placeholder.png) with frame 0 (fairway) replaced by a generated one, to
art/tiles/surfaces_sample_procedural.png. tests/fixtures/art_sample_shot.tscn swaps it in for a
screenshot beside the placeholder (docs/playtests/2026-11-10-e5-art-options.md).

The fairway rule: mown stripes along one isometric axis (light bands sprinkled with tee_light,
dark bands with fairway_dark) over the plain fairway colour, which stays the most common colour
(the frame's fill, tests/test_course_view.gd). Every pixel is a palette colour. The pattern is a
function of a = x + 2y and b = x - 2y taken mod 64, so it repeats under the tile lattice
(32, 16) and (32, -16) and neighbouring tiles join without a seam.

Usage: python3 scripts/art_sample.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import placeholder as ph  # noqa: E402

OUT = ph.ROOT / "art" / "tiles" / "surfaces_sample_procedural.png"

# Share of pixels sprinkled in each band (designer numbers for the sample only).
LIGHT_SHARE = 0.30
DARK_SHARE = 0.14
GRAIN_SHARE = 0.04
STRIPE_PERIOD = 64  # in b = x - 2y units; must divide 64 to tile


def _hash(a: int, b: int, salt: int) -> float:
    """A repeatable value in [0, 1) for a lattice-periodic pixel."""
    h = (a * 374761393 + b * 668265263 + salt * 2246822519) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65536.0


def fairway_pixel(x: int, y: int, p: dict[str, ph.Color]) -> ph.Color:
    a = (x + 2 * y) % 64
    b = (x - 2 * y) % 64
    light_band = (b % STRIPE_PERIOD) < STRIPE_PERIOD // 2
    n = _hash(a, b, 1)
    if light_band and n < LIGHT_SHARE:
        return p["tee_light"]
    if not light_band and n < DARK_SHARE:
        return p["fairway_dark"]
    if _hash(a, b, 2) < GRAIN_SHARE:  # a few blades of the other shade, so bands are not flat
        return p["fairway_dark"] if light_band else p["tee_light"]
    return p["fairway"]


def fairway_frame(p: dict[str, ph.Color]) -> ph.Image:
    img = ph.Image(ph.TILE_W, ph.TILE_H)
    for y in range(ph.TILE_H):
        for x in range(ph.TILE_W):
            if not ph.in_diamond(x, y):
                continue
            if y >= ph.TILE_H // 2 and not ph.in_diamond(x, y + 1):
                img.set(x, y, p[ph.EDGE["fairway"]])  # the spec's one shared bottom seam
            else:
                img.set(x, y, fairway_pixel(x, y, p))
    return img


def main() -> int:
    p = ph.load_palette()
    p["tree_light_px"] = p["rough"]
    frames = [ph.surface_frame(n, lbl, p, labelled=False) for n, lbl in ph.SURFACES]
    frames[0] = fairway_frame(p)
    ph.sheet(frames).save_png(OUT)
    counts: dict[ph.Color, int] = {}
    for y in range(ph.TILE_H):
        for x in range(ph.TILE_W):
            if ph.in_diamond(x, y):
                c = frames[0].get(x, y)
                counts[c] = counts.get(c, 0) + 1
    total = sum(counts.values())
    mean = sum(ph.luminance(c) * k for c, k in counts.items()) / total
    fill = max(counts, key=lambda c: counts[c])
    print(f"{OUT.relative_to(ph.ROOT)}: fairway fill {fill[:3]}, mean luma {mean:.1f} (BT.601)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
