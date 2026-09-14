#!/usr/bin/env python3
"""
Builds a walk cycle out of a single static sprite.

Asking an image model for animation frames does not work: separate generations
are not frame-coherent, so the character's proportions and palette drift between
frames and the result flickers. Instead this derives frames from the ONE sprite
that was approved, which is coherent by construction and free.

Two classic tricks, combined:

  * mirror the leg region horizontally, which swaps which foot is forward
  * bob the whole sprite up a pixel on alternate frames

At 24px that reads convincingly as walking. The bob is what sells it -- a leg
swap alone looks like a glitch, a bob alone looks like hovering.

Vehicles pass --legs 0 so only the bob applies; a tractor has no feet to shuffle
but should still rumble.

    python3 tools/make_walk_frames.py --src assets/sprites/player_00.png \\
        --prefix player_s0 --legs 0.34
"""

import argparse
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sprites")


def leg_band(img, frac):
    """Row range of the leg band, capped so it can never reach the torso."""
    h = img.size[1]
    frac = min(frac, 0.34)
    return h - max(2, int(round(h * frac))), h


def step_legs(img, frac, side, lift, spread=0):
    """Lift ONE leg, leaving the other planted.

    Operates only on a shallow band at the very bottom, and splits left from
    right at the CONTENT centroid of that band rather than the canvas centre --
    a sprite carrying a rake is not centred on its own body, so splitting at the
    canvas midpoint cuts the figure in the wrong place.

    Deliberately does NOT mirror anything. Mirroring a band flips whatever else
    sits in it: at any useful depth it flipped the torso, and on the rake states
    it produced a second rake on the wrong side.
    """
    if frac <= 0.0 or lift <= 0:
        return img.copy()
    w, h = img.size
    cut, _ = leg_band(img, frac)
    src = img.load()

    # Centroid of the opaque pixels in the band.
    xs = [x for y in range(cut, h) for x in range(w) if src[x, y][3] > 0]
    if not xs:
        return img.copy()
    cx = sum(xs) / len(xs)

    out = img.copy()
    dst = out.load()
    for y in range(cut, h):
        for x in range(w):
            dst[x, y] = (0, 0, 0, 0)
    for y in range(cut, h):
        for x in range(w):
            moving = (x < cx) == (side == "left")
            sy = y + lift if moving else y
            if cut <= sy < h:
                p = src[x, sy]
                if p[3] > 0:
                    dst[x, y] = p
    return out


def bob(img, dy):
    """Shift up by dy, leaving transparent at the bottom."""
    if dy == 0:
        return img.copy()
    w, h = img.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(img.crop((0, dy, w, h)), (0, 0))
    return out


def build(src_path, prefix, legs, bob_px, style, lift, spread, src2_path=None,
          pairs=False):
    img = Image.open(src_path).convert("RGBA")

    if pairs:
        # A-B cycle from two genuinely drawn poses: contact, then passing. No
        # pixel manipulation at all, which is the point -- every frame is art
        # somebody drew, so nothing can end up mirrored or duplicated.
        pose_b = Image.open(src2_path).convert("RGBA")
        if pose_b.size != img.size:
            canvas = Image.new("RGBA", img.size, (0, 0, 0, 0))
            canvas.paste(pose_b, ((img.size[0] - pose_b.size[0]) // 2,
                                  img.size[1] - pose_b.size[1]))
            pose_b = canvas
        frames = [img, pose_b]
    elif src2_path:
        # Two REAL drawn poses. Nothing beats this -- the pixel-shifting styles
        # below only exist for when a second pose isn't available.
        pose_b = Image.open(src2_path).convert("RGBA")
        if pose_b.size != img.size:
            canvas = Image.new("RGBA", img.size, (0, 0, 0, 0))
            canvas.paste(pose_b, ((img.size[0] - pose_b.size[0]) // 2,
                                  img.size[1] - pose_b.size[1]))
            pose_b = canvas
        frames = [img, bob(img, bob_px), pose_b, bob(pose_b, bob_px)]
    elif style == "step":
        # Front-facing: alternate which leg lifts.
        frames = [
            img,
            bob(step_legs(img, legs, "left", lift, spread), bob_px),
            img,
            bob(step_legs(img, legs, "right", lift, spread), bob_px),
        ]
    else:
        # Alternate which foot lifts, with a bob on the lifted frames.
        frames = [
            img,
            bob(step_legs(img, legs, "left", lift), bob_px),
            img,
            bob(step_legs(img, legs, "right", lift), bob_px),
        ]

    os.makedirs(OUT, exist_ok=True)
    for i, f in enumerate(frames):
        path = os.path.join(OUT, f"{prefix}_f{i}.png")
        f.save(path)
    print(f"  {prefix}_f0..f3.png  {img.size[0]}x{img.size[1]}"
          f"  style {'two-pose' if src2_path else style}  bob {bob_px}px")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", required=True)
    ap.add_argument("--src2", default=None,
                    help="Second drawn pose; when given, the two alternate with a bob")
    ap.add_argument("--pair", action="store_true",
                    help="Emit a bare two-frame A-B cycle from --src and --src2, "
                         "with no bob and no pixel manipulation")
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--legs", type=float, default=0.34,
                    help="Fraction of sprite height treated as legs; 0 disables")
    ap.add_argument("--bob", type=int, default=1,
                    help="Pixels to lift on alternate frames; raise for a heavier gait")
    ap.add_argument("--style", choices=["step"], default="step",
                    help="Only `step` remains; mirroring flipped torsos and tools")
    ap.add_argument("--lift", type=int, default=1,
                    help="Pixels a single leg lifts in step style")
    ap.add_argument("--spread", type=int, default=0,
                    help="Pixels the lifted leg swings outward; raises the stride")
    a = ap.parse_args()
    src = a.src if os.path.isabs(a.src) else os.path.join(ROOT, a.src)
    src2 = None
    if a.src2:
        src2 = a.src2 if os.path.isabs(a.src2) else os.path.join(ROOT, a.src2)
    build(src, a.prefix, a.legs, a.bob, a.style, a.lift, a.spread, src2, a.pair)


if __name__ == "__main__":
    main()
