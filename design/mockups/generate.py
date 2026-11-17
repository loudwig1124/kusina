#!/usr/bin/env python3
"""Kusina pixel-art UI mockups.

Pure Python 3 + Pillow. No network, no randomness, no external assets.
Run from the repository root:

    python3 design/mockups/generate.py

Output: six 540x960 PNGs next to this script (180x320 art units at 3x,
nearest-neighbour). Colours come from ../palette.json.

Deliberate demo of the typography rule in docs/07-pixel-ui-spec.md:
pixel-bitmap font for headings, tab/section labels, action-button labels and
numerals; readable anti-aliased TrueType for body text and for every locked
status string (Have / Low / Out / Probably have, Ready / Probably have /
Missing, Didn't use / Used it / Used it up) so those strings appear verbatim
in title case. The bitmap font is hand-built below (5x7 glyphs); the body
font is loaded from the operating system and never shipped.

One tap-target floor (docs/07 section 0 rule 6 and section 4): every control
has a hit rect of at least 24 au (48 dp) in both dimensions and the single
primary action is 28 au (56 dp) tall. `check_floors()` enforces the numbers
used by every screen; a rerun is byte-identical (no randomness, no clock).

Optional: `--sheet /tmp/kusina_sheet.png` writes a font/sprite contact sheet.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
PALETTE_PATH = HERE.parent / "palette.json"

S = 3                 # integer scale: 1 art unit (au) = 3 image px
W, H = 180, 320       # art units
IW, IH = W * S, H * S

BODY = 27             # image px -> 18 dp at the reference 360 dp viewport (>=18 sp rule)
META = 22             # image px -> ~16 dp, short labels only
SMALL = 21            # image px -> 14 dp, control labels and locked status strings
TINY = 18             # image px -> ~12 dp, contact-sheet captions only

# Tap-target floor, in art units (1 au = 2 dp at the reference device).
FLOOR_AU = 24               # 48 dp hit rect, minimum in BOTH dimensions
PRIMARY_H = 28              # 56 dp, the single primary action
SECONDARY_H = 24            # 48 dp
METHOD_BTN_W, METHOD_BTN_H = 78, 36   # 156 x 72 dp, two per row + 4 au gap
INV_CHIP_W, INV_CHIP_H = 76, 24       # 152 x 48 dp, 2 x 2 grid per ingredient
REVIEW_CHOICE_W, REVIEW_CHOICE_H = 48, 24  # 96 x 48 dp, three per line
REVIEW_TAG_W, REVIEW_TAG_H = 72, 24        # 144 x 48 dp, tappable = "I have it"
DETAIL_CHIP_W, DETAIL_CHIP_H = 68, 24      # 136 x 48 dp, recipe-detail row
TAB_TARGET_W, TAB_TARGET_H = 45, 24        # 90 x 48 dp, four tabs

D = None              # set in main(); helpers draw into it


# --------------------------------------------------------------------------
# palette
# --------------------------------------------------------------------------

def load_palette(path=PALETTE_PATH):
    with path.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
    colors = {}
    for name, entry in data["colors"].items():
        h = entry["hex"].lstrip("#")
        colors[name] = (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
    return data, colors


PALETTE = {}
C = lambda name: PALETTE[name]


# --------------------------------------------------------------------------
# fonts
# --------------------------------------------------------------------------

_FONT_CACHE = {}
_REGULAR_PATHS = [
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Supplemental/Verdana.ttf",
    "/System/Library/Fonts/Supplemental/Helvetica.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/SFNS.ttf",
    "/Library/Fonts/Arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
]
_BOLD_PATHS = [
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Verdana Bold.ttf",
    "/System/Library/Fonts/Supplemental/Helvetica Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/SFNS.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
]
_BODY_FONT_USED = "default"


def _load_font(size, bold=False):
    paths = _BOLD_PATHS if bold else _REGULAR_PATHS
    for p in paths:
        try:
            if Path(p).exists():
                f = ImageFont.truetype(p, size=size)
                if not bold:
                    global _BODY_FONT_USED
                    _BODY_FONT_USED = p
                return f
        except (OSError, ValueError):
            continue
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # very old Pillow
        return ImageFont.load_default()


def body(size=BODY, bold=False):
    key = (size, bold)
    if key not in _FONT_CACHE:
        _FONT_CACHE[key] = _load_font(size, bold)
    return _FONT_CACHE[key]


# --------------------------------------------------------------------------
# 5x7 bitmap font (headings, labels, numbers, chrome only)
# --------------------------------------------------------------------------

_G = {
    "A": (".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"),
    "B": ("####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."),
    "C": (".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."),
    "D": ("####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."),
    "E": ("#####", "#....", "#....", "####.", "#....", "#....", "#####"),
    "F": ("#####", "#....", "#....", "####.", "#....", "#....", "#...."),
    "G": (".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."),
    "H": ("#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"),
    "I": ("#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"),
    "J": ("..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."),
    "K": ("#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"),
    "L": ("#....", "#....", "#....", "#....", "#....", "#....", "#####"),
    "M": ("#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"),
    "N": ("#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"),
    "O": (".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."),
    "P": ("####.", "#...#", "#...#", "####.", "#....", "#....", "#...."),
    "Q": (".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"),
    "R": ("####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"),
    "S": (".####", "#....", "#....", ".###.", "....#", "....#", "####."),
    "T": ("#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."),
    "U": ("#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."),
    "V": ("#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."),
    "W": ("#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"),
    "X": ("#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"),
    "Y": ("#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."),
    "Z": ("#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"),
    "0": (".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."),
    "1": ("..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."),
    "2": (".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"),
    "3": ("#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."),
    "4": ("...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."),
    "5": ("#####", "#....", "####.", "....#", "....#", "#...#", ".###."),
    "6": (".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."),
    "7": ("#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."),
    "8": (".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."),
    "9": (".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."),
    " ": (".....", ".....", ".....", ".....", ".....", ".....", "....."),
    ".": (".....", ".....", ".....", ".....", ".....", ".##..", ".##.."),
    ",": (".....", ".....", ".....", ".....", ".##..", ".##..", ".#..."),
    ":": (".....", ".##..", ".##..", ".....", ".##..", ".##..", "....."),
    "!": ("..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."),
    "?": (".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."),
    "-": (".....", ".....", ".....", ".###.", ".....", ".....", "....."),
    "+": (".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."),
    "/": ("....#", "...#.", "...#.", "..#..", ".#...", ".#...", "#...."),
    "%": ("##..#", "##.#.", "..#..", ".#...", ".#.##", "#..##", "....."),
    "(": ("...#.", "..#..", ".#...", ".#...", ".#...", "..#..", "...#."),
    ")": (".#...", "..#..", "...#.", "...#.", "...#.", "..#..", ".#..."),
    "'": ("..#..", "..#..", ".....", ".....", ".....", ".....", "....."),
    "x": (".....", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#"),
}


# --------------------------------------------------------------------------
# primitives
# --------------------------------------------------------------------------

def r(x, y, w, h, color):
    """Filled rectangle in art units."""
    if w <= 0 or h <= 0:
        return
    x0 = int(round(x * S))
    y0 = int(round(y * S))
    x1 = int(round((x + w) * S)) - 1
    y1 = int(round((y + h) * S)) - 1
    if x1 < x0 or y1 < y0:
        return
    D.rectangle([x0, y0, x1, y1], fill=color)


def bitmap(x, y, s, color, scale=1, anchor="la"):
    """Draw 5x7 bitmap text. (x, y) in art units. scale = au per font pixel."""
    s = str(s).upper()
    width = (len(s) * 6 - 1) * scale
    height = 7 * scale
    if anchor[0] == "m":
        x -= width / 2.0
    elif anchor[0] == "r":
        x -= width
    if anchor[1] == "m":
        y -= height / 2.0
    cx = x
    for ch in s:
        glyph = _G.get(ch) or _G.get(ch.upper()) or _G["?"]
        for j, row in enumerate(glyph):
            for i, cell in enumerate(row):
                if cell == "#":
                    r(cx + i * scale, y + j * scale, scale, scale, color)
        cx += 6 * scale
    return width, height


def bitmap_width(s, scale=1):
    return (len(str(s)) * 6 - 1) * scale


def text(x, y, s, size, color, bold=False, anchor="la"):
    D.text((x * S, y * S), s, font=body(size, bold), fill=color, anchor=anchor)


def text_width(s, size, bold=False):
    return D.textlength(s, font=body(size, bold))


def wrap(s, size, max_w_au, bold=False):
    f = body(size, bold)
    max_px = max_w_au * S
    words = str(s).split()
    lines, cur = [], ""
    for word in words:
        trial = (cur + " " + word).strip()
        if D.textlength(trial, font=f) <= max_px or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def para(x, y, s, size, color, max_w_au, bold=False, line_h=None):
    """Wrapped body text. Returns the height used, in art units."""
    f = body(size, bold)
    line_h = line_h or int(round(size * 1.35))
    lines = wrap(s, size, max_w_au, bold)
    yy = int(round(y * S))
    for ln in lines:
        D.text((x * S, yy), ln, font=f, fill=color, anchor="la")
        yy += line_h
    return (yy - int(round(y * S))) / S


def panel(x, y, w, h, fill, border=None, shadow=True, bw=2):
    border = border or C("adobo")
    if shadow:
        r(x + 2, y + 2, w, h, C("adobo"))
    r(x, y, w, h, border)
    r(x + bw, y + bw, w - 2 * bw, h - 2 * bw, fill)
    # pixel highlight and shade inside the frame
    r(x + bw, y + bw, w - 2 * bw, 1, C("white") if _light(fill) else C("banig"))
    r(x + bw, y + bw, 1, h - 2 * bw, C("white") if _light(fill) else C("banig"))
    r(x + bw, y + h - bw - 1, w - 2 * bw, 1, C("cream_dark") if _light(fill) else C("adobo"))
    r(x + w - bw - 1, y + bw, 1, h - 2 * bw, C("cream_dark") if _light(fill) else C("adobo"))


def _light(color):
    r_, g_, b_ = color
    return (0.299 * r_ + 0.587 * g_ + 0.114 * b_) > 110


def disc(cx, cy, radius, color):
    """Blocky filled circle in art units."""
    rr = int(radius)
    for dy in range(-rr, rr + 1):
        span = int(math.floor(math.sqrt(max(0.0, rr * rr - dy * dy)) + 1e-6))
        if dy in (-rr, rr):
            span = 0
        r(cx - span, cy + dy, 2 * span + 1, 1, color)


def ring(cx, cy, radius, thickness, color, progress=1.0):
    """Blocky ring arc, drawn clockwise from 12 o'clock."""
    steps = 240
    for i in range(int(steps * max(0.0, min(1.0, progress)))):
        a = math.radians(-90 + (360.0 * i / steps))
        for t in range(thickness):
            px = int(round(cx + (radius - t) * math.cos(a)))
            py = int(round(cy + (radius - t) * math.sin(a)))
            r(px, py, 1, 1, color)


