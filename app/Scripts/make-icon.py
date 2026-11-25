#!/usr/bin/env python3
"""生成 App 图标：钛金属暗底圆角方块 + 翠玉/钴蓝双引擎胶囊。"""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

S = 2048
OUT = 1024
MARGIN = int(100 / 1024 * S)
RADIUS = int(185 / 1024 * S)
BOX = (MARGIN, MARGIN, S - MARGIN, S - MARGIN)

PALETTE = json.loads(
    (Path(__file__).resolve().parent.parent.parent / "palette.json").read_text()
)


def hex_rgb(value):
    h = value.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=float)


TOP = hex_rgb(PALETTE["surface"]["top"])
BOTTOM = hex_rgb(PALETTE["surface"]["bottom"])
CODEX_A = hex_rgb(PALETTE["engines"]["codex"]["fillFrom"])
CODEX_B = hex_rgb(PALETTE["engines"]["codex"]["fillTo"])
AGY_A = hex_rgb(PALETTE["engines"]["antigravity"]["fillFrom"])
AGY_B = hex_rgb(PALETTE["engines"]["antigravity"]["fillTo"])
TRACK = np.array([255, 255, 255], dtype=float)


def rounded_mask(size, box, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return np.array(mask, dtype=float) / 255.0


def vertical_gradient(size, top, bottom):
    t = np.linspace(0, 1, size)[:, None]
    ramp = top[None, :] * (1 - t) + bottom[None, :] * t
    return np.repeat(ramp[:, None, :], size, axis=1)


def horizontal_bar(size, x0, y0, x1, y1, radius, c0, c1):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((x0, y0, x1, y1), radius=radius, fill=255)
    m = np.array(mask, dtype=float) / 255.0
    t = np.linspace(0, 1, size)[None, :, None]
    color = c0[None, None, :] * (1 - t) + c1[None, None, :] * t
    return np.repeat(color, size, axis=0), m


def main():
    mask = rounded_mask(S, BOX, RADIUS)[..., None]
    canvas = vertical_gradient(S, TOP, BOTTOM)

    bars = (
        (190, 760, 287, CODEX_A, CODEX_B),
        (190, 834, 567, AGY_A, AGY_B),
    )
    for (bx0, bx1, by, c0, c1) in bars:
        x0 = int(bx0 / 1024 * S)
        x1_full = int(834 / 1024 * S)
        x1 = int(bx1 / 1024 * S)
        y0 = int(by / 1024 * S)
        y1 = int((by + 170) / 1024 * S)
        rad = int(85 / 1024 * S)

        track_mask = rounded_mask(S, (x0, y0, x1_full, y1), rad)[..., None] * 0.08
        canvas = canvas * (1 - track_mask) + TRACK[None, None, :] * track_mask

        color, bar_mask = horizontal_bar(S, x0, y0, x1, y1, rad, c0, c1)
        m = bar_mask[..., None]
        canvas = canvas * (1 - m) + color * m

    rgb = np.clip(canvas, 0, 255).astype(np.uint8)
    alpha = np.clip(mask[..., 0] * 255, 0, 255).astype(np.uint8)
    rgba = np.dstack([rgb, alpha])
    img = Image.fromarray(rgba).resize((OUT, OUT), Image.Resampling.LANCZOS)

    out_path = Path(__file__).resolve().parent.parent / "AppBundle" / "AppIcon-1024.png"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path)
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main()
