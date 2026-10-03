#!/usr/bin/env python3
"""Lays the captured frames out for the README GIF.

* The simulator's boot and home screen are trimmed from both ends.
* Each frame becomes a phone, centred on a black square. The simulator always
  records the screen as the portrait panel, so while the device is on its side
  the app appears turned through 90°; those frames are turned upright, and the
  phone drawn on its side at the same size.
* The turns themselves become the phone rotating, in place of the sideways
  rotation animation the capture shows.
* A title card goes in at the start of each section of the walkthrough.

The walkthrough logs each turn and section with the time (DEMO-MARK lines).
Writes numbered frames and durations.json, their durations in milliseconds.

usage: compose-frames.py <raw frames> <out dir> <log> <capture start> <fps> <speedup> <size>
"""
import glob
import json
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont, ImageStat

# How long a turn of the device takes to settle after its mark.
SETTLE = 0.8
# The phone drawn turning, in place of the frames mid-turn.
TURN_STEPS = 6
TURN_STEP_MS = 60
CARD_MS = 5000

MARGIN = 20
BEZEL = 10
BODY = (26, 26, 28)
EDGE = (78, 78, 82)

FONT = "/System/Library/Fonts/SFNS.ttf"
AMBER = (245, 115, 23)
TITLE = (240, 240, 236)
COPY = (165, 165, 170)


# MARK: - Marks

def read_marks(log_path: str):
    """Landscape spans as (turned, turned back), and sections as (time, title, copy)."""
    turns, sections = [], []
    for line in open(log_path, encoding="utf-8", errors="replace"):
        turn = re.search(r"DEMO-MARK (landscape|portrait) ([0-9.]+)", line)
        section = re.search(r"DEMO-MARK section ([0-9.]+) (.+?) \| (.+?)\s*$", line)
        if turn:
            turns.append((turn.group(1), float(turn.group(2))))
        elif section:
            sections.append((float(section.group(1)), section.group(2), section.group(3)))

    spans, start = [], None
    for name, at in sorted(turns, key=lambda mark: mark[1]):
        if name == "landscape" and start is None:
            start = at
        elif name == "portrait" and start is not None:
            spans.append((start, at))
            start = None
    return spans, sorted(sections)


# MARK: - Trimming

def is_home_screen(frame: Image.Image) -> bool:
    """The springboard is bright and colourful; the app is dark and grey."""
    saturation = ImageStat.Stat(frame.convert("HSV")).mean[1]
    brightness = sum(ImageStat.Stat(frame).mean) / 3
    return saturation > 80 and brightness > 120


def app_range(raw: list) -> range:
    """Leaves out the boot and home screen before the app, and the home screen after."""
    half = len(raw) // 2
    home = [is_home_screen(frame) for frame in raw]

    leading = [i for i in range(half) if home[i]]
    start = leading[-1] + 1 if leading else 0
    # The launch: the zoom out of the home screen, still colourful, then the
    # near-black launch screen.
    while start < len(raw):
        saturation = ImageStat.Stat(raw[start].convert("HSV")).mean[1]
        brightness = sum(ImageStat.Stat(raw[start]).mean) / 3
        if saturation <= 60 and brightness >= 15:
            break
        start += 1

    trailing = [i for i in range(half, len(raw)) if home[i]]
    return range(start, trailing[0] if trailing else len(raw))


# MARK: - Drawing