def chip(x, y, w, h, label, fill, fg, size=SMALL, bold=True, border=None):
    border = border or C("adobo")
    r(x, y, w, h, border)
    r(x + 1, y + 1, w - 2, h - 2, fill)
    if _light(fill):
        r(x + 1, y + 1, w - 2, 1, C("white"))
    text(x + w / 2.0, y + h / 2.0, label, size, fg, bold=bold, anchor="mm")


def avail_width(label, size=SMALL, pad=7):
    """Width of an availability badge, in art units."""
    return int(text_width(label, size, True) / S) + pad * 2


def avail_badge(x, y, label, fill, fg, h=15, size=SMALL, pad=7, border=None):
    """Availability badge: title-case system sans, so Ready/Probably have/Missing read verbatim."""
    border = border or C("adobo")
    w = avail_width(label, size, pad)
    r(x, y, w, h, border)
    r(x + 1, y + 1, w - 2, h - 2, fill)
    text(x + w / 2.0, y + h / 2.0, label, size, fg, bold=True, anchor="mm")
    return w


def status_chip(x, y, state, w=DETAIL_CHIP_W, h=DETAIL_CHIP_H):
    """Current stock status chip: fill + icon shape + title-case label (never colour alone)."""
    st = PALETTE_STATES[state]
    fill, fg = C(st["fill"]), C(st["text"])
    r(x, y, w, h, C("adobo"))
    r(x + 1, y + 1, w - 2, h - 2, fill)
    _state_icon(x + 5, y + (h - 7) / 2.0, 7, st["icon"], fg)
    text(x + 17, y + h / 2.0, st["label"], SMALL, fg, bold=True, anchor="lm")
    return w


