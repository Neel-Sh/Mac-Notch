"""Rounds the corners of each staged capture and saves it as WebP: finish.py <captures-dir> <output-dir>"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

raw, out = Path(sys.argv[1]), Path(sys.argv[2])
RADIUS = 28  # pixels at 2x
SCALE = 4  # draw the corner mask larger, then shrink it, for a smooth edge

for capture in sorted(raw.glob("*.png")):
    image = Image.open(capture).convert("RGBA")
    mask = Image.new("L", (image.width * SCALE, image.height * SCALE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, mask.width - 1, mask.height - 1], RADIUS * SCALE, fill=255)
    image.putalpha(mask.resize(image.size, Image.LANCZOS))
    image.save(out / f"{capture.stem}.webp", quality=90, method=6)
