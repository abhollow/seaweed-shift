#!/usr/bin/env python3
"""
Builds a looping water animation out of a static background.

Generating wave frames with an image model would not work: separate generations
are not frame-coherent, so the scene, the palette and the foam would all jitter
between frames. Instead this displaces rows of the EXISTING art vertically with
a travelling sine, which is the technique old console games used and is coherent
by construction.

Only the strip from --water-top down is exported, so the frames stay small and
nothing above the shoreline can move. The amplitude fades to zero at the top of
the strip, so it blends into the static sand with no seam.

Re-run whenever the source background changes, or the waves will be displacing
rows of the OLD art and will not match what is on screen.

    # in-game beach, full 360x640 resolution
    python3 tools/make_water_frames.py --src raw/background_level1.png \\
        --prefix water --width 360 --height 640 --water-top 390

    # title screen, deliberately chunkier at half resolution
    python3 tools/make_water_frames.py --src raw/menu_source_fitted.png \\
        --prefix menu_water --width 180 --height 320 --water-top 196
"""

import argparse
import math
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sprites")


def build(src_path, prefix, gw, gh, water_top, frames, amp_shore, amp_deep, fade):
    src = Image.open(src_path).convert("RGB")
    sw, sh = src.size
    scale = sh / gh
    top = int(water_top * scale)
    strip_h = sh - top
    px = src.load()

    out_h = gh - water_top
    os.makedirs(OUT, exist_ok=True)

    # Amplitudes are given in output pixels; convert to source pixels so the
    # motion looks the same regardless of what resolution the art came in at.
    a_shore = amp_shore * scale
    a_deep = amp_deep * scale

    for f in range(frames):
        phase = 2.0 * math.pi * f / frames
        frame = Image.new("RGB", (sw, strip_h))
        fp = frame.load()

        for row in range(strip_h):
            t = row / strip_h

            # Ramp in from zero so the top edge matches the static art exactly,
            # then ease off with depth -- the shore laps, the deep just swells.
            ramp = min(1.0, t / fade)
            amp = ramp * (a_shore + (a_deep - a_shore) * t)

            # Two components so it doesn't read as one mechanical sine.
            y_src = row + top + amp * (
                0.70 * math.sin(phase + row * 0.011)
                + 0.30 * math.sin(2.0 * phase + row * 0.027 + 1.3)
            )

            # Clamp rather than wrap: wrapping would drag deep water onto sand.
            a = max(top, min(sh - 1, int(y_src)))
            for x in range(sw):
                fp[x, row] = px[x, a]

        small = frame.resize((gw, out_h), Image.Resampling.BOX)
        path = os.path.join(OUT, f"{prefix}_{f:02d}.png")
        small.save(path)
        print(f"  {prefix}_{f:02d}.png  {gw}x{out_h}  {os.path.getsize(path)/1024:.0f} KB")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", required=True)
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--width", type=int, required=True)
    ap.add_argument("--height", type=int, required=True)
    ap.add_argument("--water-top", type=int, required=True,
                    help="In OUTPUT pixels; a little above the foam line")
    ap.add_argument("--frames", type=int, default=8)
    ap.add_argument("--amp-shore", type=float, default=2.8,
                    help="Output-pixel displacement at the shoreline")
    ap.add_argument("--amp-deep", type=float, default=1.3)
    ap.add_argument("--fade", type=float, default=0.12,
                    help="Fraction of the strip over which amplitude ramps in")
    a = ap.parse_args()

    src = a.src if os.path.isabs(a.src) else os.path.join(ROOT, a.src)
    print(f"Building {a.frames} frames from {os.path.basename(src)}...")
    build(src, a.prefix, a.width, a.height, a.water_top,
          a.frames, a.amp_shore, a.amp_deep, a.fade)
    print(f"\nStrip sits at y={a.water_top}, {a.height - a.water_top}px tall.")


if __name__ == "__main__":
    main()
