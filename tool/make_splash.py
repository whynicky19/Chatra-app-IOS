#!/usr/bin/env python3
"""Генерация ассета для нативного splash: тот же глиф Chatra, но небольшим и по
центру прозрачного квадрата — на нативном splash логотип не растягивается на
весь экран, а выглядит компактно и по-эпловски.

Пересборка: python3 tool/make_splash.py && dart run flutter_native_splash:create
"""
import os
from PIL import Image

ASSETS = os.path.join(os.path.dirname(__file__), "..", "assets")

# Квадратный холст; глиф занимает ~38% ширины — на нативном splash это даёт
# компактный логотип с «воздухом» вокруг (iOS launch style).
CANVAS = 1024
GLYPH_FRACTION = 0.38

logo = Image.open(f"{ASSETS}/logo-icon.png").convert("RGBA")
glyph = logo.crop(logo.split()[3].getbbox())  # плотная обрезка по содержимому

target_w = int(CANVAS * GLYPH_FRACTION)
target_h = int(glyph.height * target_w / glyph.width)
glyph = glyph.resize((target_w, target_h), Image.LANCZOS)

canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
canvas.alpha_composite(glyph, ((CANVAS - target_w) // 2, (CANVAS - target_h) // 2))
canvas.save(f"{ASSETS}/splash-logo.png")
print(f"Wrote assets/splash-logo.png ({CANVAS}x{CANVAS}, glyph {target_w}px)")
