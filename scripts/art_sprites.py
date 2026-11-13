#!/usr/bin/env python3
"""Final sprite art for Prestwick (E5-S3, D62), drawn by rule from art/palette.gpl. Stdlib only;
rerun after any palette or rule change. Never edit the PNGs: change the rule here.

Usage:
  python3 scripts/art_sprites.py            -> every sheet below
  python3 scripts/art_sprites.py golfer     -> one of: golfer, trees, decor, ball, markers, clubhouse,
                                                bridge

Sheets (each spec in art/specs/ is the contract: frame size, order, anchor):
  golfer     art/sprites/golfer_{idle,walk,swing}.png and golfer_shirts.png (preview)
  trees      art/sprites/trees.png        3 x 64x96, anchor (32, 88)
  decor      art/sprites/decor.png        4 x 48x48, anchor (24, 40)
  ball       art/sprites/ball.png         4 x 8x8,  anchor (4, 7)
  markers    art/sprites/hole_markers.png tee_block 8x8, cup 12x6, pin_0..2 16x36
  clubhouse  art/sprites/clubhouse.png    4 x 192x138, anchor (96, 88)
  bridge     art/sprites/bridge.png       32 x 64x48, anchor (32, 28)

Every sheet is one row, no padding, a 1 px transparent gutter, palette colours only and fully
opaque or fully clear pixels (the art-spec constants).
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import placeholder as ph  # noqa: E402  (Image, palette, sheet, polygon helpers, golfer constants)

Image = ph.Image
Color = ph.Color
OUT = ph.ROOT / "art" / "sprites"


# --- shared drawing helpers ---------------------------------------------------------------------

def disc(img: Image, cx: float, cy: float, r: float, c: Color, sy: float = 1.0) -> None:
    for y in range(int(cy - r * sy) - 1, int(cy + r * sy) + 2):
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            dx = (x + 0.5 - cx) / r
            dy = (y + 0.5 - cy) / (r * sy)
            if dx * dx + dy * dy <= 1.0:
                img.set(x, y, c)


def rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> None:
    """Fills x0..x1, y0..y1 inclusive."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            img.set(x, y, c)


def outline_mask(img: Image, mask: set[tuple[int, int]], c: Color, sides: str = "nsew") -> None:
    """Ink every clear pixel 4-next to the mask, on the named sides of it (n: above, s: below...)."""
    steps = {"n": (0, -1), "s": (0, 1), "w": (-1, 0), "e": (1, 0)}
    for (x, y) in list(mask):
        for k in sides:
            dx, dy = steps[k]
            nx, ny = x + dx, y + dy
            if (nx, ny) not in mask and 0 <= nx < img.width and 0 <= ny < img.height \
                    and img.get(nx, ny)[3] == 0:
                img.set(nx, ny, c)


def opaque(img: Image) -> set[tuple[int, int]]:
    return {(x, y) for y in range(img.height) for x in range(img.width) if img.get(x, y)[3]}


def save(path: Path, img: Image, p: dict[str, Color]) -> None:
    ph.check_palette(img, p)
    img.save_png(path)
    print(f"{path.relative_to(ph.ROOT)} {img.width}x{img.height}")


# --- golfer (art/specs/golfer.md) ---------------------------------------------------------------

GW, GH = ph.GOLFER_W, ph.GOLFER_H
# E7-S3: the figure is drawn in one of five views facing right (or the camera, or away) and
# mirrored about the frame's middle (x -> 23 - x) for the views that face left. The body is 8 px
# across from the front and 8 px deep from the side, so the profile is no thinner than the front.
GOLFER_VIEW = {"s": ("front", 1), "se": ("front3q", 1), "sw": ("front3q", -1), "e": ("side", 1),
               "w": ("side", -1), "ne": ("back3q", 1), "nw": ("back3q", -1), "n": ("back", 1)}