def tri_chip(x, y, state, selected, w=INV_CHIP_W, h=INV_CHIP_H):
    """One chip of the inventory 2 x 2 grid: selected = state fill + icon, else cream."""
    st = PALETTE_STATES[state]
    r(x, y, w, h, C("adobo"))
    if selected:
        fill, fg = C(st["fill"]), C(st["text"])
        r(x + 1, y + 1, w - 2, h - 2, fill)
        _state_icon(x + 5, y + (h - 7) / 2.0, 7, st["icon"], fg)
        text(x + 16, y + h / 2.0, st["label"], SMALL, fg, bold=True, anchor="lm")
    else:
        fill, fg = C("cream"), C("ink_soft")
        r(x + 1, y + 1, w - 2, h - 2, fill)
        text(x + w / 2.0, y + h / 2.0, st["label"], SMALL, fg, bold=True, anchor="mm")
    return w


def state_tag(x, y, state, restock=False):
    """Review row status tag. When it can restock it carries a '+' and is the 48 dp target."""
    st = PALETTE_STATES[state]
    fill, fg = C(st["fill"]), C(st["text"])
    w, h = REVIEW_TAG_W, REVIEW_TAG_H
    r(x, y, w, h, C("adobo"))
    r(x + 1, y + 1, w - 2, h - 2, fill)
    _state_icon(x + 4, y + (h - 7) / 2.0, 7, st["icon"], fg)
    text(x + 15, y + h / 2.0, st["label"], SMALL, fg, bold=True, anchor="lm")
    if restock:
        bitmap(x + w - 6, y + h / 2.0, "+", fg, 1, anchor="mm")
    return w


def review_choice(x, y, label, selected=False, disabled=False):
    """One of the three usage-review choices: 48 x 24 au, mutually exclusive per line."""
    w, h = REVIEW_CHOICE_W, REVIEW_CHOICE_H
    if selected:
        fill, fg = C("clay"), C("white")
    elif disabled:
        fill, fg = C("cream_dark"), C("slate")
    else:
        fill, fg = C("cream"), C("ink")
    r(x, y, w, h, C("adobo"))
    r(x + 1, y + 1, w - 2, h - 2, fill)
    text(x + w / 2.0, y + h / 2.0, label, SMALL, fg, bold=True, anchor="mm")


def method_button(x, y, label, method_state, selected=False, enabled=True):
    """Method button 78 x 36 au: method sprite + title-case label + that method's badge."""
    w, h = METHOD_BTN_W, METHOD_BTN_H
    st = PALETTE_AVAILABILITY[method_state]
    if not enabled:
        fill, border, fg = C("cream_dark"), C("slate"), C("ink_soft")
    elif selected:
        fill, border, fg = C("clay"), C("clay_dark"), C("white")
    else:
        fill, border, fg = C("cream"), C("slate"), C("ink")
    r(x + 2, y + 2, w, h, C("adobo"))
    r(x, y, w, h, border)
    r(x + 2, y + 2, w - 4, h - 4, fill)
    icon(x + 4, y + 2, "pan" if label.lower().startswith("pan") else "airfryer", fg, 16)
    text(x + 22, y + 10, label, SMALL, fg, bold=True, anchor="lm")
    if selected:
        _state_icon(x + w - 12, y + 6, 7, "check", fg)
    avail_badge(x + 4, y + 21, st["label"], C(st["fill"]), C(st["text"]),
                h=12, size=SMALL, pad=5,
                border=C("white") if selected else C("adobo"))


def _state_icon(x, y, size, kind, color):
    """7x7 state icons, distinct by shape as well as colour."""
    if kind == "check":
        for i, (dx, dy) in enumerate(((0, 3), (1, 4), (2, 5), (3, 4), (4, 3), (5, 2), (6, 1))):
            r(x + dx, y + dy, 1, 1, color)
            r(x + dx, y + dy + 1, 1, 1, color)
    elif kind == "cross":
        for i in range(5):
            r(x + i, y + i, 1, 1, color)
            r(x + 4 - i, y + i, 1, 1, color)
    elif kind == "half":
        r(x, y, 7, 1, color)
        r(x, y + 6, 7, 1, color)
        r(x, y, 1, 7, color)
        r(x + 6, y, 1, 7, color)
        r(x + 3, y + 1, 1, 5, color)
        r(x + 1, y + 1, 2, 5, color)
    elif kind == "question":
        r(x + 2, y, 3, 1, color)
        r(x + 1, y + 1, 1, 1, color)
        r(x + 5, y + 1, 1, 1, color)
        r(x + 5, y + 2, 1, 1, color)
        r(x + 4, y + 3, 1, 1, color)
        r(x + 3, y + 4, 1, 1, color)
        r(x + 3, y + 6, 1, 1, color)
    else:  # dash
        r(x, y + 3, 7, 1, color)


def button(x, y, w, h, label, kind="primary", enabled=True, scale=None):
    if kind == "primary":
        fill = C("clay") if enabled else C("cream_dark")
        fg = C("white") if enabled else C("ink_soft")
        border = C("clay_dark") if enabled else C("slate")
    else:
        fill = C("cream")
        fg = C("clay_dark") if enabled else C("ink_soft")
        border = C("clay") if enabled else C("slate")
    r(x + 2, y + 2, w, h, C("adobo"))
    r(x, y, w, h, border)
    r(x + 2, y + 2, w - 4, h - 4, fill)
    r(x + 2, y + 2, w - 4, 2, C("white") if _light(fill) else C("clay_dark") if enabled else fill)
    if scale is None:
        scale = 2 if bitmap_width(label, 2) <= w - 14 else 1
    bitmap(x + w / 2.0, y + h / 2.0, label, fg, scale=scale, anchor="mm")


