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

# Target burgundy hue (~341deg = 0.948 in [0..1]) — matches our --wine #6B1A2D
TARGET_HUE = 0.948

for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        if a == 0:
            continue
        rr, gg, bb = r/255, g/255, b/255
        h_, s_, v_ = colorsys.rgb_to_hsv(rr, gg, bb)
        # Shift hue to burgundy
        new_h = TARGET_HUE
        # Boost saturation if pixel is mostly desaturated cream
        new_s = max(s_, 0.55)
        # Darken value — cream is light, burgundy is dark, but preserve relative variation
        # Map v_ in [0,1] to roughly [0.05, 0.4] so embossing detail stays
        new_v = 0.05 + v_ * 0.40
        nr, ng, nb = colorsys.hsv_to_rgb(new_h, new_s, new_v)
        px[x, y] = (int(nr*255), int(ng*255), int(nb*255), a)

img.save(dst, "PNG")
print(f"saved {dst} ({img.size})")