def phone(screen: Image.Image, length: int) -> Image.Image:
    """The screen in a phone body, its long side `length` long."""
    inner = length - 2 * BEZEL
    scale = inner / max(screen.size)
    screen = screen.resize((round(screen.width * scale), round(screen.height * scale)), Image.Resampling.LANCZOS)
    radius = round(min(screen.size) * 0.13)

    mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, screen.width - 1, screen.height - 1), radius=radius, fill=255)

    body = Image.new("RGBA", (screen.width + 2 * BEZEL, screen.height + 2 * BEZEL), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle(
        (0, 0, body.width - 1, body.height - 1), radius=radius + BEZEL, fill=BODY, outline=EDGE, width=2,
    )
    body.paste(screen, (BEZEL, BEZEL), mask)
    return body


def on_square(image: Image.Image, size: int) -> Image.Image:
    canvas = Image.new("RGB", (size, size), (0, 0, 0))
    canvas.paste(image, ((size - image.width) // 2, (size - image.height) // 2), image)
    return canvas


def font(size: int, weight: str) -> ImageFont.FreeTypeFont:
    face = ImageFont.truetype(FONT, size)
    try:
        face.set_variation_by_name(weight)
    except (OSError, ValueError):
        pass
    return face


def card(title: str, copy: str, size: int) -> Image.Image:
    """A title and a couple of lines about what's coming."""
    image = Image.new("RGB", (size, size), (0, 0, 0))
    draw = ImageDraw.Draw(image)
    left = round(size * 0.12)
    width = size - 2 * left

    title_font = font(round(size * 0.068), "Bold")
    copy_font = font(round(size * 0.04), "Regular")
    # Wrapped by measuring, since the copy font is proportional.
    lines, words = [], copy.split()
    while words:
        line = words.pop(0)
        while words and draw.textlength(f"{line} {words[0]}", font=copy_font) <= width:
            line += " " + words.pop(0)
        lines.append(line)

    title_height = title_font.size * 1.2
    line_height = copy_font.size * 1.45
    block = 6 + 24 + title_height + 18 + line_height * len(lines)
    y = (size - block) / 2

    draw.rectangle((left, y, left + 44, y + 5), fill=AMBER)
    y += 6 + 24
    draw.text((left, y), title, font=title_font, fill=TITLE)
    y += title_height + 18
    for line in lines:
        draw.text((left, y), line, font=copy_font, fill=COPY)
        y += line_height
    return image


# MARK: - Composing

def main(raw_dir, out_dir, log_path, capture_start, fps, speedup, size):
    files = sorted(glob.glob(os.path.join(raw_dir, "*.png")))
    if not files:
        raise SystemExit(f"no frames in {raw_dir}")
    raw = [Image.open(f).convert("RGB") for f in files]
    kept = app_range(raw)
    if not kept:
        raise SystemExit("no frames of the app in the capture")

    spans, sections = read_marks(log_path)
    spans = [(a - capture_start, b - capture_start) for a, b in spans]
    sections = [(t - capture_start, title, copy) for t, title, copy in sections]

    step = speedup / fps
    length = size - 2 * MARGIN
    frame_ms = round(1000 / fps)
    out = []
    turned = set()
    last = None  # The phone last shown, for drawing the next turn.

    for i in kept:
        t = int(re.search(r"(\d+)\.png$", files[i]).group(1)) * step

        while sections and sections[0][0] <= t:
            _, title, copy = sections.pop(0)
            out.append((card(title, copy, size), CARD_MS))

        mid_turn = next(((n, start, end) for n, (start, end) in enumerate(spans)
                         if start <= t < start + SETTLE or end <= t < end + SETTLE), None)
        if mid_turn:
            n, start, _ = mid_turn
            to_landscape = t < start + SETTLE
            key = (n, to_landscape)
            if key not in turned and last is not None:
                turned.add(key)
                # On to its side counter-clockwise, as for landscape left; back again clockwise.
                direction = 1 if to_landscape else -1
                for k in range(1, TURN_STEPS + 1):
                    angle = direction * 90 * k / TURN_STEPS
                    out.append((on_square(last.rotate(angle, expand=True, resample=Image.Resampling.BICUBIC), size), TURN_STEP_MS))
            continue

        landscape = any(start + SETTLE <= t < end for start, end in spans)
        screen = raw[i].rotate(90, expand=True) if landscape else raw[i]
        last = phone(screen, length)
        out.append((on_square(last, size), frame_ms))

    os.makedirs(out_dir, exist_ok=True)
    for n, (image, _) in enumerate(out):
        image.save(os.path.join(out_dir, f"{n:05d}.png"))
    with open(os.path.join(out_dir, "durations.json"), "w") as f:
        json.dump([ms for _, ms in out], f)

    cards = sum(1 for _, ms in out if ms == CARD_MS)
    print(f"{len(out)} frames: {len(spans)} landscape stretches, {cards} title cards")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]),
         float(sys.argv[5]), float(sys.argv[6]), int(sys.argv[7]))
