#!/usr/bin/env python3
"""
Slices a generated sprite sheet into individual game-ready PNGs.

Unlike a fixed grid cut, this FINDS each sprite by looking for islands of
non-background pixels. Generated sheets never space their subjects evenly, and a
grid cut ends up clipping limbs and centring things badly.

It also preserves each sprite's aspect ratio. The player's five states are not
all square -- the tractor is wide, the hopper is tall -- so each is scaled to fit
inside its target box and centred, rather than squashed to fill it.

    python3 tools/slice_sheet.py --src raw/player_sheet.jpg --prefix player \\
        --sizes 16x16,16x16,16x20,20x20,20x28

    # same size for every sprite, 3x3 grid of seaweed
    python3 tools/slice_sheet.py --src raw/seaweed.png --prefix seaweed \\
        --sizes 16x16 --rows 3
"""

import argparse
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sprites")


def is_background(p):
    """Flat magenta key, including the darker magenta of a drop shadow."""
    r, g, b = p[0], p[1], p[2]
    return r > 90 and b > 90 and g < r * 0.62 and g < b * 0.62


def mask_of(img):
    """Alpha mask, keying ONLY background connected to the image border.

    A pure colour test is not enough: a hot pink hawaiian shirt is close enough
    to the magenta key that pixels inside the character get cut out, leaving
    holes in the sprite. Since every subject is enclosed by its own black
    outline, background reachable from the edge is the real background and
    anything walled off inside a figure is not, whatever colour it happens to be.
    """
    a = np.asarray(img.convert("RGB")).astype(np.int16)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    candidate = (r > 90) & (b > 90) & (g < r * 0.62) & (g < b * 0.62)

    labels, n = ndimage.label(candidate)
    if n == 0:
        return Image.fromarray(np.full(candidate.shape, 255, np.uint8), "L")

    edge = np.concatenate([labels[0, :], labels[-1, :], labels[:, 0], labels[:, -1]])
    outside = np.unique(edge[edge > 0])

    bg = np.isin(labels, outside)
    return Image.fromarray(np.where(bg, 0, 255).astype(np.uint8), "L")


def spans(profile, threshold, gap, min_len=0):
    """Turn a 1-D occupancy profile into (start, end) runs, merging small gaps.

    `min_len` discards specks -- a drop shadow fragment or a stray pixel would
    otherwise register as its own sprite and throw the whole grid out.
    """
    runs, start = [], None
    for i, v in enumerate(profile):
        if v > threshold and start is None:
            start = i
        elif v <= threshold and start is not None:
            runs.append([start, i])
            start = None
    if start is not None:
        runs.append([start, len(profile)])

    merged = []
    for r in runs:
        if merged and r[0] - merged[-1][1] < gap:
            merged[-1][1] = r[1]
        else:
            merged.append(r)
    return [r for r in merged if (r[1] - r[0]) >= min_len]


def parse_sizes(text, count):
    out = []
    for part in text.split(","):
        w, h = part.lower().split("x")
        out.append((int(w), int(h)))
    if len(out) == 1:
        out = out * count
    return out


def _close_pinholes(img, max_px=6):
    """Fill tiny enclosed transparent specks left by the alpha threshold.

    Downscaling then hard-thresholding can punch a stray hole through a solid
    area. Anything transparent, walled off from the border and smaller than
    `max_px` is a threshold artefact, not a real gap.
    """
    arr = np.array(img)
    clear = arr[:, :, 3] == 0
    labels, n = ndimage.label(clear)
    if n == 0:
        return img
    edge = np.concatenate([labels[0, :], labels[-1, :], labels[:, 0], labels[:, -1]])
    outside = np.unique(edge[edge > 0])

    for idx in range(1, n + 1):
        if idx in outside:
            continue
        sel = labels == idx
        if sel.sum() > max_px:
            continue
        # Borrow colour from the surrounding pixels rather than inventing one.
        grown = ndimage.binary_dilation(sel) & ~sel & (arr[:, :, 3] > 0)
        if not grown.any():
            continue
        arr[sel, 0:3] = arr[grown][:, 0:3].mean(axis=0).astype(np.uint8)
        arr[sel, 3] = 255
    return Image.fromarray(arr, "RGBA")


def fit(sprite, target):
    """Scale to fit inside target preserving aspect, then centre on transparent."""
    tw, th = target
    sw, sh = sprite.size
    k = min(tw / sw, th / sh)
    nw, nh = max(1, int(round(sw * k))), max(1, int(round(sh * k)))
    small = sprite.resize((nw, nh), Image.Resampling.BOX)

    # Hard alpha: a generated edge fades out, and a faded edge at 16px is fringe.
    a = small.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    small.putalpha(a)
    small = _close_pinholes(small)

    canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    canvas.paste(small, ((tw - nw) // 2, (th - nh) // 2))
    return canvas


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", required=True)
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--sizes", required=True,
                    help="One WxH, or a comma list one per sprite in reading order")
    ap.add_argument("--rows", type=int, default=1)
    ap.add_argument("--gap", type=int, default=12,
                    help="Columns closer than this are treated as one sprite")
    ap.add_argument("--row-gap", type=int, default=None,
                    help="Same for rows. Defaults to 2x --gap, but a sheet whose "
                         "figures have wide internal gaps (a raised arm, a "
                         "splayed stride) needs a LARGE column gap and a SMALL "
                         "row gap, or the two rows merge into one.")
    a = ap.parse_args()

    src_path = a.src if os.path.isabs(a.src) else os.path.join(ROOT, a.src)
    img = Image.open(src_path).convert("RGBA")
    w, h = img.size

    m = mask_of(img.convert("RGB"))
    mp = m.load()

    row_bounds = [(0, h)]
    if a.rows > 1:
        rowprof = [sum(mp[x, y] > 0 for x in range(w)) for y in range(h)]
        rg = a.row_gap if a.row_gap is not None else a.gap * 2
        row_bounds = [tuple(r) for r in spans(rowprof, 0, rg, int(h * 0.04))]

    # Alpha comes from the same mask, so the magenta key and its shadow both go.
    rgba = img.copy()
    rgba.putalpha(m)

    boxes = []
    for (y0, y1) in row_bounds:
        colprof = [sum(mp[x, y] > 0 for y in range(y0, y1)) for x in range(w)]
        for (x0, x1) in spans(colprof, 0, a.gap, int(w * 0.04)):
            sub = rgba.crop((x0, y0, x1, y1))
            bb = sub.getchannel("A").getbbox()
            if bb is None:
                continue
            boxes.append(sub.crop(bb))

    sizes = parse_sizes(a.sizes, len(boxes))
    if len(sizes) != len(boxes):
        print(f"WARNING: found {len(boxes)} sprites but got {len(sizes)} sizes")
        sizes = (sizes + [sizes[-1]] * len(boxes))[:len(boxes)]

    os.makedirs(OUT, exist_ok=True)
    print(f"Found {len(boxes)} sprites in {os.path.basename(src_path)}")
    for i, (sprite, target) in enumerate(zip(boxes, sizes)):
        out = fit(sprite, target)
        path = os.path.join(OUT, f"{a.prefix}_{i:02d}.png")
        out.save(path)
        print(f"  {a.prefix}_{i:02d}.png  source {sprite.size[0]}x{sprite.size[1]}"
              f"  ->  {target[0]}x{target[1]}")


if __name__ == "__main__":
    main()
