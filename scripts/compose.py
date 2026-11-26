"""Places each transparent island capture on a quiet backdrop with a menu bar, cropped to the island."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

raw, out = Path(sys.argv[1]), Path(sys.argv[2])
frames = "--frames" in sys.argv  # a recording: one fixed crop for every frame, so nothing jumps
MENU_BAR = 74  # 37pt at 2x, the height of a notched MacBook's menu bar


def backdrop(width, height):
    top, bottom = (24, 22, 52), (58, 38, 92)
    image = Image.new("RGB", (width, height))
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / max(height - 1, 1)
        draw.line([(0, y), (width, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    glow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([width * 0.2, height * 0.55, width * 0.8, height * 1.4], fill=(255, 140, 90, 70))
    image.paste(glow.filter(ImageFilter.GaussianBlur(120)), (0, 0), glow.filter(ImageFilter.GaussianBlur(120)))
    bar = Image.new("RGBA", (width, MENU_BAR), (12, 10, 22, 215))
    image.paste(bar, (0, 0), bar)
    return image


captures = sorted(raw.glob("*.png"))
fixed_box = None
if frames:
    boxes = [Image.open(c).getbbox() for c in captures[::10]]
    boxes = [b for b in boxes if b]
    fixed_box = (min(b[0] for b in boxes), 0, max(b[2] for b in boxes), max(b[3] for b in boxes))
background = None

for capture in captures:
    island = Image.open(capture).convert("RGBA")
    box = fixed_box or island.getbbox() or (0, 0, island.width, island.height)
    small = not frames and box[3] - box[1] < 120  # the closed island: frame it tighter
    margin_x, margin_bottom = (90, 60) if small else (120, 110)
    left, right = max(box[0] - margin_x, 0), min(box[2] + margin_x, island.width)
    bottom = min(box[3] + margin_bottom, island.height)
    if background is None or background.size != island.size:
        background = backdrop(island.width, island.height)
    canvas = background.copy()
    canvas.paste(island, (0, 0), island)
    canvas.crop((left, 0, right, max(bottom, MENU_BAR + (80 if small else 200)))).save(out / capture.name, optimize=True)


# A recording arrives as frames at irregular times. Lay them on an even 30fps timeline,
# holding each frame until the next one, so pauses in the tour stay pauses in the video.
if frames and (raw / "times.txt").exists():
    lines = (raw / "times.txt").read_text().split()
    end = float(lines[lines.index("end") + 1])
    times = [float(t) for t in lines[: lines.index("end")]]
    composed = sorted(p for p in out.glob("*.png"))
    timeline = out / "timeline"
    timeline.mkdir(exist_ok=True)
    frame, slot = 0, 0
    while slot / 30 < end:
        while frame + 1 < len(times) and times[frame + 1] <= slot / 30:
            frame += 1
        (timeline / f"{slot:05d}.png").write_bytes(composed[frame].read_bytes())
        slot += 1
