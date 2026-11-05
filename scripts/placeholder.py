#!/usr/bin/env python3
"""Generate placeholder art for Prestwick from art/palette.gpl. Stdlib only.

Usage:
  scripts/placeholder.py surfaces            -> art/tiles/surfaces_placeholder.png
  scripts/placeholder.py risers              -> art/tiles/risers_placeholder.png
  scripts/placeholder.py edges               -> art/tiles/edges_placeholder.png
  scripts/placeholder.py land                -> art/tiles/land_placeholder.png
  scripts/placeholder.py golfer              -> art/sprites/golfer_{idle,walk,swing}_placeholder.png
                                                and golfer_shirts_placeholder.png (E3-S28)
  scripts/placeholder.py all                 -> all of the above
  scripts/placeholder.py <thing> --size WxH --frames N [--folder sprites] [--color name]
                                             -> art/<folder>/<thing>_placeholder.png

Sheets follow the art-spec constants: PNG, no padding, 1 px transparent gutter
between frames, one row. Every pixel is a palette color or fully transparent.
Placeholders are never final; the spec in art/specs/ is the handoff.
"""
from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PALETTE_PATH = ROOT / "art" / "palette.gpl"

TILE_W = 64
TILE_H = 32
RISER_PX = 16
GUTTER = 1

Color = tuple[int, int, int, int]
CLEAR: Color = (0, 0, 0, 0)


# --- palette -------------------------------------------------------------

def load_palette(path: Path = PALETTE_PATH) -> dict[str, Color]:
    colors: dict[str, Color] = {}
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith(("GIMP", "Name:", "Columns:", "#")):
            continue
        parts = line.split()
        if len(parts) < 4:
            raise ValueError(f"bad palette line: {line!r}")
        r, g, b = (int(p) for p in parts[:3])
        colors[" ".join(parts[3:])] = (r, g, b, 255)
    return colors


# --- image ---------------------------------------------------------------

class Image:
    def __init__(self, width: int, height: int) -> None:
        self.width = width
        self.height = height
        self.px: list[Color] = [CLEAR] * (width * height)

    def set(self, x: int, y: int, c: Color) -> None:
        if 0 <= x < self.width and 0 <= y < self.height:
            self.px[y * self.width + x] = c

    def get(self, x: int, y: int) -> Color:
        return self.px[y * self.width + x]

    def blit(self, other: "Image", ox: int, oy: int) -> None:
        for y in range(other.height):
            for x in range(other.width):
                c = other.get(x, y)
                if c[3]:
                    self.set(ox + x, oy + y, c)

    def save_png(self, path: Path) -> None:
        raw = bytearray()
        for y in range(self.height):
            raw.append(0)  # filter: none
            for x in range(self.width):
                raw.extend(self.get(x, y))

        def chunk(tag: bytes, data: bytes) -> bytes:
            body = tag + data
            return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

        ihdr = struct.pack(">IIBBBBB", self.width, self.height, 8, 6, 0, 0, 0)
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(png)


def sheet(frames: list[Image]) -> Image:
    w = sum(f.width for f in frames) + GUTTER * (len(frames) - 1)
    h = max(f.height for f in frames)
    out = Image(w, h)
    x = 0
    for f in frames:
        out.blit(f, x, 0)
        x += f.width + GUTTER
    return out


# --- 3x5 label font --------------------------------------------------------

