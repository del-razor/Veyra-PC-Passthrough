"""Placeholder OverRez artwork until the final logo is chosen.

Writes assets/overrez.ico (the program icon, all Windows sizes) and
qml/OverRez/logo.png (the in-app mark, 360x240 like the logo it replaces).
Swap these two files for the final logo; nothing else refers to the artwork.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FUCHSIA, CYAN = (255, 0, 170), (0, 229, 255)


def font(size):
    for path in (sys.argv[1] if len(sys.argv) > 1 else "",
                 "/usr/share/fonts/opentype/inter/InterDisplay-Black.otf",
                 "/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf",
                 r"C:\Windows\Fonts\segoeuib.ttf"):
        if path and Path(path).is_file():
            return ImageFont.truetype(path, size)
    raise SystemExit("no bold font found; pass one as the first argument")


def gradient(size):
    w, h = size
    g = Image.new("RGB", size)
    px = g.load()
    for y in range(h):
        for x in range(w):
            f = (x / max(1, w - 1) + y / max(1, h - 1)) / 2
            px[x, y] = tuple(int(a + (b - a) * f) for a, b in zip(FUCHSIA, CYAN))
    return g


def mark(size):
    """Rounded dark tile with a gradient OR monogram."""
    s = size * 4
    tile = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(tile).rounded_rectangle((0, 0, s - 1, s - 1), radius=s // 5, fill=(12, 10, 22, 255))
    border = Image.new("L", (s, s), 0)
    ImageDraw.Draw(border).rounded_rectangle((0, 0, s - 1, s - 1), radius=s // 5, outline=255, width=max(4, s // 28))
    tile.paste(gradient((s, s)), (0, 0), border)
    f = font(int(s * 0.5))
    d = ImageDraw.Draw(tile)
    box = d.textbbox((0, 0), "OR", font=f)
    w, h = box[2] - box[0], box[3] - box[1]
    text = Image.new("L", (w, h), 0)
    ImageDraw.Draw(text).text((-box[0], -box[1]), "OR", font=f, fill=255)
    tile.paste(gradient((w, h)), ((s - w) // 2, (s - h) // 2), text)
    return tile.resize((size, size), Image.LANCZOS)


big = mark(256)
big.save(ROOT / "assets/overrez.ico", sizes=[(n, n) for n in (16, 20, 24, 32, 40, 48, 64, 96, 128, 256)])
logo = Image.new("RGBA", (360, 240), (0, 0, 0, 0))
logo.paste(mark(200), (80, 20), mark(200))
(ROOT / "qml/OverRez").mkdir(exist_ok=True)
logo.save(ROOT / "qml/OverRez/logo.png")
print("wrote assets/overrez.ico and qml/OverRez/logo.png")
