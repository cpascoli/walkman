#!/usr/bin/env python3
"""Sets the landscape stretches of a capture upright.

The simulator always records the screen as the portrait panel, so while the
device is on its side the app appears turned through 90°. The walkthrough logs
each turn (DEMO-MARK lines, with the time); between a turn to landscape and the
turn back, frames are rotated upright and letterboxed into the portrait frame.
The frames mid-turn, which show the rotation animation sideways, are dropped.

usage: orient-frames.py <frames> <log> <capture start> <fps> <speedup>
"""
import glob
import os
import re
import sys

from PIL import Image, ImageDraw

# How long the rotation animation takes to settle after each mark.
SETTLE = 0.8
# Behind a landscape frame, the colour of the deck's well, and the outline of
# the phone around it, so it reads as the whole screen turned on its side.
BACKGROUND = (11, 11, 12)
BEZEL = (70, 70, 74)


def landscape_spans(log_path: str) -> list:
    """(turned, turned back) pairs, in seconds since the epoch."""
    marks = []
    for line in open(log_path, errors="replace"):
        match = re.search(r"DEMO-MARK (landscape|portrait) ([0-9.]+)", line)
        if match:
            marks.append((match.group(1), float(match.group(2))))

    spans, start = [], None
    for name, at in sorted(marks, key=lambda mark: mark[1]):
        if name == "landscape" and start is None:
            start = at
        elif name == "portrait" and start is not None:
            spans.append((start, at))
            start = None
    return spans


def upright(frame: Image.Image) -> Image.Image:
    width, height = frame.size
    margin = 6
    turned = frame.rotate(90, expand=True)
    inner = width - 2 * margin
    scaled = turned.resize((inner, round(turned.height * inner / turned.width)), Image.LANCZOS)

    # The screen's rounded corners, cut from the capture.
    radius = round(scaled.height * 0.12)
    mask = Image.new("L", scaled.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *scaled.size), radius=radius, fill=255)

    canvas = Image.new("RGB", (width, height), BACKGROUND)
    top = (height - scaled.height) // 2
    canvas.paste(scaled, (margin, top), mask)
    ImageDraw.Draw(canvas).rounded_rectangle(
        (margin - 3, top - 3, margin + scaled.width + 2, top + scaled.height + 2),
        radius=radius + 3, outline=BEZEL, width=2,
    )
    return canvas


def main(frame_dir: str, log_path: str, capture_start: float, fps: float, speedup: float) -> None:
    spans = [(a - capture_start, b - capture_start) for a, b in landscape_spans(log_path)]
    if not spans:
        print("no landscape marks; frames left as they are")
        return

    step = speedup / fps
    turned = dropped = 0
    for path in sorted(glob.glob(os.path.join(frame_dir, "*.png"))):
        index = int(re.search(r"(\d+)\.png$", path).group(1))
        t = index * step
        for start, end in spans:
            if start <= t < start + SETTLE or end <= t < end + SETTLE:
                os.remove(path)
                dropped += 1
                break
            if start + SETTLE <= t < end:
                upright(Image.open(path).convert("RGB")).save(path)
                turned += 1
                break
    print(f"{len(spans)} landscape stretches: {turned} frames set upright, {dropped} mid-turn dropped")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5]))
