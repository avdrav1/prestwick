#!/usr/bin/env python3
"""Final terrain art for Prestwick (E5-S2, D62): the 9 surface textures and the unowned-land hatch,
made by rule from art/palette.gpl. Stdlib only; rerun after any palette or rule change.

Usage:
  python3 scripts/art_terrain.py            -> art/tiles/surfaces_final.png, art/tiles/land_final.png
  python3 scripts/art_terrain.py --check    -> print the value report only, write nothing

Surfaces (art/specs/surfaces.md). A surface's pattern repeats every MACRO x MACRO tiles, not every
tile, so mowing stripes can be a tile or two wide (SimGolf) and rough and water do not look stamped.
The sheet holds MACRO * MACRO frames per surface (TileSheet.macro): frames 0 to 8 are the variant
(0, 0) of each surface in surface enum order, so frame index == surface value still names the
surface, and variant (a, b) of surface s is frame s + 9 * (a + b * MACRO). Tile (x, y) of the course
draws variant (x mod MACRO, y mod MACRO) (TileSheet.variant_of, course/terrain_mesh.gd).

Every rule is a function of the pixel's place on the course, written as the lattice-periodic pair
A = X + 2Y and B = 2Y - X of its course pixel (X, Y) (one tile step +x adds 64 to A, +y adds 64 to
B), taken mod 64 * MACRO, so neighbouring tiles join without a seam on any slope (the mesh maps
each frame onto its tile, D50) and the pattern repeats exactly on the macro lattice.

The value rules of tests/test_course_view.gd are checked here too (Rec. 709, mean and fill over
all of a surface's variants) so a retune can be judged before the game runs.
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import placeholder as ph  # noqa: E402  (Image, palette, sheet, diamond geometry)

SURFACES_OUT = ph.ROOT / "art" / "tiles" / "surfaces_final.png"
LAND_OUT = ph.ROOT / "art" / "tiles" / "land_final.png"

SURFACES = ["fairway", "rough", "green", "tee", "bunker", "water", "trees", "cart_path", "oob"]

# Tiles per side of a surface's repeat. Art geometry, read by art/tiles/surfaces.tres (macro).
MACRO = 4
PERIOD = 64 * MACRO  # in A and B units

# --- designer numbers (rerun to retune) ------------------------------------------------------
# Fairway: mowing stripes along the x axis, each STRIPE_TILES tiles wide (2 * STRIPE_TILES must
# divide MACRO), the light one in tee_light and LIGHT_SHARE of the pair, so plain fairway stays
# the fill. STRIPE_DITHER px of 2 x 2 dither soften each stripe edge. FAIRWAY_GRAIN: a few blades.
STRIPE_TILES = 2
LIGHT_SHARE = 0.44
STRIPE_DITHER = 3.0
FAIRWAY_GRAIN = 0.006
# Rough: tufts (a dark blade pair with a lit tip), denser in slow patches.
TUFT_MIN = 0.020
TUFT_MAX = 0.060
# Water: the chance a pixel of a crest row starts a crest.
CREST_SHARE = 0.14
# Trees: crown radius, px.
CROWN_R = 3.3


def _hash(a: int, b: int, salt: int) -> float:
    """A repeatable value in [0, 1) for (a, b) (already reduced mod PERIOD)."""
    h = (a * 374761393 + b * 668265263 + salt * 2246822519) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65536.0


def _ab(x: int, y: int) -> tuple[int, int]:
    return (x + 2 * y) % PERIOD, (2 * y - x) % PERIOD


def _uv(x: int, y: int) -> tuple[float, float]:
    """Course tile coordinates of course pixel (x, y)'s centre (tile centres are whole)."""
    px, py = x + 0.5, y + 0.5
    return (px / 32 + py / 16) / 2, (py / 16 - px / 32) / 2


def _slow(u: float, v: float, salt: int) -> float:
    """Smooth noise in [0, 1], periodic over MACRO tiles: a few integer-frequency waves."""
    t = 2 * math.pi / MACRO
    s = (math.sin(t * (u + 2 * v) + salt) + math.sin(t * (2 * u - v) + 1.7 * salt)
         + 0.5 * math.sin(t * (3 * u + v) + 2.3 * salt))
    return (s / 2.5 + 1) / 2


# --- surface rules: course pixel (x, y) -> palette name ----------------------------------------

