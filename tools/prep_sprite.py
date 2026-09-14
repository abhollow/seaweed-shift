#!/usr/bin/env python3
"""
Turns AI-generated "pixel art" into actual pixel art the game can use.

Image models don't produce pixel art -- they produce a high-resolution painting
OF pixel art: soft anti-aliased edges, a pixel grid that drifts and isn't quite
square, and hundreds of near-duplicate colours. Dropped into the game at 24x24
that reads as a blurry smudge, not a sprite.

This does the four steps that fix it:

  1. trim      crop away empty margin so the subject fills the frame
  2. downscale box-average to the target size (area mean, not bilinear)
  3. quantize  snap every colour to a fixed palette
  4. harden    threshold alpha so edges are on/off, never feathered

Step 3 is the one people skip, and it's why AI pixel art usually looks mushy.

Examples
--------
Single sprite:
    python3 tools/prep_sprite.py raw/tractor.png -o assets/tractor.png -s 32x32

A 4-across sheet of player states, sliced and processed in one pass:
    python3 tools/prep_sprite.py raw/player_sheet.png -o assets/player -s 24x24 --cols 4

Keep the generated colours instead of snapping to the palette:
    python3 tools/prep_sprite.py raw/x.png -o out.png -s 32x32 --no-quantize
"""

import argparse
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required:  pip install Pillow")


DEFAULT_PALETTE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "palette.txt")


def load_palette(path):
    colors = []
    with open(path) as f:
        for line in f:
            line = line.split("#", 1)[0].strip() if not line.strip().startswith("#") else line.strip()
            if line.startswith("#"):
                line = line[1:].strip()
            if not line:
                continue
            token = line.split()[0].lstrip("#")
            if len(token) != 6:
                continue
            colors.append(tuple(int(token[i:i + 2], 16) for i in (0, 2, 4)))
    if not colors:
        sys.exit(f"No colours found in {path}")
    if len(colors) > 256:
        sys.exit("Palette is capped at 256 colours")
    return colors


def palette_image(colors):
    # Pillow wants a P-mode image carrying the palette. Unused slots are padded
    # with the first colour so quantize() can never pick something off-palette.
    pal = Image.new("P", (1, 1))
    flat = []
    for c in colors:
        flat.extend(c)
    flat.extend(colors[0] * (256 - len(colors)))
    pal.putpalette(flat)
    return pal


def trim(img, alpha_floor=8):
    """Crop to the subject. Uses alpha when present, otherwise the corner colour."""
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    alpha = img.getchannel("A")

    if alpha.getextrema()[0] < 255:
        box = alpha.point(lambda v: 255 if v > alpha_floor else 0).getbbox()
    else:
        # Fully opaque: assume the top-left pixel is background.
        bg = img.getpixel((0, 0))
        mask = Image.new("L", img.size, 0)
        px = img.load()
        mp = mask.load()
        w, h = img.size
        for y in range(h):
            for x in range(w):
                r, g, b, _ = px[x, y]
                if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) > 30:
                    mp[x, y] = 255
        box = mask.getbbox()

    return img.crop(box) if box else img


def fit_square(img):
    """Pad to a square so the downscale doesn't distort the aspect ratio."""
    w, h = img.size
    if w == h:
        return img
    side = max(w, h)
    out = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    out.paste(img, ((side - w) // 2, (side - h) // 2))
    return out


def downscale(img, size):
    # BOX is an area average: every output pixel is the mean of an exact block
    # of input pixels. LANCZOS/BICUBIC would ring and add halo colours, which is
    # the last thing a 24px sprite needs.
    return img.resize(size, Image.Resampling.BOX)


def quantize(img, colors):
    rgb = img.convert("RGB")
    pal = palette_image(colors)
    # dither=NONE is essential -- dithering scatters checkerboard noise that
    # looks like detail at 1024px and like dirt at 24px.
    snapped = rgb.quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB")
    out = snapped.convert("RGBA")
    out.putalpha(img.getchannel("A"))
    return out


def harden_alpha(img, threshold):
    a = img.getchannel("A").point(lambda v: 255 if v >= threshold else 0)
    img.putalpha(a)
    return img


def count_colors(img):
    # getcolors() returns None past its cap, which an un-quantized background
    # will always blow through. Ask for the full 24-bit space.
    got = img.convert("RGB").getcolors(1 << 24)
    return len(got) if got else "many"


def process(img, args, colors):
    if not args.no_trim:
        img = trim(img)
    if not args.no_square:
        img = fit_square(img)
    img = downscale(img, args.size)
    if not args.no_quantize:
        img = quantize(img, colors)
    img = harden_alpha(img, args.alpha_threshold)
    return img


def parse_size(text):
    try:
        w, h = text.lower().split("x")
        return (int(w), int(h))
    except Exception:
        raise argparse.ArgumentTypeError("Size must look like 24x32")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("-o", "--output", required=True,
                    help="Output PNG, or output directory when slicing a sheet")
    ap.add_argument("-s", "--size", required=True, type=parse_size,
                    help="Target size, e.g. 24x24")
    ap.add_argument("--cols", type=int, default=1, help="Sheet columns to slice")
    ap.add_argument("--rows", type=int, default=1, help="Sheet rows to slice")
    ap.add_argument("--palette", default=DEFAULT_PALETTE)
    ap.add_argument("--alpha-threshold", type=int, default=128)
    ap.add_argument("--no-quantize", action="store_true")
    ap.add_argument("--no-trim", action="store_true")
    ap.add_argument("--no-square", action="store_true",
                    help="Skip square padding (use for non-square subjects already framed)")
    args = ap.parse_args()

    colors = [] if args.no_quantize else load_palette(args.palette)
    src = Image.open(args.input).convert("RGBA")

    if args.cols == 1 and args.rows == 1:
        out = process(src, args, colors)
        os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
        out.save(args.output)
        print(f"{args.input} -> {args.output}  {out.size[0]}x{out.size[1]}  "
              f"{count_colors(out)} colours")
        return

    os.makedirs(args.output, exist_ok=True)
    cw = src.width // args.cols
    ch = src.height // args.rows
    n = 0
    for r in range(args.rows):
        for c in range(args.cols):
            cell = src.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
            out = process(cell, args, colors)
            name = f"{n:02d}.png"
            path = os.path.join(args.output, name)
            out.save(path)
            print(f"  cell {r},{c} -> {path}  {out.size[0]}x{out.size[1]}  "
                  f"{count_colors(out)} colours")
            n += 1
    print(f"Sliced {n} sprites into {args.output}/")


if __name__ == "__main__":
    main()
