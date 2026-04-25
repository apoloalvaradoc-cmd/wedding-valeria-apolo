"""Remove white background from logo PNG and save as alpha-transparent."""
from PIL import Image

src = "logo-va.png"
dst = "logo-va-transparente.png"

img = Image.open(src).convert("RGBA")
data = img.getdata()
out = []
for r, g, b, a in data:
    mx, mn = max(r, g, b), min(r, g, b)
    sat = (mx - mn)
    # Pure white-ish (high luminance, low saturation)
    if mx >= 235 and sat <= 15:
        out.append((255, 255, 255, 0))
    elif mx >= 215 and sat <= 25:
        # Soft alpha for edges (anti-aliased fade)
        new_a = int(a * (1.0 - (mx - 215) / 20.0))
        new_a = max(0, min(a, new_a))
        out.append((r, g, b, new_a))
    else:
        out.append((r, g, b, a))

img.putdata(out)
img.save(dst, "PNG")
print(f"saved {dst} ({img.size})")