# --------------------------------------------------------------------------
# sprites (placeholder pixel art, authored here as ASCII)
# --------------------------------------------------------------------------

SPRITE_MAP = {
    "#": "adobo", "k": "ink", "s": "ink_soft", "a": "adobo", "c": "clay", "C": "clay_dark",
    "b": "banig", "g": "calamansi", "G": "calamansi_dark", "m": "amber",
    "M": "amber_dark", "r": "rust", "R": "rust_dark", "l": "slate",
    "w": "white", "e": "cream", "E": "cream_dark",
}

SPRITES = {
    # Chicken Adobo: clay pot, dark stew, steam
    "adobo": (
        "................",
        "....e...e...e...",
        "....e...e...e...",
        "................",
        "...kkkkkkkkkk...",
        "..#bbbbbbbbbb#..",
        ".#cccccccccccc#.",
        ".#cCbaaaaaaaCc#.",
        ".#cCaaaaaaaaCc#.",
        ".#cCaaaaaaaaCc#.",
        ".#cCCCCCCCCCCc#.",
        ".#cccccccccccc#.",
        "..#cccccccccc#..",
        "...kkkkkkkkkk...",
        "................",
        "................",
    ),
    # Sinangag: bowl of garlic fried rice, spring onion
    "sinangag": (
        "................",
        "....e...e...e...",
        "....e...e...e...",
        "................",
        "...kkkkkkkkkk...",
        "..#bbbbbbbbbb#..",
        ".#cccccccccccc#.",
        ".#ceeeeeeeeeec#.",
        ".#ceeebeeeebec#.",
        ".#cebeeegeeeec#.",
        ".#ceeeebeeegec#.",
        ".#cccccccccccc#.",
        "..#cccccccccc#..",
        "...kkkkkkkkkk...",
        "................",
        "................",
    ),
    # Crispy Pork Belly: plate, crisp skin, meat, fat layers
    "crispy": (
        "................",
        "................",
        "...kkkkkkkkkk...",
        "..#bbbbbbbbbb#..",
        ".#bbbbbbbbbbbb#.",
        ".#bmmmmmmmmmmb#.",
        ".#bmrrrrrrrrrb#.",
        ".#bmmmmmmmmmmb#.",
        ".#bbbbbbbbbbbb#.",
        ".#bmwwwwwwwwwb#.",
        ".#bmrrrrrrrrrb#.",
        ".#bmmmmmmmmmmb#.",
        "..#bbbbbbbbbb#..",
        "...kkkkkkkkkk...",
        "................",
        "................",
    ),
    # Palayok mascot
    "mascot": (
        "................",
        "....e...e..e....",
        "....e...e..e....",
        "................",
        "....kkkkkkkk....",
        "...#cccccccc#...",
        "..#cccccccccc#..",
        ".#cccccccccccc#.",
        ".#cwkkcccckkwc#.",
        ".#cwkkcccckkwc#.",
        ".#cccccccccccc#.",
        ".#ccccMkkMcccc#.",
        "..#cccccccccc#..",
        "...kkkkkkkkkk...",
        "................",
        "................",
    ),
}


def sprite(x, y, name, px=3):
    rows = SPRITES[name]
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch == ".":
                continue
            r(x + i * px, y + j * px, px, px, C(SPRITE_MAP[ch]))
    return (len(rows[0]) * px, len(rows) * px)


def icon(x, y, kind, color, size=12):
    """Procedural chrome icons, 12-16 au."""
    if kind == "pot":
        r(x, y + 1, size, 2, color)
        r(x + 4, y - 1, 4, 1, color)
        r(x + 1, y + 3, size - 2, 1, color)
        r(x + 1, y + 3, 1, size - 5, color)
        r(x + size - 2, y + 3, 1, size - 5, color)
        r(x + 1, y + size - 3, size - 2, 1, color)
        r(x + 3, y + 6, size - 6, 2, C("cream") if color == C("ink") else C("ink"))
    elif kind == "book":
        r(x + 1, y + 1, size - 2, size - 2, color)
        r(x + 2, y + 2, size - 4, size - 4, C("cream"))
        r(x + 4, y + 4, size - 8, 1, color)
        r(x + 4, y + 7, size - 8, 1, color)
        r(x + 2, y + 3, 1, size - 6, color)
    elif kind == "basket":
        r(x + 3, y, 2, 2, color)
        r(x + size - 5, y, 2, 2, color)
        r(x, y + 2, size, 1, color)
        r(x + 1, y + 3, size - 2, size - 4, C("cream"))
        r(x + 1, y + 3, 1, size - 4, color)
        r(x + size - 2, y + 3, 1, size - 4, color)
        r(x + 1, y + size - 2, size - 2, 1, color)
        for i in range(3):
            r(x + 3 + i * 2, y + 5, 1, 4, color)
    elif kind == "clock":
        ring(x + size / 2.0 - 0.5, y + size / 2.0 - 0.5, size / 2.0 - 1, 2, color)
        r(x + size / 2.0 - 0.5, y + 3, 1, size / 2.0 - 3, color)
        r(x + size / 2.0 - 0.5, y + size / 2.0, 3, 1, color)
    elif kind == "gear":
        r(x + 3, y + 1, size - 6, size - 2, color)
        r(x + 1, y + 3, size - 2, size - 6, color)
        r(x + 4, y + 4, size - 8, size - 8, C("cream"))
        r(x + 5, y + 5, size - 10, size - 10, color)
    elif kind == "back":
        r(x + 2, y + 5, size - 4, 2, color)
        r(x + 4, y + 3, 2, 1, color)
        r(x + 3, y + 4, 2, 1, color)
        r(x + 3, y + 7, 2, 1, color)
        r(x + 4, y + 8, 2, 1, color)
    elif kind == "close":
        for i in range(size - 4):
            r(x + 2 + i, y + 2 + i, 2, 2, color)
            r(x + size - 4 - i, y + 2 + i, 2, 2, color)
    elif kind == "check":
        _state_icon(x + 1, y + 1, 7, "check", color)
    elif kind == "caution":
        for j in range(size - 2):
            span = min(j, size - 2 - j)
            r(x + size / 2.0 - span, y + 1 + j, 2 * span + 1, 1, color)
        r(x + size / 2.0 - 1, y + 4, 2, 4, C("cream"))
        r(x + size / 2.0 - 1, y + 9, 2, 2, C("cream"))
    elif kind == "search":
        ring(x + size / 2.0 - 2, y + size / 2.0 - 2, size / 2.0 - 3, 2, color)
        r(x + size - 4, y + size - 4, 4, 2, color)
    elif kind == "finger":
        r(x + 4, y + 2, 4, 8, color)
        r(x + 4, y + 9, 7, 3, color)
        r(x + 2, y + 9, 2, 2, color)
    elif kind == "stove":
        r(x, y + 2, size, 3, color)
        r(x + 2, y + 5, size - 4, size - 6, color)
        r(x + 1, y + size - 2, size - 2, 1, color)
        for i in range(2):
            r(x + 3 + i * 4, y + 7, 1, 3, C("cream") if color == C("ink") else C("ink"))
    elif kind == "pan":
        # variant_panfry placeholder: shallow pan seen from the side
        r(x, y + 5, size - 5, 2, color)
        r(x + 1, y + 7, size - 7, 1, color)
        r(x + size - 5, y + 4, 5, 2, color)
        r(x + 2, y + 3, max(1, size - 9), 1, color)
    elif kind == "airfryer":
        # variant_airfry placeholder: basket box with a front drawer line
        r(x + 1, y + 2, size - 2, 2, color)
        r(x + 1, y + 2, 2, size - 4, color)
        r(x + size - 3, y + 2, 2, size - 4, color)
        r(x + 1, y + size - 3, size - 2, 2, color)
        r(x + 4, y + 6, size - 8, 2, color)
        r(x + 4, y + size - 6, size - 8, 1, color)