BACK_VIEWS = ("back", "back3q")
# Head and cap, rows 2 to 8, x 7 to 16, facing right: R cap, S skin, H hair, K eye.
GOLFER_HEADS = {
    "front": ["...RRRR...",
              "..RRRRRR..",
              "..RRRRRR..",
              ".RRRRRRRR.",
              "..SKSSKS..",
              "..SSSSSS..",
              "...SSSS..."],
    "front3q": ["...RRRR...",
                "..RRRRRR..",
                "..RRRRRRR.",
                "..HRRRRRRR",
                "..HSSKSKS.",
                "..SSSSSSS.",
                "...SSSSS.."],
    "side": ["...RRRR...",
             "..RRRRRR..",
             "..RRRRRRRR",
             "..HHHSSS..",
             "..HHSSKSS.",
             "..HHSSSS..",
             "...SSSS..."],
    "back3q": ["...RRRR...",
               "..RRRRRR..",
               "..RRRRRRRR",
               "..HHHHHHS.",
               "..HHHHHSS.",
               "..HHHHHS..",
               "...HHHS..."],
    "back": ["...RRRR...",
             "..RRRRRR..",
             "..RRRRRR..",
             "..HHHHHH..",
             "..HHHHHH..",
             "..HHHHHH..",
             "...SSSS..."],
}
# Torso, rows 9 to 16, x 7 to 16: the shirt (the key colour), rounded shoulders, 8 px wide.
GOLFER_TORSO = ["..CCCCCC.."] + [".CCCCCCCC."] * 7
# Where the arms hang from, facing right (one arm seen from the side).
GOLFER_SHOULDERS = {"front": [(7, 10), (16, 10)], "front3q": [(7, 10), (16, 10)],
                    "side": [(12, 10)], "back3q": [(7, 10), (16, 10)], "back": [(7, 10), (16, 10)]}
# Legs per view and frame, facing right: (hip x, foot x, foot lift), each leg 3 px wide.
GOLFER_STAND = {"front": [(8, 8, 0), (13, 13, 0)], "front3q": [(9, 9, 0), (12, 12, 0)],
                "side": [(10, 10, 0), (11, 11, 0)], "back3q": [(9, 9, 0), (12, 12, 0)],
                "back": [(8, 8, 0), (13, 13, 0)]}
# The walk (contact, pass, contact, pass): a stride along the facing; seen from the front or
# back the far foot lifts. The body dips a pixel on the contact frames.
GOLFER_STRIDE = {
    "front": [[(8, 8, 1), (13, 13, 0)], [(8, 8, 2), (13, 13, 0)],
              [(8, 8, 0), (13, 13, 1)], [(8, 8, 0), (13, 13, 2)]],
    "front3q": [[(9, 7, 1), (12, 14, 0)], [(10, 10, 2), (12, 12, 0)],
                [(11, 14, 0), (9, 7, 1)], [(10, 10, 0), (12, 12, 2)]],
    "side": [[(10, 7, 1), (11, 15, 0)], [(10, 9, 2), (11, 12, 0)],
             [(10, 14, 0), (11, 8, 1)], [(10, 12, 0), (11, 9, 2)]],
    "back3q": [[(9, 7, 0), (12, 14, 1)], [(10, 10, 0), (12, 12, 2)],
               [(11, 14, 1), (9, 7, 0)], [(10, 10, 2), (12, 12, 0)]],
    "back": [[(8, 8, 0), (13, 13, 1)], [(8, 8, 0), (13, 13, 2)],
             [(8, 8, 1), (13, 13, 0)], [(8, 8, 2), (13, 13, 0)]],
}
# The arms swing against the legs: each arm's hand x offset per walk frame.
GOLFER_ARM_SWING = [(1, -1), (0, 0), (-1, 1), (0, 0)]
# The side view's arm: its hand per walk frame (back, by the hip, forward, by the hip; the idle
# hand is the hip one), facing right.
GOLFER_SIDE_HANDS = [(10, 15), (13, 16), (16, 14), (13, 16)]
# The swing, for a swing through to +x: (hands, club degrees from straight down toward +x,
# negative back, club length, head dip, upper-body lean, legs). Frames: address, takeaway, top,
# down, impact, finish; the ball leaves on frame 4 (golfer.tres swing_impact_frame).
GOLFER_SWING = [
    ((12, 16), 4, 7, 1, 0, [(8, 7, 0), (13, 14, 0)]),
    ((8, 14), -80, 8, 1, 0, [(8, 7, 0), (13, 14, 0)]),
    ((6, 7), -160, 8, 0, -1, [(8, 7, 0), (13, 13, 0)]),
    ((9, 12), -55, 8, 1, 0, [(8, 7, 0), (13, 14, 0)]),
    ((13, 16), 8, 7, 1, 0, [(8, 8, 1), (13, 14, 0)]),
    ((17, 8), 172, 8, 0, 1, [(9, 10, 1), (13, 14, 0)]),
]
GOLFER_SWING_SIDE = [
    ((15, 16), 28, 7, 1, 1, [(9, 9, 0), (11, 12, 0)]),
    ((10, 14), -80, 8, 1, 0, [(9, 9, 0), (11, 12, 0)]),
    ((8, 7), -160, 8, 0, -1, [(9, 9, 0), (11, 12, 0)]),
    ((11, 12), -55, 8, 1, 0, [(9, 9, 0), (11, 12, 0)]),
    ((15, 16), 30, 7, 1, 1, [(9, 9, 1), (11, 12, 0)]),
    ((17, 8), 172, 8, 0, 1, [(10, 11, 1), (11, 12, 0)]),
]


