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

# Target #75763E HSV ≈ (0.169, 0.475, 0.463) — official wedding palette olive
TARGET_HUE = 0.169

for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        if a == 0:
            continue
        rr, gg, bb = r / 255.0, g / 255.0, b / 255.0
        hsv_h, hsv_s, hsv_v = colorsys.rgb_to_hsv(rr, gg, bb)
        # Set hue directly to target olive (not just shift)
        new_h = TARGET_HUE
        # Reduce saturation toward olive's muted feel (~0.5)
        new_s = min(0.6, hsv_s * 0.55)
        # Slightly darken to match olive's value while preserving the embossed lighting variation
        new_v = hsv_v * 0.85
        nr, ng, nb = colorsys.hsv_to_rgb(new_h, new_s, new_v)
        px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)

img.save(dst, "PNG")
print(f"saved {dst} ({img.size})")