# --------------------------------------------------------------------------
# shared chrome
# --------------------------------------------------------------------------

STATUS_H = 12
APPBAR_Y = 12
APPBAR_H = 26
CONTENT_Y = 38


def status_bar():
    r(0, 0, W, STATUS_H, C("cream_dark"))
    r(0, STATUS_H - 1, W, 1, C("adobo"))
    bitmap(6, 3, "7:42", C("ink"), 1)
    # signal bars + battery (system chrome, deliberately abstract)
    r(146, 5, 2, 3, C("ink_soft"))
    r(149, 4, 2, 4, C("ink_soft"))
    r(152, 3, 2, 5, C("ink_soft"))
    r(156, 3, 2, 5, C("ink_soft"))
    r(161, 3, 12, 6, C("ink"))
    r(163, 5, 8, 2, C("cream"))
    r(173, 5, 2, 3, C("ink"))


def app_bar(title, back=False, right=None, right_icon=None):
    r(0, APPBAR_Y, W, APPBAR_H, C("cream"))
    r(0, APPBAR_Y + APPBAR_H - 1, W, 1, C("cream_dark"))
    x = 6
    if back:
        icon(5, 19, "back", C("ink"), 12)
        x = 24
    bitmap(x, APPBAR_Y + 10, title, C("clay_dark"), 1)
    if right_icon:
        icon(160, 19, right_icon, C("ink_soft"), 12)
    if right:
        bitmap(174, APPBAR_Y + 10, right, C("ink_soft"), 1, anchor="ra")


def progress_bar(x, y, w, h, value):
    r(x, y, w, h, C("adobo"))
    r(x + 1, y + 1, w - 2, h - 2, C("cream_dark"))
    filled = int((w - 2) * max(0.0, min(1.0, value)))
    if filled > 0:
        r(x + 1, y + 1, filled, h - 2, C("clay"))
        r(x + 1, y + 1, filled, 1, C("banig"))


def tab_bar(active="COOK"):
    y = H - 24
    r(0, y, W, 24, C("cream_dark"))
    r(0, y, W, 1, C("adobo"))
    tabs = [("pot", "COOK"), ("book", "RECIPES"), ("basket", "STOCK"), ("clock", "HISTORY")]
    slot = W / 4.0
    for i, (ic, label) in enumerate(tabs):
        on = label == active
        col = C("clay_dark") if on else C("ink_soft")
        cx = slot * i + slot / 2.0
        icon(cx - 6, y + 2, ic, col, 12)
        bitmap(cx, y + 15, label, col, 1, anchor="ma")
        if on:
            r(cx - 10, y + 1, 20, 2, C("clay"))


def toast(y, s, icon_kind="check"):
    panel(10, y, 160, 24, C("adobo"), border=C("ink"), shadow=False, bw=2)
    r(12, y + 2, 156, 1, C("banig"))
    icon(17, y + 7, icon_kind, C("banig"), 10)
    text(31, y + 12, s, SMALL, C("cream"), bold=False, anchor="lm")


# --------------------------------------------------------------------------
# screen 01 - Cook now (three availability badges)
# --------------------------------------------------------------------------

def screen_01():
    status_bar()
    app_bar("KUSINA", right_icon="gear")

    bitmap(6, 42, "COOK NOW", C("ink"), 2)
    text(6, 57, "Maria's Kitchen | 3 dishes", BODY, C("ink_soft"))
    bitmap(6, 68, "STOVETOP + AIR FRYER", C("ink_soft"), 1)
    r(6, 79, 168, 1, C("cream_dark"))

    # Locked demo snapshot: Adobo Missing (bay leaf out), the other two Ready.
    cards = [
        ("adobo", "Chicken Adobo", "4 servings | 35 min", "blocked"),
        ("sinangag", "Sinangag", "2 servings | 20 min", "ready"),
        ("crispy", "Crispy Pork Belly", "4 servings | 30 min", "ready"),
    ]
    y = 84
    for name, title, meta, state in cards:
        panel(6, y, 168, 66, C("white"))
        sprite(13, y + 9, name, 3)
        para(64, y + 7, title, 26, C("ink"), 104, bold=True, line_h=31)
        text(64, y + 34, meta, META, C("ink_soft"))
        st = PALETTE_AVAILABILITY[state]
        avail_badge(166 - avail_width(st["label"]), y + 46,
                    st["label"], C(st["fill"]), C(st["text"]))
        y += 71

    tab_bar("COOK")


