#!/usr/bin/env python3
"""Генерация иконки Chatra: белый глиф (книга+звезда) на бирюзовом градиенте.

Стиль — как у системных иконок iOS: вертикальный градиент (светлее сверху),
мягкий свет за глифом, много «воздуха», едва заметная тень под глифом.
Пересборка: python3 tool/make_icon.py && dart run flutter_launcher_icons
"""
from PIL import Image, ImageFilter, ImageDraw
import os

ASSETS = os.path.join(os.path.dirname(__file__), "..", "assets")
S = 1024

# ── 1. Белый глиф из logo-icon.png (бирюзовый на прозрачном) ──────────────
logo = Image.open(f"{ASSETS}/logo-icon.png").convert("RGBA")
alpha = logo.split()[3]
glyph_a = alpha.crop(alpha.getbbox())  # плотная обрезка по содержимому

def white_glyph(target_w: int) -> Image.Image:
    ratio = target_w / glyph_a.width
    a = glyph_a.resize((target_w, int(glyph_a.height * ratio)), Image.LANCZOS)
    g = Image.new("RGBA", a.size, (255, 255, 255, 255))
    g.putalpha(a)
    return g

# ── 2. Вертикальный градиент + мягкий свет за глифом (стиль iOS) ──────────
TOP = (64, 208, 228)   # светлый бирюзовый (верх)
BOT = (0, 130, 156)    # глубокий бирюзовый (низ)

def gradient_bg(size: int) -> Image.Image:
    bg = Image.new("RGB", (size, size))
    px = bg.load()
    for y in range(size):
        t = (y / (size - 1)) ** 1.06  # чуть дольше держим светлый верх
        row = tuple(int(TOP[i] + (BOT[i] - TOP[i]) * t) for i in range(3))
        for x in range(size):
            px[x, y] = row
    bg = bg.convert("RGBA")

    # Едва заметный радиальный свет за глифом (чуть выше центра) —
    # придаёт объём, не ломая «плоский» эппловский вид.
    hl = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(hl)
    cx, cy, r = size * 0.5, size * 0.40, size * 0.52
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=34)
    hl = hl.filter(ImageFilter.GaussianBlur(size * 0.16))
    bg.paste(Image.new("RGBA", (size, size), (255, 255, 255, 255)), (0, 0), hl)
    return bg

def compose(size: int, glyph_frac: float, with_bg: bool, shadow: bool = True) -> Image.Image:
    canvas = gradient_bg(size) if with_bg else Image.new("RGBA", (size, size), (0, 0, 0, 0))
    g = white_glyph(int(size * glyph_frac))
    gx = (size - g.width) // 2
    gy = (size - g.height) // 2
    if shadow:
        # Деликатная тень — только намёк на глубину
        tint = Image.new("RGBA", g.size, (0, 55, 70, 255))
        tint.putalpha(g.split()[3].point(lambda v: v * 60 // 255))
        sh = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        sh.paste(tint, (gx, gy + int(size * 0.012)), tint)
        sh = sh.filter(ImageFilter.GaussianBlur(size * 0.016))
        canvas = Image.alpha_composite(canvas, sh)
    canvas.paste(g, (gx, gy), g)
    return canvas

# Основная иконка (iOS + легаси Android): full-bleed, ОС сама скругляет углы.
# 58% — эппловская «дышащая» компоновка глифа.
compose(S, 0.58, with_bg=True).save(f"{ASSETS}/icon_source.png")
# Adaptive foreground: только глиф. Генератор добавляет inset 16%,
# итог в лаунчере ~60% видимого круга — в безопасной зоне.
compose(S, 0.54, with_bg=False, shadow=False).save(f"{ASSETS}/icon_source_adaptive.png")
# Adaptive background: чистый градиент без глифа
gradient_bg(S).save(f"{ASSETS}/icon_bg_adaptive.png")
print("done")
