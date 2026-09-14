#!/usr/bin/env python3
"""
Builds a gentle sway cycle out of a single static sprite.

This is the horizontal cousin of tools/make_water_frames.py. Rows are displaced
sideways by a travelling sine, with the offset weighted toward the TOP of the
sprite so the base stays planted and only the fronds move. A uniform shift would
just look like the whole clump sliding.

As with the walk cycle, the frames are derived from the one approved sprite
rather than generated separately -- separate generations aren't frame-coherent
and would flicker.

    python3 tools/make_sway_frames.py --src assets/sprites/sw_06.png \\
        --prefix sea_kelp0 --amp 2
"""

import argparse
import math
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sprites")


def sway(img, phase, amp, anchor):
    w, h = img.size
    src = img.load()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dst = out.load()

    for y in range(h):
        # 1 at the top, 0 at the base -- `anchor` controls how much of the
        # bottom is held still.
        t = 1.0 - (y / max(1, h - 1))
        weight = max(0.0, (t - anchor) / max(1e-6, 1.0 - anchor))
        dx = int(round(amp * weight * math.sin(phase)))
        for x in range(w):
            sx = x - dx
            if 0 <= sx < w:
                dst[x, y] = src[sx, y]
    return out


def build(src_path, prefix, frames, amp, anchor):
    img = Image.open(src_path).convert("RGBA")
    os.makedirs(OUT, exist_ok=True)
    for f in range(frames):
        phase = 2.0 * math.pi * f / frames
        sway(img, phase, amp, anchor).save(
            os.path.join(OUT, f"{prefix}_f{f}.png"))
    print(f"  {prefix}_f0..f{frames-1}.png  {img.size[0]}x{img.size[1]}  amp {amp}px")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", required=True)
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--frames", type=int, default=4)
    ap.add_argument("--amp", type=float, default=1.0,
                    help="Peak horizontal displacement in pixels")
    ap.add_argument("--anchor", type=float, default=0.35,
                    help="Fraction of the sprite held still at the base")
    a = ap.parse_args()
    src = a.src if os.path.isabs(a.src) else os.path.join(ROOT, a.src)
    build(src, a.prefix, a.frames, a.amp, a.anchor)


if __name__ == "__main__":
    main()