# --------------------------------------------------------------------------
# screen 02 - Recipe detail: Missing + Guide me anyway (+ Probably have footer)
# --------------------------------------------------------------------------

def screen_02():
    status_bar()
    app_bar("RECIPE", back=True, right_icon="gear")

    sprite(6, 40, "crispy", 3)
    text(60, 40, "Crispy Pork Belly", 24, C("ink"), bold=True)
    text(60, 58, "Base yield: 4 servings", META, C("ink_soft"))
    text(60, 70, "2 cooking methods | 30 min", META, C("ink_soft"))

    # Cooking method control (P0): two buttons, per-method availability badges,
    # no pre-selection. Illustrative state: the cook picked Air-fry.
    bitmap(6, 92, "COOKING METHOD", C("ink_soft"), 1)
    bitmap(166, 92, "NO DEFAULT", C("ink_soft"), 1, anchor="ra")
    method_button(8, 102, "Pan-fry", "needs_confirmation")
    method_button(90, 102, "Air-fry", "blocked", selected=True)

    # Availability panel for the selected method: air fryer not owned -> Missing.
    panel(6, 146, 168, 30, C("white"), border=C("rust_dark"))
    r(8, 148, 3, 26, C("rust"))
    bw = avail_badge(14, 151, "Missing", C("rust"), C("white"))
    text(14 + bw + 6, 148, "Air fryer is missing.", META, C("rust_dark"), bold=True)
    bitmap(14 + bw + 6, 160, "1 MISSING ITEM", C("ink_soft"), 1)

    # Required rows + the optional line, collapsed (never clipped, never blocking).
    panel(6, 182, 168, 86, C("cream_dark"), shadow=False)
    bitmap(12, 185, "WHAT YOU NEED", C("ink_soft"), 1)
    rows = [("Pork belly", "have"), ("Salt", "unknown")]
    y = 194
    for label, state in rows:
        r(12, y, 156, 1, C("cream"))
        text(14, y + 5, label, META, C("ink"))
        status_chip(164 - DETAIL_CHIP_W, y + 3, state)
        y += 28
    r(12, 252, 156, 1, C("cream"))
    text(12, 255, "Optional (9): garlic, soy sauce, + 7 more", SMALL, C("ink_soft"))

    button(6, 272, 168, PRIMARY_H, "GUIDE ME ANYWAY", "primary", enabled=True)
    text(6, 304, "Starts anyway and records: air fryer missing.", SMALL, C("ink_soft"))


# --------------------------------------------------------------------------
# screen 03 - Guided cook, prep step (tap to continue)
# --------------------------------------------------------------------------

def kitchen_scene(y, h):
    r(0, y, W, h, C("cream_dark"))
    for x in range(0, W, 12):
        r(x, y + 5, 6, 2, C("banig"))
        r(x + 6, y + 9, 6, 2, C("banig"))
    r(10, y + 16, 56, 40, C("adobo"))
    r(13, y + 19, 50, 34, C("banig"))
    r(37, y + 19, 2, 34, C("adobo"))
    r(13, y + 35, 50, 2, C("adobo"))
    r(16, y + 21, 8, 3, C("cream"))
    r(0, y + h - 26, W, 26, C("clay_dark"))
    r(0, y + h - 26, W, 3, C("banig"))
    r(0, y + h - 23, W, 1, C("adobo"))


def speech_bubble(x, y, w, lines):
    h = 10 + len(lines) * 9
    panel(x, y, w, h, C("white"), shadow=True)
    yy = y + 6
    for ln in lines:
        text(x + 6, yy, ln, SMALL, C("ink"))
        yy += 9
    r(x + 20, y + h, 2, 2, C("adobo"))
    r(x + 18, y + h + 2, 2, 2, C("adobo"))
    r(x + 21, y + h, 2, 2, C("white"))


def screen_03():
    status_bar()
    app_bar("STEP 1 OF 7", right_icon="close")
    # (k-1)/N with k = 1, N = 7: the first step paints 0 %.
    progress_bar(6, 41, 168, 5, 0.0)

    kitchen_scene(49, 104)
    sprite(120, 79, "mascot", 3)
    speech_bubble(66, 52, 100, ["Take your time.", "I wait for your tap."])

    panel(6, 157, 168, 115, C("white"))
    r(12, 163, 16, 16, C("clay"))
    bitmap(20, 171, "1", C("white"), 2, anchor="mm")
    text(34, 161, "Pat the chicken dry", 28, C("ink"), bold=True)
    para(12, 181, "Pat the chicken dry and season with black pepper.",
         BODY, C("ink"), 146, line_h=35)
    text(12, 208, "Dry skin browns better.", META, C("ink_soft"))
    r(12, 222, 156, 1, C("cream_dark"))
    icon(12, 227, "clock", C("ink_soft"), 12)
    text(28, 233, "No timer on this step", META, C("ink_soft"), anchor="lm")
    r(12, 242, 156, 1, C("cream_dark"))
    bitmap(12, 248, "NEXT: HEAT THE OIL", C("ink_soft"), 1)

    button(6, 276, 168, PRIMARY_H, "CONTINUE", "primary", enabled=True)
    bitmap(90, 308, "IT WAITS FOR YOUR TAP", C("ink_soft"), 1, anchor="ma")


# --------------------------------------------------------------------------
# screen 04 - Guided cook, timer step (running ring + done notification)
# --------------------------------------------------------------------------

