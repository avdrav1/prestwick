#!/usr/bin/env python3
"""Final sprite art for Prestwick (E5-S3, D62), drawn by rule from art/palette.gpl. Stdlib only;
rerun after any palette or rule change. Never edit the PNGs: change the rule here.

Usage:
  python3 scripts/art_sprites.py            -> every sheet below
  python3 scripts/art_sprites.py golfer     -> one of: golfer, trees, decor, ball, markers, clubhouse

Sheets (each spec in art/specs/ is the contract: frame size, order, anchor):
  golfer     art/sprites/golfer_{idle,walk,swing}.png and golfer_shirts.png (preview)
  trees      art/sprites/trees.png        3 x 64x96, anchor (32, 88)
  decor      art/sprites/decor.png        4 x 48x48, anchor (24, 40)
  ball       art/sprites/ball.png         4 x 8x8,  anchor (4, 7)
  markers    art/sprites/hole_markers.png tee_block 8x8, cup 12x6, pin_0..2 16x36
  clubhouse  art/sprites/clubhouse.png    4 x 192x138, anchor (96, 88)

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
CX = ph.GOLFER_ANCHOR[0]
# Club angle per swing frame, degrees from straight down, toward the facing side: address,
# takeaway, top, down, impact, finish (as the placeholder; the ball leaves on frame 4).
SWING_DEG = [12, -55, -150, -70, 12, 150]
# Hands per swing frame, relative to (CX, 14), toward the facing side (+x) and up (-y).
SWING_HANDS = [(1, 0), (-2, -2), (-2, -6), (-1, -2), (1, 0), (2, -6)]


def golfer_frame(state: str, d: str, n: int, p: dict[str, Color]) -> Image:
    img = Image(GW, GH)
    sx, sy = ph.GOLFER_DIR_STEP[d]
    back = sy < 0
    profile = sy == 0
    face = sx if sx else 1           # the side the club and brim go to
    bob = 1 if state == "idle" and n == 1 else 0
    walk = state == "walk"
    lift = 1 if walk and n in (1, 3) else 0       # the passing frames rise a pixel
    top = bob - lift
    skin, cap, hair = p["skin"], p["flag_red"], p["earth_dark"]
    shirt, pants, shoe = p["chalk"], p["slate_dark"], p["earth_dark"]
    body: set[tuple[int, int]] = set()

    def put(x: int, y: int, c: Color) -> None:
        img.set(x, y, c)
        body.add((x, y))

    # Legs and shoes: two 2 px legs from row 17; a stride spreads them along the facing.
    stride = [2, 0, -2, 0][n] if walk else 0
    half = 1 if profile else 2   # legs closer together seen from the side
    for i, sgn in enumerate((-1, 1)):
        lx = CX - half if sgn < 0 else CX + half - 2
        for y in range(17, 22):
            t = (y - 16) / 5
            off = round(stride * (1 if i == 0 else -1) * t * (face if (profile or sx) else 0))
            # Seen from the front or back a stride shows as one foot lifted.
            up = 1 if (not sx and stride and ((stride > 0) == (i == 0))) else 0
            if y <= 21 - up:
                for x in (lx + off, lx + off + 1):
                    put(x, y, pants)
        foot_off = round(stride * (1 if i == 0 else -1) * (face if (profile or sx) else 0))
        up = 1 if (not sx and stride and ((stride > 0) == (i == 0))) else 0
        fx = lx + foot_off
        put(fx, 22 - up, shoe)
        put(fx + 1, 22 - up, shoe)
        if profile or sx:
            put(fx + (2 if face > 0 else -1), 22 - up, shoe)   # the toe points the facing way
    # Shirt: rows 9 + top to 16, the shirt key (chalk) only on rows 9 to 16.
    w0, w1 = (CX - 2, CX + 1) if profile else (CX - 3, CX + 2)
    for y in range(max(9, 9 + top), 17):
        for x in range(w0, w1 + 1):
            if y == max(9, 9 + top) and x in (w0, w1):
                continue  # round shoulders
            put(x, y, shirt)
    # Arms: chalk sleeves on the shoulders, skin forearms; a walk swings them, a swing holds the
    # club in both hands.
    if state == "swing":
        hx = CX + face * SWING_HANDS[n][0]
        hy = 14 + SWING_HANDS[n][1]
        for (shx, shy) in ((w0, 10), (w1, 10)):
            steps = max(abs(hx - shx), abs(hy - shy), 1)
            for k in range(steps + 1):
                ax = round(shx + (hx - shx) * k / steps)
                ay = round(shy + (hy - shy) * k / steps)
                if 9 <= ay <= 11 and abs(ax - shx) <= 1:
                    continue  # the sleeve is the shirt's
                if not (w0 <= ax <= w1 and 9 <= ay <= 16):
                    put(ax, ay, skin)
        put(hx, hy, skin)
    else:
        swing_arm = [1, 0, -1, 0][n] if walk else 0
        if profile:
            # Seen from the side the near arm hangs along the body: a hand at its front edge,
            # swinging fore and aft on a walk.
            hx = (w1 + 1) if face > 0 else (w0 - 1)
            put(hx + swing_arm * face if swing_arm * face > 0 else hx, 14 + top, skin)
        else:
            for side, sgn in ((w0 - 1, -1), (w1 + 1, 1)):
                a_off = swing_arm * sgn
                for y in range(10 + top, 12 + top):
                    put(side, y, shirt if 9 <= y <= 16 else skin)
                for y in range(12 + top, 15 + top):
                    put(side + (a_off if y >= 13 + top else 0), y, skin)
    # Head: skin face, or hair from behind; hair on the back half seen from the side.
    hy0 = 4 + top
    for y in range(hy0, hy0 + 5):
        for x in range(CX - 2, CX + 2):
            c = skin
            if back:
                c = hair
            elif profile and (x - CX + 0.5) * face < 0 and y < hy0 + 3:
                c = hair
            put(x, y, c)
    # Cap: crown row and band; the brim points where the golfer faces.
    for x in range(CX - 2, CX + 2):
        put(x, hy0 - 1, cap)
        put(x, hy0, cap)
    for x in range(CX - 1, CX + 1):
        put(x, hy0 - 2, cap)
    if not back:
        if profile:
            put(CX + (2 if face > 0 else -3), hy0 + 1, cap)
            put(CX + (3 if face > 0 else -4), hy0 + 1, cap)
        else:
            for x in range(CX - 2, CX + 2):
                put(x, hy0 + 1, cap)
            if sx:
                put(CX + (2 if sx > 0 else -3), hy0 + 1, cap)
    # Eyes on the facing side.
    if not back:
        ey = hy0 + 2
        if profile:
            img.set(CX + (1 if face > 0 else -2), ey, p["ink"])
        elif sx:
            img.set(CX + (1 if sx > 0 else -2), ey, p["ink"])
            img.set(CX + (-1 if sx > 0 else 0), ey, p["ink"])
        else:
            img.set(CX - 2, ey, p["ink"])
            img.set(CX + 1, ey, p["ink"])
    # Outline: ink round the whole figure.
    outline_mask(img, body, p["ink"])
    # The club: slate_light shaft from the hands, an ink head at its end.
    if state == "swing":
        hx = CX + face * SWING_HANDS[n][0]
        hy = 14 + SWING_HANDS[n][1]
        deg = SWING_DEG[n]
    else:
        hx, hy, deg = CX + face * (3 if profile else 4), 14 + top, 8
        if back:
            hx = CX - face * 4
    a = math.radians(deg)
    end = (hx, hy)
    for i in range(1, 10):
        x = hx + round(face * math.sin(a) * i)
        y = hy + round(math.cos(a) * i)
        if not (0 <= x < GW and 0 <= y < GH):
            break
        if (x, y) in body:
            continue
        img.set(x, y, p["slate_light"])
        end = (x, y)
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


BUILDERS = {"golfer": build_golfer, "trees": build_trees, "decor": build_decor, "ball": build_ball,
            "markers": build_markers, "clubhouse": build_clubhouse}


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