def fairway(x: int, y: int) -> str:
    _, v = _uv(x, y)
    period = 2 * STRIPE_TILES
    f = (v + 0.5) % period  # stripe edges run through tile middles, not along the grid
    light_w = LIGHT_SHARE * period
    # Distance in screen px to the nearest stripe edge (one tile of v is about 28.6 px across).
    d = min(abs(f), abs(f - light_w), abs(f - period)) * 28.6
    light = f < light_w
    if d < STRIPE_DITHER:
        # Each side of the edge keeps its own colour on every other 2 x 2 cell.
        if ((x // 2) + (y // 2)) % 2 == 0:
            light = not light
    a, b = _ab(x, y)
    if _hash(a, b, 11) < FAIRWAY_GRAIN:
        return "fairway" if light else "fairway_dark"
    return "tee_light" if light else "fairway"


def _tuft_anchor(x: int, y: int) -> bool:
    a, b = _ab(x, y)
    u, v = _uv(x, y)
    dens = TUFT_MIN + (TUFT_MAX - TUFT_MIN) * _slow(u, v, 3)
    return _hash(a, b, 21) < dens


def rough(x: int, y: int) -> str:
    # A tuft: two dark blades side by side and a lit tip above the left one.
    if _tuft_anchor(x, y) or _tuft_anchor(x - 1, y):
        return "rough_dark"
    if _tuft_anchor(x, y + 1):
        return "fairway"
    return "rough"


def green(x: int, y: int) -> str:
    # Cross-hatched: both screen diagonals every 8 px, one dark, one light, so the hatch is soft.
    if (x + y) % 8 == 0:
        return "green_dark"
    if (x - y) % 8 == 0:
        return "green_light" if (x // 2) % 2 == 0 else "green"
    return "green"


def tee(x: int, y: int) -> str:
    # Checkered: mown squares half a tile wide along the grid axes; the dark squares are inset so
    # tee_light is the fill.
    a, b = _ab(x, y)
    if ((a // 32) + (b // 32)) % 2 == 1 and 3 <= a % 32 < 29 and 3 <= b % 32 < 29:
        return "tee_dark"
    return "tee_light"


def bunker(x: int, y: int) -> str:
    # Dotted: a regular grid of 2 x 1 dots, rows offset, with a light grain between.
    row = y // 4
    if y % 4 == 1 and (x + 4 * (row % 2)) % 8 in (1, 2):
        return "sand_dark"
    a, b = _ab(x, y)
    if _hash(a, b, 31) < 0.05:
        return "sand_light"
    return "sand"


def _crest_anchor(x: int, y: int) -> bool:
    if y % 4 != 0:
        return False
    a, b = _ab(x, y)
    return _hash(a, b, 41) < CREST_SHARE


def water(x: int, y: int) -> str:
    # Waves: deep water (water_dark) under rows of small crests 4 px apart, scattered: each a
    # 6 px swell of water with a 4 px water_light arc on top, so water reads darker than rough
    # by value and by a light pattern where rough's flecks are dark (grayscale, E5-S2).
    for dx in range(6):
        if _crest_anchor(x - dx, y + 1) and 1 <= dx <= 4:
            return "water_light"
        if _crest_anchor(x - dx, y):
            return "water"
    return "water_dark"


def trees(x: int, y: int) -> str:
    # Canopy: round crowns on a staggered grid, lit on the upper left, on dark ground.
    cx = (x + 4 * ((y // 8) % 2)) % 8 - 3.5
    cy = y % 8 - 3.5
    d2 = cx * cx + cy * cy
    if d2 <= CROWN_R * CROWN_R:
        if cx + cy < -3.0:
            return "rough"
        return "tree"
    return "tree_dark"


def cart_path(x: int, y: int) -> str:
    # Lined: lines along the x axis every 16 px of B (about 7 px apart on screen), grit between.
    a, b = _ab(x, y)
    if b % 16 in (0, 1, 2):
        return "path_dark"
    if _hash(a, b, 51) < 0.04:
        return "path_dark"
    return "path"


def oob(x: int, y: int) -> str:
    # Bold diagonal stripes.
    return "oob_dark" if ((x + y) // 4) % 2 == 0 else "oob"


RULES = {"fairway": fairway, "rough": rough, "green": green, "tee": tee, "bunker": bunker,
         "water": water, "trees": trees, "cart_path": cart_path, "oob": oob}


def surface_frame(name: str, ta: int, tb: int, p: dict[str, ph.Color]) -> ph.Image:
    """Variant (ta, tb): the tile at (ta, tb) of the surface's MACRO x MACRO repeat."""
    img = ph.Image(ph.TILE_W, ph.TILE_H)
    ox = (ta - tb) * 32 - 32
    oy = (ta + tb) * 16 - 16
    rule = RULES[name]
    for y in range(ph.TILE_H):
        for x in range(ph.TILE_W):
            if ph.in_diamond(x, y):
                img.set(x, y, p[rule(ox + x, oy + y)])
    return img


def build_surfaces(p: dict[str, ph.Color]) -> list[ph.Image]:
    frames: list[ph.Image] = []
    for k in range(MACRO * MACRO):
        ta, tb = k % MACRO, k // MACRO
        for name in SURFACES:
            frames.append(surface_frame(name, ta, tb, p))
    return frames


# --- land hatch (art/specs/land.md) ------------------------------------------------------------
# The E6-S5 rule stands as final art (D62): a screen-diagonal ink hatch and dashed chalk-and-ink
# parcel lines.

# Frame index is a mask of the edges that lie on a parcel edge: bit 0 "w" the back-left edge
# (towards x - 1), bit 1 "n" the back-right (y - 1), bit 2 "e" the front-right (x + 1), bit 3
# "s" the front-left (y + 1). Frame 0 "hatch" is the pattern alone.
LAND_SIDES = ["w", "n", "e", "s"]
LAND = ["hatch" + ("_" + "".join(LAND_SIDES[b] for b in range(4) if m >> b & 1) if m else "")
        for m in range(16)]
# Screen-diagonal hatch, 2 px of ink every 8 px. 8 divides 32 and 16, so the lines of
# neighbouring tiles (and of tiles one step higher) join into one pattern.
LAND_HATCH_PERIOD = 8
LAND_HATCH_WIDTH = 2
# The parcel edge line, px straight down (or up) from the edge, inside the top.
LAND_EDGE_PX = 2
# The line is dashed, a survey-stake line: chalk then ink, LAND_DASH_PX of screen x each.
# The edge cue's lip is one solid chalk line (art/specs/edge_cue.md), so a dashed line never
# reads as a one-step rise. 2 * 8 = 16 px divides 32, so dashes join along a parcel edge.
LAND_DASH_PX = 8


def land_frame(mask: int, p: dict[str, ph.Color]) -> ph.Image:
    img = ph.Image(ph.TILE_W, ph.TILE_H)
    for y in range(ph.TILE_H):
        for x in range(ph.TILE_W):
            if not ph.in_diamond(x, y):
                continue
            dx = (x + 0.5 - ph.TILE_W / 2) / (ph.TILE_W / 2)
            dy = (y + 0.5 - ph.TILE_H / 2) / (ph.TILE_H / 2)
            # Closeness to each edge's line, 1 on the line: w up-left, n up-right,
            # e down-right, s down-left.
            near = [-dx - dy, dx - dy, dx + dy, -dx + dy]
            edge = any(mask >> b & 1 and (1 - near[b]) * (ph.TILE_H / 2) < LAND_EDGE_PX for b in range(4))
            if edge:
                img.set(x, y, p["chalk"] if (x // LAND_DASH_PX) % 2 == 0 else p["ink"])
            elif (x + y) % LAND_HATCH_PERIOD < LAND_HATCH_WIDTH:
                img.set(x, y, p["ink"])
    return img


def build_land(p: dict[str, ph.Color]) -> ph.Image:
    return ph.sheet([land_frame(m, p) for m in range(len(LAND))])


# --- value report ------------------------------------------------------------------------------

def rec709(c: ph.Color) -> float:
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def values(frames: list[ph.Image], s: int) -> tuple[float, ph.Color, dict[ph.Color, int]]:
    counts: dict[ph.Color, int] = {}
    for k in range(MACRO * MACRO):
        img = frames[s + len(SURFACES) * k]
        for c in img.px:
            if c[3]:
                counts[c] = counts.get(c, 0) + 1
    total = sum(counts.values())
    mean = sum(rec709(c) * n for c, n in counts.items()) / total
    fill = max(counts, key=lambda c: counts[c])
    return mean, fill, counts


def report(frames: list[ph.Image], p: dict[str, ph.Color]) -> None:
    names = {v: k for k, v in p.items()}
    for s, name in enumerate(SURFACES):
        mean, fill, counts = values(frames, s)
        total = sum(counts.values())
        shares = ", ".join(f"{names[c]} {n / total:.0%}" for c, n in sorted(counts.items(), key=lambda kv: -kv[1]))
        print(f"  {name:9s} mean {mean:6.1f}  fill {names[fill]} {rec709(fill):6.1f}   {shares}")


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="print the value report, write nothing")
    args = ap.parse_args(argv)
    p = ph.load_palette()
    frames = build_surfaces(p)
    print("Rec. 709 over all variants:")
    report(frames, p)
    if args.check:
        return 0
    surf = ph.sheet(frames)
    land = build_land(p)
    for path, img in ((SURFACES_OUT, surf), (LAND_OUT, land)):
        ph.check_palette(img, p)
        img.save_png(path)
        print(f"{path.relative_to(ph.ROOT)} {img.width}x{img.height}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
