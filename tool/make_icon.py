#!/usr/bin/env python3
"""Генерация иконки Chatra: чёрный глиф «C» на белом фоне — монохром,
как в оригинале логотипа (new logo chatra). Никакого бирюзового.

Пересборка: python3 tool/make_icon.py && dart run flutter_launcher_icons
Источник глифа: assets/icon_glyph.png (чёрный логотип «C» на белом фоне).
"""
from PIL import Image
import os

ASSETS = os.path.join(os.path.dirname(__file__), "..", "assets")
S = 1024

# Цвет глифа — как в исходнике логотипа (почти чёрный, чуть тёплый графит).
INK = (26, 26, 28)
BG = (255, 255, 255)

# ── 1. Альфа глифа из icon_glyph.png (чёрный на белом) ────────────────────
# Альфа = инвертированная яркость; кривая душит почти-белый шум по краям.
logo = Image.open(f"{ASSETS}/icon_glyph.png").convert("L")
alpha = logo.point(lambda v: 255 if v < 40 else 0 if v > 225 else int((225 - v) * 255 / 185))
glyph_a = alpha.crop(alpha.getbbox())  # плотная обрезка по содержимому


def glyph(target_w: int, color) -> Image.Image:
    ratio = target_w / glyph_a.width
    a = glyph_a.resize((target_w, int(glyph_a.height * ratio)), Image.LANCZOS)
    g = Image.new("RGBA", a.size, (*color, 255))
    g.putalpha(a)
    return g


def compose(size: int, glyph_frac: float, with_bg: bool) -> Image.Image:
    canvas = (Image.new("RGBA", (size, size), (*BG, 255)) if with_bg
              else Image.new("RGBA", (size, size), (0, 0, 0, 0)))
    g = glyph(int(size * glyph_frac), INK)
    canvas.paste(g, ((size - g.width) // 2, (size - g.height) // 2), g)
    return canvas


# Основная иконка (iOS + легаси Android): full-bleed белый квадрат,
# ОС сама скругляет углы. 58% — «дышащая» компоновка глифа.
compose(S, 0.58, with_bg=True).save(f"{ASSETS}/icon_source.png")
# Adaptive foreground: только глиф; 0.46 — чтобы «C» не липла к краю
# круглой маски лаунчера (генератор добавляет свой inset).
compose(S, 0.46, with_bg=False).save(f"{ASSETS}/icon_source_adaptive.png")
# Adaptive background: чистый белый.
Image.new("RGB", (S, S), BG).save(f"{ASSETS}/icon_bg_adaptive.png")
print("done")
