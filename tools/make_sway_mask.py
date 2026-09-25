"""Mask of the parts of a background that should move in the wind.

    python3 tools/make_sway_mask.py --src assets/sprites/background_level2.png \\
        --out assets/sprites/sway_level2.png --below 96 --sky 56

Palms are painted into the background, so they cannot be animated as sprites.
Instead a shader shifts the pixels this mask marks sideways over time. White
means "sways fully", black "never moves"; the soft edge between them is what
stops the displacement leaving a visible seam.

Two kinds of pixel qualify:
  * palm-frond GREEN anywhere above --below (the town strip), defined as
    darker than the sky AND leaning green-over-blue. Not by saturation: the
    overcast Veracruz palms have almost none, and a saturation rule missed
    nearly all of them while grey sky sat right beside them.
  * any strongly coloured pixel above --sky -- kites and flag cloth, up where
    nothing else is saturated. Terracotta roofs sit lower and are excluded,
    which is why the colour rule is limited to the sky.
"""
import argparse

import numpy as np
from PIL import Image
from scipy import ndimage

ap = argparse.ArgumentParser()
ap.add_argument("--src", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--below", type=int, required=True, help="mask nothing below this row")
ap.add_argument("--sky", type=int, required=True, help="saturated colours count above this row")
ap.add_argument("--grow", type=int, default=2, help="pixels of room to swing into")
ap.add_argument("--soft", type=float, default=1.2, help="edge blur")
a = ap.parse_args()

im = np.asarray(Image.open(a.src).convert("RGB")).astype(np.float32)
h, w, _ = im.shape
r, g, b = im[..., 0], im[..., 1], im[..., 2]
sat = im.max(axis=2) - im.min(axis=2)
rows = np.arange(h)[:, None].repeat(w, axis=1)

lum = im.mean(axis=2)
sky_lum = float(np.median(lum[: max(4, h // 30)]))      # the top rows are sky
frond = (g > r + 5) & (g > b + 4) & (lum < sky_lum - 25) & (rows < a.below)
flag = (sat > 70) & (rows < a.sky)
mask = frond | flag
# room to swing into, then a soft falloff so there is no seam at the edge
mask = ndimage.binary_dilation(mask, iterations=a.grow)
soft = ndimage.gaussian_filter(mask.astype(np.float32), a.soft)
soft = np.clip(soft * 1.4, 0, 1)
soft[rows >= a.below] = 0.0
Image.fromarray((soft * 255).astype(np.uint8), "L").save(a.out)
print(f"{a.out}: {w}x{h}, {(soft > 0.05).mean()*100:.1f}% of the image sways")