def golfer_swing_body(d: str) -> tuple[str, int]:
    """A golfer stands side-on to the shot, the target on their left (right-handed): the body
    faces the swing direction turned 90 degrees clockwise on screen. Returns that facing and
    the side the club goes through to in the drawn, unmirrored frame (+1 right, -1 left)."""
    dirs = ph.GOLFER_DIRS
    b = dirs[(dirs.index(d) + 2) % 8]
    view, fb = GOLFER_VIEW[b]
    return b, (1 if view == "side" else ph.GOLFER_DIR_STEP[d][0] * fb)


def _line(x0: int, y0: int, x1: int, y1: int) -> list[tuple[int, int]]:
    steps = max(abs(x1 - x0), abs(y1 - y0), 1)
    return [(round(x0 + (x1 - x0) * k / steps), round(y0 + (y1 - y0) * k / steps))
            for k in range(steps + 1)]


def golfer_frame(state: str, d: str, n: int, p: dict[str, Color]) -> Image:
    swing = state == "swing"
    r = 1
    if swing:
        d, r = golfer_swing_body(d)
    view, fb = GOLFER_VIEW[d]
    back = view in BACK_VIEWS
    img = Image(GW, GH)
    body: set[tuple[int, int]] = set()
    head: set[tuple[int, int]] = set()
    skin, shirt, pants, shoe = p["skin"], p["chalk"], p["slate_dark"], p["earth_dark"]
    key = {"R": p["flag_red"], "S": skin, "H": p["earth_dark"], "K": p["ink"]}

    def put(x: int, y: int, c: Color, into: set[tuple[int, int]] | None = None) -> None:
        x = GW - 1 - x if fb < 0 else x
        if 0 <= x < GW and 0 <= y < GH:
            img.set(x, y, c)
            body.add((x, y))
            if into is not None:
                into.add((x, y))

    # The pose. A swing to the left mirrors its hands, club, lean and legs.
    if swing:
        hands, deg, length, dip, lean, legs = (GOLFER_SWING_SIDE if view == "side" else GOLFER_SWING)[n]
        if r < 0:
            hands = (GW - 1 - hands[0], hands[1])
            deg, lean = -deg, -lean
            legs = [(GW - 3 - h, GW - 3 - f, lift) for (h, f, lift) in legs]
        top = 0
    else:
        dip, lean, deg, length = 0, 0, 10, 8
        if state == "walk":
            legs, top = GOLFER_STRIDE[view][n], (1 if n in (0, 2) else 0)
        else:
            legs, top = GOLFER_STAND[view], (1 if n == 1 else 0)
        swing_x = GOLFER_ARM_SWING[n] if state == "walk" else (0, 0)
    # Legs: 3 px trousers from the hips to each foot, the shoe below (a lifted foot higher),
    # its toe toward the facing in the side and three-quarter views.
    hip_y = 17 + top
    for x in range(min(h for h, _, _ in legs), max(h for h, _, _ in legs) + 3):
        put(x, hip_y, pants)
    toe = 1 if view in ("side", "front3q", "back3q") else 0
    for (hx, fx, lift) in legs:
        foot_y = 22 - lift
        for y in range(hip_y + 1, foot_y):
            x = round(hx + (fx - hx) * (y - hip_y) / max(foot_y - hip_y, 1))
            for k in range(3):
                put(x + k, y, pants)
        for k in range(3 + toe):
            put(fx + k, foot_y, shoe)
    shoulders = [(x + lean, y + top) for (x, y) in GOLFER_SHOULDERS[view]]

    def arm(sh: tuple[int, int], hand: tuple[int, int]) -> None:
        for i, (x, y) in enumerate(_line(sh[0], sh[1], hand[0], hand[1])):
            put(x, y, shirt if i < 2 and 9 <= y <= 16 else skin)

    # Hanging arms (idle, walk); the side view's one arm swings fore and aft over the shirt.
    if not swing:
        if view == "side":
            hx, hy = GOLFER_SIDE_HANDS[n] if state == "walk" else GOLFER_SIDE_HANDS[1]
            hands = (hx, hy + top)
        else:
            hands = (16, 15 + top)
    if swing and back:
        for sh in shoulders:
            arm(sh, hands)
    # Torso: the shirt on rows 9 to 16 only (the key never leaves them).
    for i, row in enumerate(GOLFER_TORSO):
        y = 9 + i + top
        if y > 16:
            break
        for j, ch in enumerate(row):
            if ch == "C":
                put(7 + j + (lean if i < 4 else 0), y, shirt)
    if not swing:
        if view == "side":
            arm(shoulders[0], hands)
            # An ink edge behind the forearm parts it from the shirt.
            for i, (x, y) in enumerate(_line(*shoulders[0], *hands)):
                bx = x - 1 if fb > 0 else GW - x
                if i >= 2 and img.get(bx, y) == shirt:
                    img.set(bx, y, p["ink"])
        else:
            for k, sh in enumerate(shoulders):
                frontal = view in ("front", "back")
                dx = 0 if frontal else swing_x[k]
                dy = -1 if (frontal and swing_x[k] > 0) else 0
                arm(sh, (sh[0] + dx, 15 + top + dy))
            hands = (16 + (0 if view in ("front", "back") else swing_x[1]), 15 + top)
    # Head and cap.
    for i, row in enumerate(GOLFER_HEADS[view]):
        for j, ch in enumerate(row):
            if ch in key:
                put(7 + j + lean, 2 + i + top + dip, key[ch], head)
    if swing and not back:
        for sh in shoulders:
            arm(sh, hands)
    outline_mask(img, body, p["ink"])
    # The club: a slate_light shaft from the hands and an ink head. It passes behind the head,
    # and behind the body when seen from behind or carried.
    hx = GW - 1 - hands[0] if fb < 0 else hands[0]
    a = math.radians(deg * fb)
    end = None
    for i in range(1, length + 1):
        x = hx + round(math.sin(a) * i)
        y = hands[1] + round(math.cos(a) * i)
        if not (0 <= x < GW and 0 <= y < GH):
            break
        if (x, y) in head or ((back or not swing) and (x, y) in body):
            continue
        img.set(x, y, p["slate_light"])
        end = (x, y)
    if end is not None:
        img.set(end[0], end[1], p["ink"])
    return img


