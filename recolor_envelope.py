"""Recolor the cream embossed envelope reference image to burgundy.

Source: e062e340-4b73-4457-a92a-bd08951c40de.png (cream envelope photo)
Output: Sobre-burgundy.png (same shape/embossed pattern, burgundy color)

Strategy: shift each pixel's hue toward burgundy while preserving its luminance,
so the embossed shadows stay visible (darker burgundy) and the paper highlights
become lighter burgundy. The original burgundy seal is kept (it'll be hidden
under the green seal overlay anyway).
"""
from PIL import Image
import colorsys

src = "e062e340-4b73-4457-a92a-bd08951c40de.png"
dst = "Sobre-burgundy.png"

img = Image.open(src).convert("RGBA")
w, h = img.size
px = img.load()

# Target #580410 HSV ≈ (0.976, 0.954, 0.345) — official wedding palette burgundy
TARGET_HUE = 0.976
TARGET_SAT = 0.95
# Map cream [0..1] V → burgundy [0.04 .. 0.345] preserving embossing variation
V_BASE = 0.04
V_RANGE = 0.30

for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        if a == 0:
            continue
        rr, gg, bb = r/255, g/255, b/255
        h_, s_, v_ = colorsys.rgb_to_hsv(rr, gg, bb)
        new_h = TARGET_HUE
        new_s = TARGET_SAT
        new_v = V_BASE + v_ * V_RANGE
        nr, ng, nb = colorsys.hsv_to_rgb(new_h, new_s, new_v)
        px[x, y] = (int(nr*255), int(ng*255), int(nb*255), a)

img.save(dst, "PNG")
print(f"saved {dst} ({img.size})")