FONT = {
    "A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
    "C": ["011", "100", "100", "100", "011"], "D": ["110", "101", "101", "101", "110"],
    "E": ["111", "100", "110", "100", "111"], "F": ["111", "100", "110", "100", "100"],
    "G": ["011", "100", "101", "101", "011"], "H": ["101", "101", "111", "101", "101"],
    "I": ["111", "010", "010", "010", "111"], "K": ["101", "101", "110", "101", "101"],
    "L": ["100", "100", "100", "100", "111"], "M": ["101", "111", "111", "101", "101"],
    "N": ["110", "101", "101", "101", "101"], "O": ["010", "101", "101", "101", "010"],
    "P": ["110", "101", "110", "100", "100"], "R": ["110", "101", "110", "101", "101"],
    "S": ["011", "100", "010", "001", "110"], "T": ["111", "010", "010", "010", "010"],
    "U": ["101", "101", "101", "101", "111"], "W": ["101", "101", "111", "111", "101"],
    "X": ["101", "101", "010", "101", "101"], "Y": ["101", "101", "010", "010", "010"],
    "0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
    "2": ["110", "001", "010", "100", "111"], "3": ["110", "001", "010", "001", "110"],
    "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "110", "001", "110"],
    "6": ["011", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
    "8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "110"],
}


def draw_label(img: Image, text: str, x: int, y: int, c: Color) -> None:
    for ch in text.upper():
        glyph = FONT.get(ch)
        if glyph:
            for gy, row in enumerate(glyph):
                for gx, bit in enumerate(row):
                    if bit == "1":
                        img.set(x + gx, y + gy, c)
        x += 4


def luminance(c: Color) -> float:
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


# --- isometric geometry ----------------------------------------------------

def in_diamond(x: int, y: int, oy: int = 0) -> bool:
    """Pixel-center test for the 64x32 top diamond, shifted down by oy px."""
    cx, cy = TILE_W / 2, TILE_H / 2 + oy
    return abs(x + 0.5 - cx) / (TILE_W / 2) + abs(y + 0.5 - cy) / (TILE_H / 2) <= 1.0


def in_riser_band(x: int, y: int) -> bool:
    """One height step of side wall, in the same 64x32 box as a tile at the lower height.

    The band is what the diamond sweeps as it rises one step (RISER_PX), minus the
    raised diamond itself, so it fills exactly the gap between the two tops.

    The sweep is sampled every half pixel: whole-pixel steps miss the corner columns 0
    and 63 (the diamond never covers them), which left a 1 px seam between neighboring
    walls in the course renderer (found in E1-S4).
    """
    if in_diamond(x, y, -RISER_PX):
        return False
    return any(in_diamond(x, y, -s / 2) for s in range(2 * RISER_PX + 1))


# --- surfaces --------------------------------------------------------------

# Index is the surface enum from /course-file: 0 fairway .. 7 cart_path, 8 oob.
SURFACES = [
    ("fairway", "FW"),
    ("rough", "RO"),
    ("green", "GR"),
    ("tee", "TE"),
    ("bunker", "BU"),
    ("water", "WA"),
    ("trees", "TR"),
    ("cart_path", "CP"),
    ("oob", "OB"),
]


def surface_pixel(name: str, x: int, y: int, p: dict[str, Color]) -> Color:
    """Base color plus colorblind pattern. Periods divide 32x16, so tiles join seamlessly."""
    if name == "fairway":  # plain
        return p["fairway"]
    if name == "rough":  # stippled: irregular dark and light flecks
        if (x % 8, y % 8) in {(1, 1), (5, 2), (2, 5), (6, 6)}:
            return p["rough_dark"]
        if (x % 8, y % 8) in {(4, 4)}:
            return p["fairway"]
        return p["rough"]
    if name == "green":  # cross-hatched: both 45 degree diagonals
        if (x + y) % 8 == 0 or (x - y) % 8 == 0:
            return p["green_dark"]
        return p["green"]
    if name == "tee":  # checkered: mown squares in two shades
        return p["tee_light"] if ((x // 4) + (y // 4)) % 2 == 0 else p["tee_dark"]
    if name == "bunker":  # dotted: regular grid of dots, rows offset
        if y % 4 == 1 and (x + 2 * ((y // 4) % 2)) % 4 == 1:
            return p["sand_dark"]
        return p["sand"]
    if name == "water":  # waves: small light crests, alternate rows offset
        wx = (x + 4 * ((y // 8) % 2)) % 8
        if (y % 8 == 3 and wx in (1, 2)) or (y % 8 == 4 and wx in (0, 3)):
            return p["water_light"]
        return p["water"]
    if name == "trees":  # canopy: dark crowns with a lit pixel, on a staggered grid
        cx = (x + 4 * ((y // 8) % 2)) % 8
        cy = y % 8
        d = (cx - 3.5) ** 2 + (cy - 3.5) ** 2
        if d <= 4.5:
            return p["tree_light_px"] if (cx, cy) == (3, 2) else p["tree"]
        return p["tree_dark"]
    if name == "cart_path":  # lined: lines along one isometric axis
        if (x - 2 * y) % 8 == 0 or (x - 2 * y) % 8 == 1:
            return p["path_dark"]
        return p["path"]
    if name == "oob":  # bold diagonal stripes
        return p["oob_dark"] if ((x + y) // 4) % 2 == 0 else p["oob"]
    raise KeyError(name)


EDGE = {
    "fairway": "fairway_dark", "rough": "rough_dark", "green": "green_dark", "tee": "tee_dark",
    "bunker": "sand_dark", "water": "water_dark", "trees": "ink", "cart_path": "path_dark",
    "oob": "slate_dark",
}


def surface_frame(name: str, label: str, p: dict[str, Color]) -> Image:
    img = Image(TILE_W, TILE_H)
    for y in range(TILE_H):
        for x in range(TILE_W):
            if not in_diamond(x, y):
                continue
            # Bottom edges only, so two neighbors share one 1 px seam.
            if y >= TILE_H // 2 and not in_diamond(x, y + 1):
                img.set(x, y, p[EDGE[name]])
            else:
                img.set(x, y, surface_pixel(name, x, y, p))
    # Label in the left corner, clear of the pattern's center.
    lx, ly = 8, 14
    for yy in range(ly - 1, ly + 6):
        for xx in range(lx - 1, lx + 4 * len(label)):
            img.set(xx, yy, p["ink"] if luminance(surface_pixel(name, 0, 0, p)) > 140 else p["chalk"])
    draw_label(img, label, lx, ly, p["chalk"] if luminance(surface_pixel(name, 0, 0, p)) > 140 else p["ink"])
    return img


def build_surfaces(p: dict[str, Color]) -> Image:
    p = dict(p)
    p["tree_light_px"] = p["rough"]
    return sheet([surface_frame(n, lbl, p) for n, lbl in SURFACES])


# --- risers ----------------------------------------------------------------

RISERS = [("both", "RB"), ("left", "RL"), ("right", "RR")]


def riser_frame(which: str, label: str, p: dict[str, Color]) -> Image:
    img = Image(TILE_W, TILE_H)
    for y in range(TILE_H):
        for x in range(TILE_W):
            if not in_riser_band(x, y):
                continue
            left = x < TILE_W // 2
            if (which == "left" and not left) or (which == "right" and left):
                continue
            # Strata run parallel to the face's top edge, every 5 px down the wall.
            slope_y = y - (x // 2 if left else (TILE_W - 1 - x) // 2)
            base = p["earth_dark"] if left else p["earth"]
            stripe = p["ink"] if left else p["earth_dark"]
            c = stripe if slope_y % 6 == 5 else base
            if not in_riser_band(x, y + 1):  # foot of the wall
                c = p["ink"]
            if x in (TILE_W // 2 - 1, TILE_W // 2) and which == "both":  # front corner
                c = p["earth_light"]
            img.set(x, y, c)
    if which in ("both", "left"):
        draw_label(img, label, 6, 9, p["chalk"])
    else:
        draw_label(img, label, TILE_W - 6 - 4 * len(label), 9, p["chalk"])
    return img


def build_risers(p: dict[str, Color]) -> Image:
    return sheet([riser_frame(w, lbl, p) for w, lbl in RISERS])


# --- edge cue (E1-S10) -----------------------------------------------------

# Frame names: "l" is the back-left edge (towards x - 1), "r" the back-right edge
# (towards y - 1); the digit is the rise, 1 step or 2 for two or more. Order is fixed.
EDGES = ["l1", "l2", "r1", "r2", "l1r1", "l1r2", "l2r1", "l2r2"]
# The frame's anchor sits 2 px lower than a surface tile's, so the shadow line has room
# above the diamond's top corner. Bands are measured straight down from the top edge.
EDGE_ANCHOR_Y = 18
# One lip per step class: a dark line, then a bright line 2 px below it. The first lip's
# dark line lies outside the top (the shadow on the lower tile's side of the edge); the
# second sits inside, so on light ground (sand, green) the count still reads as two dark
# lines, and on dark ground as two bright ones. 2 px bands survive nearest sampling at 0.5x.
EDGE_LIPS = [((-2, 0), (0, 2)), ((2, 4), (4, 6))]


def edge_frame(name: str, p: dict[str, Color]) -> Image:
    img = Image(TILE_W, TILE_H)
    oy = EDGE_ANCHOR_Y - TILE_H // 2
    rises = {"l": 0, "r": 0}
    for side, n in zip(name[::2], name[1::2]):
        rises[side] = int(n)
    top_corner_y = EDGE_ANCHOR_Y - TILE_H / 2
    for y in range(TILE_H):
        for x in range(TILE_W):
            inside = in_diamond(x, y, oy)
            dx = x + 0.5 - TILE_W / 2
            for side, sign in (("l", -1), ("r", 1)):
                steps = rises[side]
                if not steps:
                    continue
                # Straight down from the edge's whole line, not only its half of the frame,
                # so the lines of neighbouring tiles along one edge join without gaps.
                v = y + 0.5 - (top_corner_y + sign * dx / 2)
                own_half = (dx < 0) if side == "l" else (dx >= 0)
                for (d0, d1), (b0, b1) in EDGE_LIPS[:steps]:
                    if d0 <= v < d1 and (inside or (own_half and d1 <= 0)):
                        img.set(x, y, p["ink"])
                    elif inside and b0 <= v < b1:
                        img.set(x, y, p["chalk"])
    return img


def build_edges(p: dict[str, Color]) -> Image:
    return sheet([edge_frame(n, p) for n in EDGES])


# --- unowned land (E6-S5) -------------------------------------------------

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


def land_frame(mask: int, p: dict[str, Color]) -> Image:
    img = Image(TILE_W, TILE_H)
    for y in range(TILE_H):
        for x in range(TILE_W):
            if not in_diamond(x, y):
                continue
            dx = (x + 0.5 - TILE_W / 2) / (TILE_W / 2)
            dy = (y + 0.5 - TILE_H / 2) / (TILE_H / 2)
            # Closeness to each edge's line, 1 on the line: w up-left, n up-right,
            # e down-right, s down-left.
            near = [-dx - dy, dx - dy, dx + dy, -dx + dy]
            edge = any(mask >> b & 1 and (1 - near[b]) * (TILE_H / 2) < LAND_EDGE_PX for b in range(4))
            if edge:
                img.set(x, y, p["chalk"] if (x // LAND_DASH_PX) % 2 == 0 else p["ink"])
            elif (x + y) % LAND_HATCH_PERIOD < LAND_HATCH_WIDTH:
                img.set(x, y, p["ink"])
    return img


def build_land(p: dict[str, Color]) -> Image:
    return sheet([land_frame(m, p) for m in range(len(LAND))])


# --- golfer (E3-S5) --------------------------------------------------------

# art/specs/golfer.md. Three sheets, one per state, each one row: 8 directions in GOLFER_DIRS
# order, and for each direction that state's frames in order. Frame names "<dir>_<n>".
GOLFER_W = 24
GOLFER_H = 24
# The feet: the pixel that sits on the ground point the projection returns.
GOLFER_ANCHOR = (12, 23)
# Screen directions, clockwise from straight down the screen (toward the camera).
GOLFER_DIRS = ["s", "sw", "w", "nw", "n", "ne", "e", "se"]
# Screen step of each direction, x right and y down, for the cap's brim.
GOLFER_DIR_STEP = {
    "s": (0, 1), "sw": (-1, 1), "w": (-1, 0), "nw": (-1, -1),
    "n": (0, -1), "ne": (1, -1), "e": (1, 0), "se": (1, 1),
}
GOLFER_STATES = [("idle", 2), ("walk", 4), ("swing", 6)]
# Club angle per swing frame, degrees from straight down, toward the facing side: address,
# takeaway, top, down, impact, finish.
GOLFER_SWING_DEG = [10, -60, -150, -60, 10, 150]


def golfer_frame(state: str, d: str, n: int, p: dict[str, Color]) -> Image:
    import math
    img = Image(GOLFER_W, GOLFER_H)
    sx, sy = GOLFER_DIR_STEP[d]
    side = sx if sx else 1
    back = sy < 0
    cx = GOLFER_ANCHOR[0]
    bob = 1 if state == "idle" and n == 1 else 0
    # Legs: slate_dark trousers from y 16 to the feet; a walk swings them in a 4-frame stride.
    stride = [0, 2, 0, -2][n] if state == "walk" else 0
    for y in range(16, 24):
        t = (y - 16) / 7
        for lx, sgn in ((cx - 2, 1), (cx + 1, -1)):
            off = round(stride * sgn * t)
            for x in (lx + off, lx + off + 1):
                img.set(x, y, p["slate_dark"])
    # Body: a chalk shirt on an ink outline, y 9 to 16.
    for y in range(9 + bob, 17):
        for x in range(cx - 4, cx + 4):
            edge = x in (cx - 4, cx + 3) or y == 9 + bob
            img.set(x, y, p["ink"] if edge else p["chalk"])
    # Head: skin, or the back of the head (earth_dark hair) facing away, under a flag_red cap.
    for y in range(4 + bob, 9 + bob):
        for x in range(cx - 2, cx + 2):
            img.set(x, y, p["earth_dark"] if back else p["skin"])
    for x in range(cx - 3, cx + 3):
        img.set(x, 3 + bob, p["flag_red"])
    # The cap's brim points where the golfer faces, so the direction reads in grayscale too.
    bx, by = cx - 1 + sx * 3, 4 + bob + max(sy, 0)
    for x in (bx, bx + 1):
        img.set(x, by, p["flag_red"])
    if not back:
        img.set(cx - 1 + sx, 6 + bob, p["ink"])  # an eye on the facing side
    # The club: slate_light, from the hands; a swing turns it through GOLFER_SWING_DEG.
    hx, hy = cx + side * 2, 14
    deg = GOLFER_SWING_DEG[n] if state == "swing" else 15
    a = math.radians(deg)
    for i in range(1, 10):
        x = hx + round(side * math.sin(a) * i)
        y = hy + round(math.cos(a) * i)
        img.set(x, y, p["slate_light"])
    draw_label(img, d, 0, 0, p["ink"])
    return img


def build_golfer(state: str, frames: int, p: dict[str, Color]) -> Image:
    img = sheet([golfer_frame(state, d, n, p) for d in GOLFER_DIRS for n in range(frames)])
    check_shirt_key(img, p)
    return img


# Shirts (E3-S28, art/specs/golfer.md "Shirts"): the sheets draw the shirt in GOLFER_SHIRT_KEY
# and GuestView's shader (art/sprites/golfer_shirt.gdshader) swaps it per group. The set lives
# in art/sprites/golfer.tres; this copy only draws the preview, and tests/test_guest_view.gd
# checks the preview against the .tres, so the two cannot drift apart unseen.
GOLFER_SHIRT_KEY = "chalk"
# Sheet rows the shirt (and so the key colour) may cover, inclusive.
GOLFER_SHIRT_ROWS = (9, 16)
# Rows above this one wear a yoke shirt's trim.
GOLFER_YOKE_ROW = 12
# (body, trim, pattern), in golfer.tres order. Patterns: plain, hoops (trim on odd rows), yoke.
GOLFER_SHIRTS = [
    ("chalk", "chalk", "plain"),
    ("flag_red", "chalk", "hoops"),
    ("water_dark", "chalk", "yoke"),
    ("sun_yellow", "sun_yellow", "plain"),
    ("earth", "earth", "plain"),
    ("slate_light", "water_dark", "yoke"),
    ("water_light", "water_dark", "hoops"),
]


def check_shirt_key(img: Image, p: dict[str, Color]) -> None:
    key = p[GOLFER_SHIRT_KEY]
    lo, hi = GOLFER_SHIRT_ROWS
    for y in range(img.height):
        if lo <= y <= hi:
            continue
        if any(img.get(x, y) == key for x in range(img.width)):
            raise SystemExit(f"golfer: the shirt key {GOLFER_SHIRT_KEY} is on row {y}, off the shirt")


def shirt_frame(base: Image, shirt: tuple[str, str, str], p: dict[str, Color]) -> Image:
    body, trim, pattern = shirt
    key = p[GOLFER_SHIRT_KEY]
    img = Image(base.width, base.height)
    for y in range(base.height):
        is_trim = (pattern == "hoops" and y % 2 == 1) or (pattern == "yoke" and y < GOLFER_YOKE_ROW)
        for x in range(base.width):
            c = base.get(x, y)
            img.set(x, y, (p[trim] if is_trim else p[body]) if c == key else c)
    return img


def build_golfer_shirts(p: dict[str, Color]) -> Image:
    """The preview: the idle s_0 frame in each shirt, in order (not loaded by the game)."""
    base = golfer_frame("idle", "s", 0, p)
    return sheet([shirt_frame(base, shirt, p) for shirt in GOLFER_SHIRTS])


# --- generic ---------------------------------------------------------------

def build_generic(thing: str, size: tuple[int, int], frames: int, color: str, p: dict[str, Color]) -> Image:
    out = []
    for i in range(frames):
        img = Image(*size)
        for y in range(size[1]):
            for x in range(size[0]):
                edge = x in (0, size[0] - 1) or y in (0, size[1] - 1)
                img.set(x, y, p["ink"] if edge else p[color])
        draw_label(img, str(i), 1, 1, p["chalk"])
        out.append(img)
    return sheet(out)


# --- main ------------------------------------------------------------------

def check_palette(img: Image, p: dict[str, Color]) -> None:
    allowed = set(p.values())
    bad = {c for c in img.px if c[3] and c not in allowed}
    if bad:
        raise SystemExit(f"colors outside art/palette.gpl: {sorted(bad)[:5]}")


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("thing")
    ap.add_argument("--size", help="frame size WxH, for things without a built-in generator")
    ap.add_argument("--frames", type=int, default=1)
    ap.add_argument("--folder", default="sprites", help="art/<folder>/ for generic things")
    ap.add_argument("--color", default="slate", help="palette color name for generic things")
    args = ap.parse_args(argv)

    p = load_palette()
    jobs: list[tuple[Path, Image]] = []
    if args.thing in ("surfaces", "all"):
        jobs.append((ROOT / "art/tiles/surfaces_placeholder.png", build_surfaces(p)))
    if args.thing in ("risers", "all"):
        jobs.append((ROOT / "art/tiles/risers_placeholder.png", build_risers(p)))
    if args.thing in ("edges", "all"):
        jobs.append((ROOT / "art/tiles/edges_placeholder.png", build_edges(p)))
    if args.thing in ("land", "all"):
        jobs.append((ROOT / "art/tiles/land_placeholder.png", build_land(p)))
    if args.thing in ("golfer", "all"):
        for state, frames in GOLFER_STATES:
            jobs.append((ROOT / f"art/sprites/golfer_{state}_placeholder.png", build_golfer(state, frames, p)))
        jobs.append((ROOT / "art/sprites/golfer_shirts_placeholder.png", build_golfer_shirts(p)))
    if not jobs:
        if not args.size:
            ap.error(f"no built-in generator for {args.thing!r}; pass --size WxH and --frames N")
        if not args.folder.isidentifier():
            ap.error("--folder is one folder name under art/, such as sprites or ui")
        if args.color not in p:
            ap.error(f"{args.color!r} is not in art/palette.gpl")
        w, h = (int(v) for v in args.size.lower().split("x"))
        jobs.append((ROOT / "art" / args.folder / f"{args.thing}_placeholder.png",
                     build_generic(args.thing, (w, h), args.frames, args.color, p)))

    for path, img in jobs:
        check_palette(img, p)
        img.save_png(path)
        print(f"{path.relative_to(ROOT)} {img.width}x{img.height}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