def build_golfer(p: dict[str, Color]) -> None:
    for state, frames in ph.GOLFER_STATES:
        img = ph.sheet([golfer_frame(state, d, n, p) for d in ph.GOLFER_DIRS for n in range(frames)])
        ph.check_shirt_key(img, p)
        save(OUT / f"golfer_{state}.png", img, p)
    base = golfer_frame("idle", "s", 0, p)
    save(OUT / "golfer_shirts.png", ph.sheet([ph.shirt_frame(base, s, p) for s in ph.GOLFER_SHIRTS]), p)


# --- trees (art/specs/trees.md) -----------------------------------------------------------------

TREE_W, TREE_H = 64, 96
TREE_ANCHOR = (32, 88)
# Crown lobes per variant: (x, y, r) in frame px. The top lobe reaches y 8 (80 px above the foot).
TREES = {
    "a": [(32, 30, 16), (21, 44, 13), (43, 44, 13), (32, 52, 14)],
    "b": [(30, 28, 15), (40, 34, 14), (22, 46, 12), (42, 50, 13), (31, 54, 12)],
    "c": [(33, 31, 17), (20, 42, 12), (46, 42, 11), (27, 54, 12), (40, 55, 12)],
}


def tree_frame(lobes: list[tuple[int, int, int]], p: dict[str, Color]) -> Image:
    img = Image(TREE_W, TREE_H)
    ax, ay = TREE_ANCHOR
    # Trunk: earth_dark, lit on its left in earth, a little flare at the foot.
    for y in range(56, ay + 1):
        w = 2 if y < ay - 3 else 3
        for x in range(ax - w, ax + w):
            img.set(x, y, p["earth"] if x < ax - w + 2 else p["earth_dark"])
    # Crown: each lobe dark, its upper-left lit, and a few lit leaf clumps.
    lx, ly = -0.6, -0.8   # toward the light (terrain_tuning.tres light_dir, up-left)
    crown: set[tuple[int, int]] = set()
    for (cx, cy, r) in lobes:
        for y in range(cy - r - 1, cy + r + 2):
            for x in range(cx - r - 1, cx + r + 2):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                if dx * dx + dy * dy <= r * r:
                    crown.add((x, y))
    top = min(y for _, y in crown)
    shift = 8 - top
    crown = {(x, y + shift) for x, y in crown}
    lobes = [(cx, cy + shift, r) for cx, cy, r in lobes]
    for (x, y) in crown:
        best = -9.0
        for (cx, cy, r) in lobes:
            dx, dy = (x + 0.5 - cx) / r, (y + 0.5 - cy) / r
            if dx * dx + dy * dy <= 1:
                best = max(best, dx * lx + dy * ly)
        # Leaf clumps: a lattice of small blobs so the crown is not flat.
        h = ph_hash(x // 3, y // 3)
        if best > 0.45 or (best > 0.15 and h < 0.35):
            c = p["rough"]
        elif best > -0.2 or h < 0.2:
            c = p["tree"]
        else:
            c = p["tree_dark"]
        img.set(x, y, c)
    # Ink only on the crown's lower right (spec), and under its lower edge.
    outline_mask(img, crown, p["ink"], "se")
    return img


def ph_hash(a: int, b: int) -> float:
    h = (a * 374761393 + b * 668265263) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65536.0


def build_trees(p: dict[str, Color]) -> None:
    save(OUT / "trees.png", ph.sheet([tree_frame(TREES[k], p) for k in ("a", "b", "c")]), p)


# --- decor (art/specs/decor.md) -----------------------------------------------------------------

DW, DH = 48, 48
DA = (24, 40)


def iso(dx: float, dy: float, z: float) -> tuple[float, float]:
    """Frame point for tile offset (dx, dy) from the anchor tile centre, z px up."""
    return (DA[0] + (dx - dy) * 32, DA[1] + (dx + dy) * 16 - z)


def bench(axis: str, p: dict[str, Color]) -> Image:
    img = Image(DW, DH)
    L = 0.32  # half length, tiles
    def at(t: float, s: float, z: float) -> tuple[float, float]:
        return iso(t, s, z) if axis == "x" else iso(s, t, z)
    # Legs (slate), seat (earth_light top, earth front), back rest (earth) behind.
    for t in (-L + 0.04, L - 0.04):
        for s in (-0.06, 0.06):
            a, b = at(t, s, 0), at(t, s, 6)
            ph.line(img, a, b, p["slate"])
    seat = [at(-L, -0.08, 7), at(L, -0.08, 7), at(L, 0.08, 7), at(-L, 0.08, 7)]
    ph.fill_poly(img, seat, p["earth_light"])
    front = [at(-L, 0.08, 7), at(L, 0.08, 7), at(L, 0.08, 5), at(-L, 0.08, 5)]
    ph.fill_poly(img, front, p["earth"])
    back = [at(-L, -0.1, 9), at(L, -0.1, 9), at(L, -0.1, 15), at(-L, -0.1, 15)]
    ph.fill_poly(img, back, p["earth"])
    ph.line(img, at(-L, -0.1, 12), at(L, -0.1, 12), p["earth_dark"])
    for q in (seat, front, back):
        ph.outline(img, q, p["ink"])
    return img


def flag(p: dict[str, Color]) -> Image:
    img = Image(DW, DH)
    x0, y0 = DA
    rect(img, x0 - 1, y0 - 2, x0 + 1, y0, p["slate_dark"])          # the foot
    rect(img, x0, y0 - 36, x0, y0 - 2, p["slate"])                    # the pole
    rect(img, x0 + 1, y0 - 36, x0 + 1, y0 - 2, p["slate_dark"])
    img.set(x0, y0 - 37, p["sun_yellow"])                             # the finial
    cloth = [(x0 + 2, y0 - 35), (x0 + 15, y0 - 33), (x0 + 15, y0 - 22), (x0 + 2, y0 - 24)]
    ph.fill_poly(img, cloth, p["sun_yellow"])
    ph.line(img, (x0 + 4, y0 - 29), (x0 + 13, y0 - 27), p["earth_light"])   # a fold
    ph.outline(img, cloth, p["ink"])
    return img


def sign(p: dict[str, Color]) -> Image:
    img = Image(DW, DH)
    x0, y0 = DA
    for px in (x0 - 9, x0 + 8):
        rect(img, px, y0 - 18, px + 1, y0, p["earth_dark"])
    board = (x0 - 13, y0 - 30, x0 + 13, y0 - 16)
    rect(img, *board, p["ink"])
    rect(img, board[0] + 1, board[1] + 1, board[2] - 1, board[3] - 1, p["chalk"])
    # A hole-sign's lines of text, in slate: a short title and two lines.
    rect(img, x0 - 9, y0 - 27, x0 + 2, y0 - 26, p["slate"])
    rect(img, x0 - 9, y0 - 23, x0 + 8, y0 - 23, p["slate_light"])
    rect(img, x0 - 9, y0 - 20, x0 + 5, y0 - 20, p["slate_light"])
    return img


def build_decor(p: dict[str, Color]) -> None:
    save(OUT / "decor.png", ph.sheet([bench("x", p), bench("y", p), flag(p), sign(p)]), p)


# --- ball (art/specs/ball.md) -------------------------------------------------------------------

BALL_ROWS = ["..####..", ".#BBBB#.", "#BBBBBB#", "#BBBBBB#", "#BBBBBB#", "#BBBBBB#", ".#BBBB#.", "..####.."]


def ball_frame(fill: str, shade: str, dot: str | None, spin: bool, p: dict[str, Color]) -> Image:
    img = Image(8, 8)
    for y, row in enumerate(BALL_ROWS):
        for x, ch in enumerate(row):
            if ch == "#":
                img.set(x, y, p["ink"])
            elif ch == "B":
                img.set(x, y, p[fill])
    # The shade sits low right, moved round in the spin frame so a flight flickers.
    for (x, y) in ([(5, 5), (4, 6), (6, 4)] if not spin else [(2, 5), (3, 6), (1, 4)]):
        img.set(x, y, p[shade])
    if dot:
        img.set(3, 3, p[dot])
        img.set(4, 3, p[dot])
    else:
        img.set(2, 2, p["chalk"])  # the player's highlight stays chalk
    return img


def build_ball(p: dict[str, Color]) -> None:
    frames = [
        ball_frame("chalk", "slate_light", None, False, p),
        ball_frame("chalk", "slate_light", None, True, p),
        ball_frame("slate_light", "slate", "chalk", False, p),
        ball_frame("slate_light", "slate", "chalk", True, p),
    ]
    save(OUT / "ball.png", ph.sheet(frames), p)


# --- hole markers (art/specs/hole_markers.md) ---------------------------------------------------

def tee_block(p: dict[str, Color]) -> Image:
    img = Image(8, 8)
    disc(img, 4, 3.5, 3.5, p["ink"])
    disc(img, 4, 3.5, 2.5, p["sun_yellow"])
    img.set(3, 2, p["chalk"])
    img.set(5, 5, p["earth_light"])
    return img


def cup(p: dict[str, Color]) -> Image:
    img = Image(12, 6)
    disc(img, 6, 3, 6, p["chalk"], 0.5)     # the cut lip
    disc(img, 6, 3, 5, p["ink"], 0.5)
    rect(img, 3, 3, 8, 4, p["slate_dark"])  # the far wall in shadow, the hole ink above it
    disc(img, 6, 2.5, 4, p["ink"], 0.4)
    return img


def pin(wave: int, p: dict[str, Color]) -> Image:
    img = Image(16, 36)
    # Pole: 30 px from the cup (2, 34) up, chalk with an ink edge.
    for y in range(4, 35):
        img.set(1, y, p["ink"])
        img.set(2, y, p["chalk"])
        img.set(3, y, p["ink"])
    img.set(2, 3, p["ink"])
    # Pennant: flag_red, its tail dipping with the wave.
    tip_dy = [0, 2, 3][wave]
    mid_dy = [0, -1, 1][wave]
    pts = [(4, 4), (9, 5 + mid_dy), (15, 7 + tip_dy), (9, 9 + mid_dy), (4, 12)]
    ph.fill_poly(img, pts, p["flag_red"])
    ph.outline(img, pts, p["ink"])
    for y in range(4, 13):
        img.set(3, y, p["ink"])
    return img


def build_markers(p: dict[str, Color]) -> None:
    frames = [tee_block(p), cup(p), pin(0, p), pin(1, p), pin(2, p)]
    save(OUT / "hole_markers.png", ph.sheet(frames), p)


# --- clubhouse (art/specs/clubhouse.md) ---------------------------------------------------------

def clubhouse_frame(facing: str, p: dict[str, Color]) -> Image:
    club_pt, fill_poly, line, outline = ph.club_pt, ph.fill_poly, ph.line, ph.outline
    img = Image(ph.CLUB_W, ph.CLUB_H)
    h = 1.5
    pad = [club_pt(-h, -h, 0), club_pt(h, -h, 0), club_pt(h, h, 0), club_pt(-h, h, 0)]
    fill_poly(img, pad, p["path"])
    # Paving joints along both axes.
    for k in (-0.75, 0.0, 0.75):
        line(img, club_pt(k, -h, 0), club_pt(k, h, 0), p["path_dark"])
        line(img, club_pt(-h, k, 0), club_pt(h, k, 0), p["path_dark"])
    outline(img, pad, p["path_dark"])
    w = ph.CLUB_INSET
    wall_h = ph.CLUB_WALL
    walls = {"y": ph.club_wall_quad("y", -w, w, 0, wall_h), "x": ph.club_wall_quad("x", w, -w, 0, wall_h)}
    fill_poly(img, walls["y"], p["sand_light"])
    fill_poly(img, walls["x"], p["sand"])
    # Siding: a line every 6 px up each wall, and a stone plinth.
    for face, col in (("y", p["sand"]), ("x", p["sand_dark"])):
        for z in range(10, wall_h, 6):
            q = ph.club_wall_quad(face, -w, w, z, z)
            line(img, q[0], q[1], col)
        fill_poly(img, ph.club_wall_quad(face, -w, w, 0, 5) if face == "y" else ph.club_wall_quad(face, w, -w, 0, 5),
                  p["slate_light"] if face == "y" else p["slate"])
    door_face = {"+x": "x", "+y": "y"}.get(facing)
    for face in ("x", "y"):
        for a in (-0.95, 0.5):
            win = ph.club_wall_quad(face, a, a + 0.45, 15, 30)
            fill_poly(img, win, p["water_light"])
            mid = ph.club_wall_quad(face, a + 0.2, a + 0.25, 15, 30)
            fill_poly(img, mid, p["chalk"])                    # the mullion
            outline(img, win, p["ink"])
            sill = ph.club_wall_quad(face, a - 0.05, a + 0.5, 13, 15)
            fill_poly(img, sill, p["chalk"])
        if face == door_face:
            door = ph.club_wall_quad(face, -0.25, 0.25, 0, 27)
            fill_poly(img, door, p["earth_dark"])
            outline(img, door, p["ink"])
            knob = ph.club_wall_quad(face, 0.12, 0.16, 12, 14)
            fill_poly(img, knob, p["sun_yellow"])
            step = [club_pt(1.5, -0.35, 0), club_pt(1.5, 0.35, 0), club_pt(w, 0.35, 0), club_pt(w, -0.35, 0)] \
                if face == "x" else [club_pt(-0.35, 1.5, 0), club_pt(0.35, 1.5, 0), club_pt(0.35, w, 0), club_pt(-0.35, w, 0)]
            fill_poly(img, step, p["chalk"])
            outline(img, step, p["slate_light"])
    for q in walls.values():
        outline(img, q, p["ink"])
    e, top = ph.CLUB_EAVE, wall_h + ph.CLUB_ROOF
    apex = club_pt(0, 0, top)
    c = {k: club_pt(*k, wall_h) for k in [(-e, -e), (e, -e), (e, e), (-e, e)]}
    roof = [
        ([c[(-e, -e)], c[(e, -e)], apex], p["earth"]),
        ([c[(-e, e)], c[(-e, -e)], apex], p["earth"]),
        ([c[(e, -e)], c[(e, e)], apex], p["earth_dark"]),
        ([c[(e, e)], c[(-e, e)], apex], p["flag_red"]),
    ]
    for tri, col in roof:
        fill_poly(img, tri, col)
    # Tile courses across the two near roof faces: lines parallel to the eaves.
    for f in (0.25, 0.5, 0.75):
        for (a, b), col in (((( e, -e), (e, e)), p["earth_dark"]), (((e, e), (-e, e)), p["earth_dark"])):
            pa = club_pt(a[0] * (1 - f), a[1] * (1 - f), wall_h + ph.CLUB_ROOF * f)
            pb = club_pt(b[0] * (1 - f), b[1] * (1 - f), wall_h + ph.CLUB_ROOF * f)
            line(img, pa, pb, col if (a, b) != ((e, e), (-e, e)) else p["earth"])
    for tri, _ in roof:
        outline(img, tri, p["ink"])
    # Chimney on the back right face.
    ch = [club_pt(0.3, -0.7, top - 22), club_pt(0.6, -0.7, top - 22), club_pt(0.6, -0.7, top - 6), club_pt(0.3, -0.7, top - 6)]
    fill_poly(img, ch, p["slate"])
    outline(img, ch, p["ink"])
    if door_face is None:
        fx, fy = (-1.2, 0.2) if facing == "-x" else (0.2, -1.2)
        base = club_pt(fx, fy, wall_h + 6)
        tip = (base[0], base[1] - 18)
        line(img, base, tip, p["chalk"])
        fill_poly(img, [tip, (tip[0] + 9, tip[1] + 3), (tip[0], tip[1] + 6)], p["sun_yellow"])
        outline(img, [tip, (tip[0] + 9, tip[1] + 3), (tip[0], tip[1] + 6)], p["ink"])
    return img


def build_clubhouse(p: dict[str, Color]) -> None:
    save(OUT / "clubhouse.png", ph.sheet([clubhouse_frame(f, p) for f, _ in ph.CLUB_FACINGS]), p)


# --- bridge (art/specs/bridge.md) ---------------------------------------------------------------

BW, BH = 64, 48
BA = (32, 28)
# The deck stands this many px over the water's surface; its rails this many px over the deck.
BRIDGE_DECK_Z = 3
BRIDGE_RAIL_Z = 7
# A railed side's deck edge, tiles from the centre (an open side runs to the tile's edge, 0.5).
BRIDGE_INSET = 0.36
# Sides by bit, as course/bridge_view.gd names them: the neighbour at +x, -x, +y, -y.
BRIDGE_SIDES = [(1, 0), (-1, 0), (0, 1), (0, -1)]


def biso(dx: float, dy: float, z: float) -> tuple[float, float]:
    return (BA[0] + (dx - dy) * 32, BA[1] + (dx + dy) * 16 - z)


def bridge_frame(axis: str, rails: int, p: dict[str, Color]) -> Image:
    """A footbridge deck over one water tile: planks across `axis` ("x": the deck runs along x),
    a rail on each side whose bit is set in `rails` (that neighbour is open water)."""
    img = Image(BW, BH)
    lo_x = -BRIDGE_INSET if rails & 2 else -0.5
    hi_x = BRIDGE_INSET if rails & 1 else 0.5
    lo_y = -BRIDGE_INSET if rails & 8 else -0.5
    hi_y = BRIDGE_INSET if rails & 4 else 0.5
    z = BRIDGE_DECK_Z
    deck = [biso(lo_x, lo_y, z), biso(hi_x, lo_y, z), biso(hi_x, hi_y, z), biso(lo_x, hi_y, z)]
    # The deck's front faces (its +x and +y edges, toward the camera) in earth, the top earth_light.
    ph.fill_poly(img, [biso(hi_x, lo_y, z), biso(hi_x, hi_y, z), biso(hi_x, hi_y, 0), biso(hi_x, lo_y, 0)],
                 p["earth"])
    ph.fill_poly(img, [biso(lo_x, hi_y, z), biso(hi_x, hi_y, z), biso(hi_x, hi_y, 0), biso(lo_x, hi_y, 0)],
                 p["earth_dark"])
    ph.fill_poly(img, deck, p["earth_light"])
    # Planks: seams across the deck every eighth of a tile.
    k = -0.5 + 0.125
    while k < 0.5 - 1e-6:
        if axis == "x" and lo_x < k < hi_x:
            ph.line(img, biso(k, lo_y, z), biso(k, hi_y, z), p["earth"])
        if axis == "y" and lo_y < k < hi_y:
            ph.line(img, biso(lo_x, k, z), biso(hi_x, k, z), p["earth"])
        k += 0.125
    ph.outline(img, deck, p["ink"])
    # Rails: a top bar on posts along each railed side.
    for bit, (sx, sy) in enumerate(BRIDGE_SIDES):
        if not rails & (1 << bit):
            continue
        if sx != 0:
            x = hi_x if sx > 0 else lo_x
            a, b = (x, lo_y), (x, hi_y)
        else:
            y = hi_y if sy > 0 else lo_y
            a, b = (lo_x, y), (hi_x, y)
        for t in (0.0, 0.5, 1.0):
            px, py = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
            ph.line(img, biso(px, py, z), biso(px, py, z + BRIDGE_RAIL_Z), p["earth_dark"])
        ph.line(img, biso(a[0], a[1], z + BRIDGE_RAIL_Z), biso(b[0], b[1], z + BRIDGE_RAIL_Z), p["earth"])
        ph.line(img, biso(a[0], a[1], z + BRIDGE_RAIL_Z + 1), biso(b[0], b[1], z + BRIDGE_RAIL_Z + 1), p["ink"])
    return img


def build_bridge(p: dict[str, Color]) -> None:
    frames = [bridge_frame(axis, rails, p) for axis in ("x", "y") for rails in range(16)]
    save(OUT / "bridge.png", ph.sheet(frames), p)


BUILDERS = {"golfer": build_golfer, "trees": build_trees, "decor": build_decor, "ball": build_ball,
            "markers": build_markers, "clubhouse": build_clubhouse, "bridge": build_bridge}


def main(argv: list[str]) -> int:
    p = ph.load_palette()
    names = argv or list(BUILDERS)
    for n in names:
        if n not in BUILDERS:
            print(f"unknown sheet {n!r}; one of {', '.join(BUILDERS)}", file=sys.stderr)
            return 2
        BUILDERS[n](p)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
