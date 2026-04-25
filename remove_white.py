from PIL import Image
import sys

src = "Sello invitación.png"
dst = "Sello-transparente.png"

img = Image.open(src).convert("RGBA")
data = img.getdata()
out = []
for r, g, b, a in data:
    # Treat near-white pixels as transparent.
    # Compute brightness; if very bright AND low saturation → transparent.
    mx, mn = max(r, g, b), min(r, g, b)
    sat = (mx - mn)
    if mx >= 235 and sat <= 12:
        out.append((255, 255, 255, 0))
    else:
        # Soft alpha around the edge: scale alpha based on how white-ish the pixel is
        if mx >= 215 and sat <= 25:
            # Edge softening — fade from opaque to transparent
            new_a = int(a * (1.0 - (mx - 215) / 20.0) * (1.0 - (25 - sat) / 25.0 * 0.3))
            new_a = max(0, min(a, new_a))
            out.append((r, g, b, new_a))
        else:
            out.append((r, g, b, a))

img.putdata(out)
img.save(dst, "PNG")
print(f"saved {dst} ({img.size})")
