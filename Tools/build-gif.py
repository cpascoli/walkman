#!/usr/bin/env python3
"""Assembles extracted frames into the README GIF.

Two things keep the file small enough to sit in a repo:

* every frame shares one palette, so the encoder can store only the pixels
  that changed between frames — a per-frame palette defeats that entirely;
* no dithering, because dither noise is incompressible and this UI is flat.

The palette is seeded with the app's accent colours. They cover very few
pixels, so median cut otherwise spends the whole palette on dark greys and
renders the amber as brown.
"""
import glob
import os
import sys

from PIL import Image

ACCENTS = [
    (245, 115, 23),    # amber
    (255, 82, 36),     # indicator lamp
    (230, 224, 212),   # cassette paper label
    (240, 240, 236),   # primary text
    (255, 69, 58),     # destructive red
    (10, 132, 255),    # keyboard blue
    (0, 0, 0),
    (255, 255, 255),
]
COLORS = 96
FRAME_MS = 125


def main(frame_dir: str, out_path: str) -> None:
    files = sorted(glob.glob(os.path.join(frame_dir, "*.png")))
    if not files:
        raise SystemExit(f"no frames in {frame_dir}")

    raw = [Image.open(f).convert("RGB") for f in files]
    width, height = raw[0].size

    swatch_h = 60
    swatch = Image.new("RGB", (width, swatch_h * len(ACCENTS)))
    for i, colour in enumerate(ACCENTS):
        swatch.paste(Image.new("RGB", (width, swatch_h), colour), (0, i * swatch_h))

    picks = list(range(0, len(raw), max(1, len(raw) // 6)))[:6]
    sample = Image.new("RGB", (width, height * len(picks) + swatch.height))
    for i, idx in enumerate(picks):
        sample.paste(raw[idx], (0, i * height))
    sample.paste(swatch, (0, height * len(picks)))

    base = sample.quantize(colors=COLORS, method=Image.MEDIANCUT)
    frames = [im.quantize(palette=base, dither=Image.NONE) for im in raw]

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    frames[0].save(
        out_path, save_all=True, append_images=frames[1:],
        duration=FRAME_MS, loop=0, optimize=True,
    )
    print(f"{len(frames)} frames, {os.path.getsize(out_path) / 1e6:.1f} MB")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
