"""Genera las dos capas del fondo del menú principal (640x360, pixel art):
  assets/ui/menu/menu_sky.png         cielo burdeos con luna tenue, dither Bayer 4x4
  assets/ui/menu/menu_silhouette.png  silueta negra de la mazmorra (muro almenado, torres, arcos, pilares)
Uso: python scripts/tools/gen_menu_bg.py   (desde la raíz del proyecto; necesita Pillow)."""
import math
import random
from PIL import Image, ImageDraw

W, H = 640, 360
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
OUT = "assets/ui/menu/"


def lerp(a, b, t):
    return a + (b - a) * t


def sky() -> Image.Image:
    top, mid, low = (6, 0, 3), (74, 6, 16), (132, 22, 28)
    img = Image.new("RGB", (W, H))
    px = img.load()
    moon = (598, 60)
    for y in range(H):
        for x in range(W):
            t = min(1.0, y / 250.0)
            if t < 0.6:
                c = [lerp(top[i], mid[i], t / 0.6) for i in range(3)]
            else:
                c = [lerp(mid[i], low[i], (t - 0.6) / 0.4) for i in range(3)]
            d = math.hypot(x - moon[0], y - moon[1])
            glow = max(0.0, 1.0 - d / 120.0) ** 2 * 0.55
            c = [min(255.0, c[i] + glow * (150, 40, 40)[i]) for i in range(3)]
            if d < 22:
                disc = 1.0 - d / 22.0 * 0.35
                c = [lerp(c[i], (196, 84, 80)[i], 0.85) * disc if i == 0 else lerp(c[i], (196, 84, 80)[i], 0.85) * disc for i in range(3)]
            bias = (BAYER[y % 4][x % 4] / 15.0 - 0.5) * 9.0
            px[x, y] = tuple(max(0, min(255, int(round((v + bias) / 6.0)) * 6)) for v in c)
    # tenue banda de niebla sobre el horizonte
    fog = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(fog)
    random.seed(7)
    for _ in range(26):
        y = random.randint(210, 300)
        x = random.randint(-80, W - 60)
        d.rectangle([x, y, x + random.randint(90, 260), y + random.randint(1, 3)], fill=(190, 60, 60, 38))
    out = img.convert("RGBA")
    out.alpha_composite(fog)
    return out.convert("RGB")


def merlons(d, x0, x1, y, fill, w=10, gap=8, h=8):
    x = x0
    while x < x1:
        d.rectangle([x, y - h, min(x + w, x1) - 1, y], fill=fill)
        x += w + gap


def tower(d, cx, w, top, kind, fill):
    x0, x1 = cx - w // 2, cx + w // 2
    d.rectangle([x0, top, x1, H], fill=fill)
    if kind == "cone":
        d.polygon([(x0 - 4, top), (x1 + 4, top), (cx + 2, top - w), (cx - 2, top - w)], fill=fill)
        d.rectangle([cx - 1, top - w - 14, cx, top - w], fill=fill)
    else:
        d.rectangle([x0 - 3, top - 4, x1 + 3, top], fill=fill)
        merlons(d, x0 - 3, x1 + 4, top - 4, fill, w=7, gap=5, h=7)


def pointed_arch(d, cx, w, base, h, fill):
    r = w / 2
    pts = [(cx - r, base)]
    top_y = base - h
    for i in range(0, 21):
        a = math.pi * i / 20
        pts.append((cx - r * math.cos(a), top_y + r - r * math.sin(a) * 1.35))
    pts.append((cx + r, base))
    d.polygon(pts, fill=fill)


def silhouette() -> Image.Image:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cut = (0, 0, 0, 0)
    # capa lejana: skyline tenue
    far = (30, 2, 8, 255)
    for cx, w, top, kind in [(30, 26, 214, "flat"), (110, 34, 196, "cone"), (205, 28, 222, "flat"),
                             (292, 38, 190, "cone"), (370, 30, 216, "flat"), (448, 36, 200, "cone"),
                             (540, 30, 220, "flat"), (615, 34, 204, "cone")]:
        tower(d, cx, w, top, kind, far)
    d.rectangle([0, 246, W, H], fill=far)
    merlons(d, 0, W, 246, far, w=9, gap=7, h=6)
    black = (0, 0, 0, 255)
    # muro almenado cercano
    d.rectangle([0, 268, W, H], fill=black)
    merlons(d, 0, W, 268, black, w=14, gap=10, h=10)
    # torres cercanas
    for cx, w, top, kind in [(46, 50, 150, "cone"), (158, 34, 206, "flat"), (250, 44, 178, "cone"),
                             (398, 38, 196, "flat"), (510, 52, 134, "cone"), (604, 42, 184, "flat")]:
        tower(d, cx, w, top, kind, black)
    # torre del homenaje central con puerta ojival
    d.rectangle([262, 190, 378, H], fill=black)
    d.rectangle([254, 184, 386, 192], fill=black)
    merlons(d, 254, 387, 184, black, w=12, gap=9, h=9)
    # arcos del muro (arcada) y aberturas
    for cx in (96, 206, 316 - 190 + 190, 430, 552):
        if 255 < cx < 380:
            continue
        pointed_arch(d, cx, 30, H, 62, cut)
    pointed_arch(d, 320, 52, H, 104, cut)          # portón central
    for cx, top in [(46, 176), (250, 204), (510, 160), (158, 226), (398, 220), (604, 206), (320, 214)]:
        d.rectangle([cx - 2, top, cx + 1, top + 12], fill=cut)   # saeteras
    pointed_arch(d, 46, 8, 188, 16, cut)
    pointed_arch(d, 510, 8, 170, 18, cut)
    # pilares de primer plano (uno roto)
    for px_, top, wd in [(18, 214, 14), (606, 200, 14), (140, 260, 12), (500, 252, 12)]:
        d.rectangle([px_ - wd // 2, top, px_ + wd // 2, H], fill=black)
        d.rectangle([px_ - wd // 2 - 4, top, px_ + wd // 2 + 4, top + 6], fill=black)
        d.rectangle([px_ - wd // 2 - 5, H - 14, px_ + wd // 2 + 5, H], fill=black)
    # pilar partido y arco derruido
    d.polygon([(70, 300), (70, 262), (76, 268), (80, 258), (86, 270), (88, 300)], fill=black)
    # suelo irregular
    random.seed(3)
    pts = [(0, H)]
    x = 0
    while x <= W:
        pts.append((x, 336 - random.randint(0, 9) - (6 if (x // 40) % 3 == 0 else 0)))
        x += random.randint(8, 22)
    pts.append((W, H))
    d.polygon(pts, fill=black)
    return img


if __name__ == "__main__":
    import os
    os.makedirs(OUT, exist_ok=True)
    sky().save(OUT + "menu_sky.png")
    silhouette().save(OUT + "menu_silhouette.png")
