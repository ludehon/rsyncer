#!/usr/bin/env python3
"""Normalise artwork/icon.png into the shape macOS expects.

    python3 scripts/normalize-icon.py

macOS 26 only treats artwork as an app icon if its silhouette is a clean,
square rounded rectangle. Anything else -- a shape that is wider than it is
tall, or one with a soft irregular edge -- is not recognised, and the system
falls back to pasting the artwork onto a generic light plate at ~60% size.

artwork/icon.png is drawn 1126x1084 (about 4% wider than tall), which trips
that fallback. This rewrites it as artwork/icon-normalized.png:

  1. extend the background out to the edges, discarding the baked-in shape
  2. re-mask with a clean, square rounded rectangle

Keeping a rounded alpha (rather than going full-bleed) matters for the
deployment target: macOS 14/15 do not mask icons themselves, so full-bleed
artwork would render there with hard square corners.

Requires Pillow and numpy. Run scripts/generate-icon.swift afterwards.
"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC = sys.argv[1] if len(sys.argv) > 1 else 'artwork/icon.png'
DST = sys.argv[2] if len(sys.argv) > 2 else 'artwork/icon-normalized.png'

BODY_RATIO = 0.834   # icon body as a fraction of the canvas, leaving room for the shadow
RADIUS = 0.28        # corner radius as a fraction of the body, matching the drawn artwork
ERODE_PX = 32        # enough to clear the bright rim on the baked-in rounded rect
GLYPH_R = 90         # background is deep blue (low red); the glyph is white (high red)

im = Image.open(SRC).convert('RGBA')
CANVAS = im.size[0]
alpha = np.array(im)[:, :, 3]

# 1. Square crop centred on the solid body, discarding the soft drop shadow.
ys, xs = np.nonzero(alpha > 250)
cy, cx = (ys.min() + ys.max()) / 2, (xs.min() + xs.max()) / 2
side = max(xs.max() - xs.min(), ys.max() - ys.min()) + 1
L, T = int(round(cx - side / 2)), int(round(cy - side / 2))
im = im.crop((L, T, L + side, T + side))
src = np.array(im)[:, :, :3].astype(np.float32)
print(f'body {xs.max()-xs.min()+1}x{ys.max()-ys.min()+1} -> square crop {side}px')

# 2. Erode well past the rim so only clean interior seeds the fill, and seed
#    from background pixels only so the glyph never smears outward.
m = Image.fromarray(((np.array(im)[:, :, 3] > 250) * 255).astype(np.uint8))
for _ in range(ERODE_PX // 4):
    m = m.filter(ImageFilter.MinFilter(9))
interior = np.array(m) > 127
known = interior & (src[:, :, 0] < GLYPH_R)
rgb = np.where(known[:, :, None], src, 0).astype(np.float32)

# 3. Grow the background outward until it covers the whole square.
while not known.all():
    k = known.astype(np.float32)
    acc = np.zeros_like(rgb)
    cnt = np.zeros_like(k)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy or dx:
                acc += np.roll(np.roll(rgb, dy, 0), dx, 1)
                cnt += np.roll(np.roll(k, dy, 0), dx, 1)
    new = (~known) & (cnt > 0)
    if not new.any():
        break
    rgb[new] = acc[new] / cnt[new][:, None]
    known |= new

# 4. Drop the original artwork back over the extended background.
blend = np.array(Image.fromarray((interior * 255).astype(np.uint8))
                 .filter(ImageFilter.GaussianBlur(6))).astype(np.float32)[:, :, None] / 255.0
flat = Image.fromarray(np.clip(src * blend + rgb * (1 - blend), 0, 255).astype(np.uint8))

# 5. Re-mask with a clean, square rounded rectangle (supersampled for smooth edges).
body = int(round(CANVAS * BODY_RATIO))
off = (CANVAS - body) / 2
SS = 4
big = Image.new('L', (CANVAS * SS, CANVAS * SS), 0)
ImageDraw.Draw(big).rounded_rectangle(
    [off * SS, off * SS, (off + body) * SS, (off + body) * SS],
    radius=RADIUS * body * SS, fill=255)

out = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))
out.paste(flat.resize((body, body), Image.LANCZOS), (int(off), int(off)))
out.putalpha(big.resize((CANVAS, CANVAS), Image.LANCZOS))
out.save(DST)

a = np.array(out)[:, :, 3]
ys, xs = np.nonzero(a > 250)
w, h = xs.max() - xs.min() + 1, ys.max() - ys.min() + 1
print(f'wrote {DST}: body {w}x{h}, aspect {h/w:.3f}')
