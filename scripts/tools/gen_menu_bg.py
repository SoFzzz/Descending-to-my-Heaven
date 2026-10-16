"""Genera el fondo del menú principal (640x360, pixel art): assets/ui/menu/menu_sky.png
Paleta monocroma de Skin04 (Free PSX UI): negro, grises y un gris-lavanda muy apagado, con
pinceladas diagonales claras como las de las pantallas de Skin04, un resplandor tenue tras la isla
(mitad derecha) y dither Bayer 4x4. La isla se dibuja aparte, en 3D.
Uso: python scripts/tools/gen_menu_bg.py   (desde la raíz del proyecto; necesita Pillow)."""
import math
import random
from PIL import Image, ImageDraw

W, H = 640, 360
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
OUT = "assets/ui/menu/"
TOP, BOTTOM = (0x10, 0x0e, 0x16), (0x2c, 0x2a, 0x34)
GLOW_CENTER, GLOW_RADIUS, GLOW_COLOR = (480, 170), 240.0, (104, 100, 114)
STROKE_ANGLE = math.radians(-24)   # pinceladas que suben hacia la derecha, como en Skin04


def lerp(a, b, t):
    return a + (b - a) * t


def sky() -> Image.Image:
    img = Image.new("RGB", (W, H))
    px = img.load()
    for y in range(H):
        for x in range(W):
            t = y / (H - 1)
            c = [lerp(TOP[i], BOTTOM[i], t) for i in range(3)]
            d = math.hypot((x - GLOW_CENTER[0]) * 0.8, y - GLOW_CENTER[1])
            glow = max(0.0, 1.0 - d / GLOW_RADIUS) ** 2
            c = [lerp(c[i], GLOW_COLOR[i], glow * 0.6) for i in range(3)]
            bias = (BAYER[y % 4][x % 4] / 15.0 - 0.5) * 4.0
            px[x, y] = tuple(max(0, min(255, int(round((v + bias) / 2.0)) * 2)) for v in c)
    strokes = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(strokes)
    random.seed(11)
    dx, dy = math.cos(STROKE_ANGLE), math.sin(STROKE_ANGLE)
    for _ in range(150):
        x = random.randint(-100, W)
        y = random.randint(-40, H + 40)
        length = random.randint(80, 360)
        width = random.choice((1, 1, 2, 2, 3, 5))
        # Más claras arriba a la derecha (de donde viene la luz en Skin04) y casi negras abajo.
        lum = random.randint(90, 190) * (1.0 - 0.55 * y / H)
        alpha = random.randint(24, 64)
        d.line([x, y, x + dx * length, y + dy * length], fill=(int(lum), int(lum * 0.97), int(lum * 1.08), alpha), width=width)
    out = img.convert("RGBA")
    out.alpha_composite(strokes)
    # Franja oscura inferior (como el negro de la parte baja de las pantallas de Skin04).
    shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sp = shade.load()
    for y in range(H):
        a = int(max(0.0, (y - H * 0.62) / (H * 0.38)) * 150)
        for x in range(W):
            sp[x, y] = (0, 0, 0, a)
    out.alpha_composite(shade)
    return out.convert("RGB")


if __name__ == "__main__":
    sky().save(OUT + "menu_sky.png")
    print("ok")
