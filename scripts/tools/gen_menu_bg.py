"""Genera el fondo del menú principal (640x360, pixel art): assets/ui/menu/menu_sky.png
Degradado vertical violeta crepuscular (#2a2640) a malva apagado (#54344a), con un resplandor
cálido tras la isla (mitad derecha), bandas de niebla y dither Bayer 4x4. La isla se dibuja aparte, en 3D.
Uso: python scripts/tools/gen_menu_bg.py   (desde la raíz del proyecto; necesita Pillow)."""
import math
import random
from PIL import Image, ImageDraw

W, H = 640, 360
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
OUT = "assets/ui/menu/"
TOP, BOTTOM = (0x2a, 0x26, 0x40), (0x54, 0x34, 0x4a)
GLOW_CENTER, GLOW_RADIUS, GLOW_COLOR = (480, 170), 230.0, (172, 108, 132)


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
            c = [lerp(c[i], GLOW_COLOR[i], glow * 0.7) for i in range(3)]
            bias = (BAYER[y % 4][x % 4] / 15.0 - 0.5) * 4.0
            px[x, y] = tuple(max(0, min(255, int(round((v + bias) / 2.0)) * 2)) for v in c)
    fog = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(fog)
    random.seed(7)
    for _ in range(22):
        y = random.randint(200, 340)
        x = random.randint(-80, W - 60)
        d.rectangle([x, y, x + random.randint(90, 260), y + random.randint(1, 2)], fill=(190, 150, 170, 26))
    out = img.convert("RGBA")
    out.alpha_composite(fog)
    return out.convert("RGB")


if __name__ == "__main__":
    sky().save(OUT + "menu_sky.png")
    print("ok")