def screen_04():
    status_bar()
    app_bar("STEP 2 OF 7", right_icon="close")
    # (k-1)/N with k = 2, N = 7: the second step paints 1/7.
    progress_bar(6, 41, 168, 5, 1 / 7.0)

    # Step card: order badge, title, instruction, detail, caution, next-step hint.
    # One timer phase only (running) - never running and finished at once.
    panel(6, 52, 168, 108, C("white"))
    r(12, 58, 16, 16, C("clay"))
    bitmap(20, 66, "2", C("white"), 2, anchor="mm")
    text(34, 56, "Heat the oil", 28, C("ink"), bold=True)
    para(12, 78, "Heat the cooking oil in a wide pan over medium heat.",
         BODY, C("ink"), 146, line_h=34)
    text(12, 106, "Use a wide pan so the oil heats evenly.", META, C("ink_soft"))
    r(12, 118, 156, 1, C("cream_dark"))
    icon(12, 123, "caution", C("amber_dark"), 10)
    text(28, 128, "Hot oil.", SMALL, C("ink"), anchor="lm")
    bitmap(12, 144, "NEXT: BROWN THE CHICKEN", C("ink_soft"), 1)

    # Timer panel, running phase only: the ring and the countdown are the same fact.
    panel(6, 166, 168, 86, C("adobo"), border=C("ink"), shadow=True, bw=2)
    r(8, 168, 164, 1, C("banig"))
    bitmap(14, 170, "TIMER", C("banig"), 1)
    cx, cy = 44, 210
    ring(cx, cy, 28, 3, C("cream_dark"), 1.0)
    ring(cx, cy, 28, 3, C("clay"), 0.55)
    bitmap(cx, cy - 4, "4:24", C("cream"), 2, anchor="mm")
    bitmap(cx, cy + 8, "LEFT", C("banig"), 1, anchor="mm")
    avail_badge(80, 174, "Running", C("amber"), C("ink"))
    text(80, 194, "8 min timer", META, C("cream"))
    text(80, 208, "No auto-advance.", META, C("white"), bold=True)
    text(80, 222, "Tap Continue when ready.", SMALL, C("cream"))
    text(80, 236, "Screen stays awake.", SMALL, C("banig"))

    button(6, 260, 168, PRIMARY_H, "CONTINUE", "primary", enabled=True)
    bitmap(90, 294, "TIMER IS ADVICE", C("ink_soft"), 1, anchor="ma")
    bitmap(90, 304, "TAP ADVANCES - NO AUTO", C("ink_soft"), 1, anchor="ma")


# --------------------------------------------------------------------------
# screen 05 - Usage review: Didn't use / Used it / Used it up, no numbers
# --------------------------------------------------------------------------

def review_row(y, name, state, choice, disabled=()):
    """One review line: name + tappable status tag (restock), then three 48 x 24 buttons."""
    r(12, y, 154, 1, C("cream_dark"))
    text(14, y + 5, name, META, C("ink"))
    state_tag(166 - REVIEW_TAG_W, y + 1, state, restock=(state != "have"))
    chips = [("Didn't use", "none"), ("Used it", "used"), ("Used it up", "up")]
    x = 12
    for label, key in chips:
        review_choice(x, y + 26, label, selected=(key == choice), disabled=(key in disabled))
        x += REVIEW_CHOICE_W + 4


def screen_05():
    status_bar()
    app_bar("USAGE REVIEW", right="CHICKEN ADOBO")

    text(6, 40, "What did you use?", 30, C("ink"), bold=True)
    text(6, 55, "One tap per ingredient, then confirm once.", META, C("ink_soft"))

    # Adobo has 8 review lines (5 required + 3 optional). At the 48 dp floor four
    # lines fit; the clipped fourth row plus the count and scrollbar are the cue.
    panel(6, 64, 168, 204, C("white"))
    bitmap(12, 68, "INGREDIENTS", C("ink_soft"), 1)
    bitmap(166, 68, "8 LINES", C("ink_soft"), 1, anchor="ra")
    text(12, 78, "Tap a status tag to mark I have it.", SMALL, C("ink_soft"))

    rows = [
        ("Chicken thighs", "have", "up", ()),
        ("Bay leaf", "out", "none", ("used",)),
        ("Garlic", "have", "used", ()),
        ("Vinegar", "have", "none", ()),
    ]
    y = 88
    for label, state, choice, disabled in rows:
        review_row(y, label, state, choice, disabled)
        y += 50

    # scrollbar: 4 of 8 lines visible, the rest scroll inside the pinned panel
    r(166, 88, 2, 172, C("cream_dark"))
    r(166, 88, 2, 86, C("clay"))

    button(6, 272, 168, PRIMARY_H, "CONFIRM", "primary", enabled=True)
    text(6, 304, "Tap a status tag: I have it.", SMALL, C("ink_soft"))
    text(6, 311, "Used it: Have -> low. Used it up: -> out.", SMALL, C("ink_soft"))


# --------------------------------------------------------------------------
# screen 06 - Inventory: four tri-state chips per ingredient
# --------------------------------------------------------------------------

def stock_row(y, name, state):
    """One inventory ingredient: name line + a 2 x 2 grid of 76 x 24 au chips."""
    text(12, y, name, META, C("ink"))
    grid = (("have", "low"), ("out", "unknown"))
    for gy, pair in enumerate(grid):
        for gx, key in enumerate(pair):
            tri_chip(12 + gx * (INV_CHIP_W + 4),
                     y + 10 + gy * (INV_CHIP_H + 2),
                     key, selected=(key == state))


def screen_06():
    status_bar()
    app_bar("INVENTORY", right="15 ITEMS")

    panel(6, 42, 168, 24, C("cream"), shadow=False, bw=1)
    icon(11, 47, "search", C("ink_soft"), 12)
    text(28, 54, "Search ingredients", META, C("ink_soft"), anchor="lm")

    filters = ["All", "Produce", "Meat", "Pantry"]
    x = 6
    for i, f in enumerate(filters):
        w = int(text_width(f, SMALL, True) / S) + 14
        fill = C("clay") if i == 0 else C("cream")
        fg = C("white") if i == 0 else C("ink")
        r(x, 70, w, 24, C("adobo"))
        r(x + 1, 71, w - 2, 22, fill)
        text(x + w / 2.0, 82, f, SMALL, fg, bold=True, anchor="mm")
        x += w + 4

    # 2 x 2 grid per ingredient: 76 x 24 au chips (152 x 48 dp) with 4 / 2 au gaps.
    # Three rows fit above the toast; the list scrolls (15 items, "3 OF 15").
    panel(6, 98, 168, 198, C("white"))
    bitmap(12, 102, "INGREDIENTS", C("ink_soft"), 1)
    bitmap(166, 102, "3 OF 15", C("ink_soft"), 1, anchor="ra")
    stock_row(112, "Garlic (Bawang)", "have")
    stock_row(172, "Spring onion (Sibuyas dahon)", "low")
    stock_row(232, "Bay leaf (Laurel)", "out")

    toast(294, "Saved. No numbers to type.")


