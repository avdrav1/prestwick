#!/usr/bin/env python3
"""Generate placeholder art for Prestwick from art/palette.gpl. Stdlib only.

Usage:
  scripts/placeholder.py surfaces            -> art/tiles/surfaces_placeholder.png
  scripts/placeholder.py risers              -> art/tiles/risers_placeholder.png
  scripts/placeholder.py all                 -> both of the above
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
    """
    if in_diamond(x, y, -RISER_PX):
        return False
    return any(in_diamond(x, y, -s) for s in range(RISER_PX + 1))


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
