"""Generate a green wax seal from the burgundy original.

Strategy: hue-rotate the wax pixels (not the white background) toward green.
We start from Sello-transparente.png (already has alpha) and shift hues.
"""
from PIL import Image
import colorsys

src = "Sello-transparente.png"
dst = "Sello-verde.png"

img = Image.open(src).convert("RGBA")
w, h = img.size
px = img.load()

# Burgundy is around hue ~0 (red). Green olive is around hue ~70-80/360 in HSV.
# Shift hue from red (~0) → olive (~75deg in 360 = ~0.21 in [0..1]).
# We also slightly de-saturate since olive is less vivid than burgundy red.

for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        if a == 0:
            continue
        # Convert to HSV (0..1)
        rr, gg, bb = r / 255.0, g / 255.0, b / 255.0
        hsv_h, hsv_s, hsv_v = colorsys.rgb_to_hsv(rr, gg, bb)
        # Original wax is red/burgundy: hue ~0.95-0.05 (wraps 360->0).
        # Shift to olive green ~0.20 (72deg).
        # Add 0.21 then wrap.
        new_h = (hsv_h + 0.21) % 1.0
        # Slightly reduce saturation for olive feel (warm muted green)
        new_s = max(0, min(1, hsv_s * 0.85))
        # Keep value roughly the same — preserves the embossed lighting
        new_v = hsv_v
        nr, ng, nb = colorsys.hsv_to_rgb(new_h, new_s, new_v)
        px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)

img.save(dst, "PNG")
print(f"saved {dst} ({img.size})")