# --------------------------------------------------------------------------
# state tables used by the chip, badge and method renderers
# --------------------------------------------------------------------------

PALETTE_STATES = {}
PALETTE_AVAILABILITY = {}


# --------------------------------------------------------------------------
# tap-target floor (docs/07 section 0 rule 6 and section 4)
# --------------------------------------------------------------------------

CONTROL_FLOORS = {
    "primary action": (168, PRIMARY_H),
    "secondary action": (168, SECONDARY_H),
    "inventory chip (2 x 2 grid)": (INV_CHIP_W, INV_CHIP_H),
    "review status tag (restock)": (REVIEW_TAG_W, REVIEW_TAG_H),
    "review choice": (REVIEW_CHOICE_W, REVIEW_CHOICE_H),
    "method button": (METHOD_BTN_W, METHOD_BTN_H),
    "recipe-detail status chip": (DETAIL_CHIP_W, DETAIL_CHIP_H),
    "tab target": (TAB_TARGET_W, TAB_TARGET_H),
}


def check_floors():
    """Fail loudly if any interactive control drops under the one floor."""
    bad = []
    for name, (w, h) in CONTROL_FLOORS.items():
        if min(w, h) < FLOOR_AU:
            bad.append(f"{name}: {w}x{h} au")
    if bad:
        raise SystemExit("tap-target floor violated (24 au = 48 dp): " + "; ".join(bad))
    print("tap-target floor: 24 au (48 dp) hit minimum in both dimensions; "
          "primary action 28 au (56 dp) - all controls pass")


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

SCREENS = [
    ("01_cook_now.png", screen_01),
    ("02_recipe_detail.png", screen_02),
    ("03_guide_prep.png", screen_03),
    ("04_guide_timer.png", screen_04),
    ("05_review.png", screen_05),
    ("06_stock_setup.png", screen_06),
]


def render(fn):
    global D
    img = Image.new("RGB", (IW, IH), C("cream"))
    D = ImageDraw.Draw(img)
    fn()
    return img


def contact_sheet(path):
    """Component contact sheet, laid out in art units (sheet = 373 x 580 au)."""
    global D
    img = Image.new("RGB", (373 * S, 580 * S), C("cream"))
    D = ImageDraw.Draw(img)
    x, y = 8, 8
    for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .:!?/-%+()'":
        bitmap(x, y, ch, C("ink"), 1)
        x += 6
    x, y = 10, 30
    for name in SPRITES:
        bitmap(x, y, name.upper(), C("ink_soft"), 1)
        sprite(x, y + 8, name, 3)
        x += 90
    x, y = 10, 98
    for kind in ("pot", "book", "basket", "clock", "gear", "back", "close",
                 "caution", "search", "finger", "stove", "pan", "airfryer"):
        icon(x, y, kind, C("ink"), 16)
        text(x, y + 18, kind, TINY, C("ink_soft"))
        x += 27
    x, y = 10, 136
    for state in ("have", "low", "out", "unknown"):
        w = status_chip(x, y, state)
        x += w + 6
    x, y = 10, 170
    for key in ("ready", "needs_confirmation", "blocked"):
        st = PALETTE_AVAILABILITY[key]
        w = avail_badge(x, y, st["label"], C(st["fill"]), C(st["text"]))
        x += w + 6
    x, y = 10, 200
    for i, key in enumerate(("have", "low", "out", "unknown")):
        tri_chip(x + (i % 2) * (INV_CHIP_W + 4), y + (i // 2) * (INV_CHIP_H + 2), key, True)
    x, y = 10, 260
    for label, key, sel in (("Pan-fry", "needs_confirmation", False),
                            ("Air-fry", "blocked", True)):
        method_button(x, y, label, key, selected=sel)
        x += METHOD_BTN_W + 8
    x, y = 10, 304
    for i, (label, sel) in enumerate((("Didn't use", False),
                                      ("Used it", True),
                                      ("Used it up", False))):
        review_choice(x + i * (REVIEW_CHOICE_W + 4), y, label, selected=sel)
    for i, key in enumerate(("have", "low", "out", "unknown")):
        state_tag(10 + i * (REVIEW_TAG_W + 6), 336, key, restock=(key != "have"))
    x, y = 10, 372
    ring(x + 30, y + 30, 26, 3, C("cream_dark"), 1.0)
    ring(x + 30, y + 30, 26, 3, C("clay"), 0.6)
    bitmap(x + 70, y + 24, "RUNNING", C("ink_soft"), 1)
    ring(x + 210, y + 30, 26, 3, C("calamansi_dark"), 1.0)
    _state_icon(x + 206, y + 26, 7, "check", C("calamansi"))
    bitmap(x + 250, y + 24, "DONE", C("ink_soft"), 1)
    button(10, 440, 168, PRIMARY_H, "PRIMARY", "primary", True, scale=2)
    button(10, 474, 168, SECONDARY_H, "SECONDARY", "secondary", True, scale=1)
    button(10, 504, 168, PRIMARY_H, "DISABLED", "primary", False, scale=2)
    toast(540, "Saved. No amounts to type.")
    img.save(path)
    return path


def main(argv=None):
    global PALETTE
    parser = argparse.ArgumentParser(description="Generate Kusina pixel-art mockups.")
    parser.add_argument("--sheet", metavar="PATH", help="write a font/sprite contact sheet and exit")
    parser.add_argument("--outdir", default=str(HERE), help="output directory (default: next to this script)")
    args = parser.parse_args(argv)

    data, PALETTE = load_palette()
    PALETTE_STATES.clear()
    PALETTE_STATES.update(data["states"])
    PALETTE_AVAILABILITY.clear()
    PALETTE_AVAILABILITY.update(data["availability"])

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    check_floors()

    if args.sheet:
        print(f"contact sheet: {contact_sheet(Path(args.sheet))}")
        return 0

    for name, fn in SCREENS:
        img = render(fn)
        path = outdir / name
        img.save(path)
        print(f"wrote {path} ({img.width}x{img.height})")
    print(f"body font: {_BODY_FONT_USED}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
