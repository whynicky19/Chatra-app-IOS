#!/usr/bin/env python3
"""Генерация внутриприложенческого логотипа Chatra из нового глифа «C»
(assets/icon_glyph.png — чёрный на белом). В отличие от make_icon.py, здесь
нужны альфа-маски на прозрачном фоне: AppLogo красит картинку через
Image.asset(color: ...) для школьных аккаунтов, а тонирование с непрозрачным
фоном закрасило бы весь квадрат целиком.

Пересборка: python3 tool/make_logo.py
После — пересобрать сплэш: python3 tool/make_splash.py && dart run flutter_native_splash:create
"""
import os
from PIL import Image, ImageDraw, ImageFont

ASSETS = os.path.join(os.path.dirname(__file__), "..", "assets")
INK = (26, 26, 28)
FONT_PATH = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

# ── альфа-маска глифа (тот же приём, что в make_icon.py) ──────────────────
logo = Image.open(f"{ASSETS}/icon_glyph.png").convert("L")
alpha = logo.point(lambda v: 255 if v < 40 else 0 if v > 225 else int((225 - v) * 255 / 185))
glyph_a = alpha.crop(alpha.getbbox())


def glyph_rgba(target_w: int) -> Image.Image:
    ratio = target_w / glyph_a.width
    a = glyph_a.resize((target_w, int(glyph_a.height * ratio)), Image.LANCZOS)
    g = Image.new("RGBA", a.size, (*INK, 255))
    g.putalpha(a)
    return g


# ── 1. logo-icon.png: только глиф, прозрачный фон, плотная обрезка ────────
S1 = 2048
g = glyph_rgba(int(S1 * 0.86))
canvas = Image.new("RGBA", g.size, (0, 0, 0, 0))
canvas.alpha_composite(g)
canvas.save(f"{ASSETS}/logo-icon.png")
print(f"Wrote assets/logo-icon.png ({canvas.width}x{canvas.height})")

# ── 2. logo.png: глиф сверху + надпись CHATRA снизу, прозрачный фон ───────
S2 = 1200
glyph_w = int(S2 * 0.42)
g2 = glyph_rgba(glyph_w)

font_size = 132
font = ImageFont.truetype(FONT_PATH, font_size)
text = "CHATRA"
letter_spacing = 6

# Ширина текста с ручным трекингом (letter-spacing) через посимвольную отрисовку.
tmp = Image.new("L", (1, 1))
tmp_draw = ImageDraw.Draw(tmp)
char_widths = [tmp_draw.textlength(ch, font=font) for ch in text]
text_w = int(sum(char_widths) + letter_spacing * (len(text) - 1))
ascent, descent = font.getmetrics()
text_h = ascent + descent

gap = int(S2 * 0.05)
total_h = g2.height + gap + text_h
canvas2 = Image.new("RGBA", (S2, total_h), (0, 0, 0, 0))
canvas2.alpha_composite(g2, ((S2 - g2.width) // 2, 0))

text_layer = Image.new("RGBA", (text_w + 4, text_h + 4), (0, 0, 0, 0))
td = ImageDraw.Draw(text_layer)
x = 0
for ch, w in zip(text, char_widths):
    td.text((x, 0), ch, font=font, fill=(*INK, 255))
    x += w + letter_spacing
canvas2.alpha_composite(text_layer, ((S2 - text_layer.width) // 2, g2.height + gap))

canvas2.save(f"{ASSETS}/logo.png")
print(f"Wrote assets/logo.png ({canvas2.width}x{canvas2.height})")
