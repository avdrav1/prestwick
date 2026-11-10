#!/usr/bin/env python3
"""Generate placeholder art for Prestwick from art/palette.gpl. Stdlib only.

Usage:
  scripts/placeholder.py <thing> --size WxH --frames N [--folder sprites] [--color name]
                                             -> art/<folder>/<thing>_placeholder.png

Sheets follow the art-spec constants: PNG, no padding, 1 px transparent gutter
between frames, one row. Every pixel is a palette color or fully transparent.
Placeholders are never final; the spec in art/specs/ is the handoff.

The terrain is final art since E5-S2 (D62): scripts/art_terrain.py writes the surface and land
sheets; the surface, riser and edge cue placeholders went with it. Since E5-S3 the sprites are final
too (scripts/art_sprites.py writes them, reusing the golfer and clubhouse geometry kept here), so
this script only makes a generic placeholder for a new thing until its generator exists.
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


# --- clubhouse (E5-S10, art/specs/clubhouse.md) -----------------------------

CLUB_W = 3 * TILE_W            # the 3x3 footprint's diamond is 192 px wide
CLUB_H = 138
CLUB_ANCHOR = (96, 88)         # the footprint centre on the ground
CLUB_WALL = 40                 # wall height, px (2.5 height steps)
CLUB_ROOF = 36                 # roof rise above the eaves, px
CLUB_INSET = 1.25              # the walls stand this many tiles from the centre
CLUB_EAVE = 1.4                # the roof's eaves
CLUB_FACINGS = [("+x", "PX"), ("+y", "PY"), ("-x", "MX"), ("-y", "MY")]


def club_pt(tx: float, ty: float, z: float) -> tuple[float, float]:
    ax, ay = CLUB_ANCHOR
    return (ax + (tx - ty) * TILE_W / 2, ay + (tx + ty) * TILE_H / 2 - z)


def fill_poly(img: Image, pts: list[tuple[float, float]], c: Color) -> None:
    ys = [p[1] for p in pts]
    for y in range(max(0, int(min(ys))), min(img.height, int(max(ys)) + 1)):
        cy = y + 0.5
        xs = []
        for i in range(len(pts)):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % len(pts)]
            if (y0 <= cy < y1) or (y1 <= cy < y0):
                xs.append(x0 + (cy - y0) * (x1 - x0) / (y1 - y0))
        xs.sort()
        for k in range(0, len(xs) - 1, 2):
            for x in range(int(xs[k] + 0.5), int(xs[k + 1] + 0.5)):
                img.set(x, y, c)


def line(img: Image, a: tuple[float, float], b: tuple[float, float], c: Color) -> None:
    n = int(max(abs(b[0] - a[0]), abs(b[1] - a[1]))) + 1
    for i in range(n + 1):
        t = i / n
        img.set(int(a[0] + (b[0] - a[0]) * t), int(a[1] + (b[1] - a[1]) * t), c)


def outline(img: Image, pts: list[tuple[float, float]], c: Color) -> None:
    for i in range(len(pts)):
        line(img, pts[i], pts[(i + 1) % len(pts)], c)


def club_wall_quad(face: str, a: float, b: float, z0: float, z1: float) -> list[tuple[float, float]]:
    """A rectangle on the +x (face "x") or +y ("y") wall, from a to b along it, z0 to z1 up."""
    w = CLUB_INSET
    if face == "x":
        return [club_pt(w, a, z0), club_pt(w, b, z0), club_pt(w, b, z1), club_pt(w, a, z1)]
    return [club_pt(a, w, z0), club_pt(b, w, z0), club_pt(b, w, z1), club_pt(a, w, z1)]


def clubhouse_frame(facing: str, label: str, p: dict[str, Color]) -> Image:
    img = Image(CLUB_W, CLUB_H)
    h = 1.5
    pad = [club_pt(-h, -h, 0), club_pt(h, -h, 0), club_pt(h, h, 0), club_pt(-h, h, 0)]
    fill_poly(img, pad, p["path"])                     # the paved footprint
    outline(img, pad, p["path_dark"])
    w = CLUB_INSET
    walls = {"y": club_wall_quad("y", -w, w, 0, CLUB_WALL), "x": club_wall_quad("x", w, -w, 0, CLUB_WALL)}
    fill_poly(img, walls["y"], p["sand_light"])        # lit wall, down-left on screen
    fill_poly(img, walls["x"], p["sand_dark"])         # shaded wall, down-right
    door_face = {"+x": "x", "+y": "y"}.get(facing)
    for face in ("x", "y"):
        for a in (-0.85, 0.45):                        # two windows a wall, the door's middle left clear
            win = club_wall_quad(face, a, a + 0.4, 16, 30)
            fill_poly(img, win, p["water_light"])
            outline(img, win, p["ink"])
        if face == door_face:
            door = club_wall_quad(face, -0.25, 0.25, 0, 26)
            fill_poly(img, door, p["earth_dark"])
            outline(img, door, p["ink"])
            step = [club_pt(1.5, -0.35, 0), club_pt(1.5, 0.35, 0), club_pt(w, 0.35, 0), club_pt(w, -0.35, 0)] \
                if face == "x" else [club_pt(-0.35, 1.5, 0), club_pt(0.35, 1.5, 0), club_pt(0.35, w, 0), club_pt(-0.35, w, 0)]
            fill_poly(img, step, p["chalk"])            # the doorstep
    for q in walls.values():
        outline(img, q, p["ink"])
    e, top = CLUB_EAVE, CLUB_WALL + CLUB_ROOF
    apex = club_pt(0, 0, top)
    c = {k: club_pt(*k, CLUB_WALL) for k in [(-e, -e), (e, -e), (e, e), (-e, e)]}
    roof = [  # back faces first
        ([c[(-e, -e)], c[(e, -e)], apex], p["earth"]),
        ([c[(-e, e)], c[(-e, -e)], apex], p["earth"]),
        ([c[(e, -e)], c[(e, e)], apex], p["earth_dark"]),
        ([c[(e, e)], c[(-e, e)], apex], p["flag_red"]),
    ]
    for tri, col in roof:
        fill_poly(img, tri, col)
    for tri, _ in roof:
        outline(img, tri, p["ink"])
    if door_face is None:
        # The door is on a wall facing away: a flag on the ridge on that side says where.
        fx, fy = (-1.2, 0.2) if facing == "-x" else (0.2, -1.2)
        base = club_pt(fx, fy, CLUB_WALL + 6)
        tip = (base[0], base[1] - 18)
        line(img, base, tip, p["chalk"])
        fill_poly(img, [tip, (tip[0] + 9, tip[1] + 3), (tip[0], tip[1] + 6)], p["sun_yellow"])
    draw_label(img, label, 1, 1, p["ink"])
    return img


def build_clubhouse(p: dict[str, Color]) -> Image:
    return sheet([clubhouse_frame(f, label, p) for f, label in CLUB_FACINGS])


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
