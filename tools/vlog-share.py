#!/usr/bin/env python3
"""vlog-share.py <slug> <runtime> <episode-no>

Builds images/vlog/<slug>-share.jpg (1200x630) from the episode poster:
big play button + "WATCH · runtime" chip, so link previews in iMessage /
Instagram / X read as a VIDEO, not a photo. og:image and twitter:image on
the episode page point at this file; the <video poster> stays clean.

  python3 tools/vlog-share.py nyc-poster-run 6:30 03
"""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
slug, runtime, ep = sys.argv[1], sys.argv[2], sys.argv[3]
W, H = 1200, 630
ACCENT = (255, 74, 23); INK = (16, 16, 16); WHITE = (255, 255, 255)

def font(name, size, index=0):
    for p in (f"/System/Library/Fonts/Supplemental/{name}", f"/System/Library/Fonts/{name}"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size, index=index)
    return ImageFont.load_default()

src = Image.open(f"{ROOT}/images/vlog/{slug}-poster.jpg").convert("RGB")
s = max(W / src.width, H / src.height)
src = src.resize((round(src.width * s), round(src.height * s)), Image.LANCZOS)
l, t = (src.width - W) // 2, (src.height - H) // 2
img = src.crop((l, t, l + W, t + H))

# darken edges so the button + chip read on any frame (day or night footage)
shade = Image.new("L", (W, H), 0)
d = ImageDraw.Draw(shade)
for y in range(H):
    d.line([(0, y), (W, y)], fill=int(40 + 110 * (y / H) ** 2))
img = Image.composite(Image.new("RGB", (W, H), INK), img, shade)

draw = ImageDraw.Draw(img, "RGBA")
# play button: soft shadow + solid accent disc + white triangle
cx, cy, r = W // 2, H // 2 - 10, 92
sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(sh).ellipse((cx - r, cy - r + 8, cx + r, cy + r + 8), fill=(0, 0, 0, 140))
img.paste(sh.filter(ImageFilter.GaussianBlur(18)), (0, 0), sh.filter(ImageFilter.GaussianBlur(18)))
draw = ImageDraw.Draw(img, "RGBA")
draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=ACCENT, outline=WHITE, width=5)
tri = r * 0.46
draw.polygon([(cx - tri * 0.62, cy - tri), (cx - tri * 0.62, cy + tri), (cx + tri * 1.02, cy)], fill=WHITE)

# bottom chip: ▶ WATCH · 6:30
mono = font("Menlo.ttc", 30, 1)
label = f"WATCH · {runtime}"
tw = draw.textlength(label, font=mono)
x0, y0, ph = 44, H - 44 - 60, 60
draw.rectangle((x0, y0, x0 + 56 + tw + 26, y0 + ph), fill=ACCENT)
draw.polygon([(x0 + 22, y0 + 18), (x0 + 22, y0 + ph - 18), (x0 + 44, y0 + ph / 2)], fill=WHITE)
draw.text((x0 + 56, y0 + ph / 2), label, font=mono, fill=WHITE, anchor="lm")

# top-left tag: CALVIN PRIICE — VLOG EP 03
tag = f"CALVIN PRIICE  ·  VLOG EP {ep}"
tf = font("Menlo.ttc", 24, 1)
tw2 = draw.textlength(tag, font=tf)
draw.rectangle((44, 40, 44 + tw2 + 32, 40 + 46), fill=INK)
draw.text((44 + 16, 40 + 23), tag, font=tf, fill=WHITE, anchor="lm")

out = f"{ROOT}/images/vlog/{slug}-share.jpg"
img.save(out, quality=85, optimize=True, progressive=True)
print(out, os.path.getsize(out) // 1024, "KB")
