/// Предметная иконка поверх обложки — и готовая обложка целиком для превью.
///
/// Иконка НЕ входит в сохранённую картинку: бэкенд генерирует только фон и
/// специально оставляет центр кадра пустым (см. services/cover_art.py).
/// Генеративные модели нестабильно рисуют символы вроде Σ или спирали ДНК,
/// поэтому иконка — чистый SVG на стороне клиента: всегда одинаковая, её можно
/// перекрасить или заменить без перегенерации всех обложек в хранилище.
///
/// [SubjectIconOverlay] кладётся в Stack к уже существующей обложке на каждом
/// экране — так все места показа получают иконку одного размера, одной толщины
/// линии и одного стиля, но продолжают сами решать, как рисовать фон (у старых
/// записей это может быть base64-картинка или градиент-заглушка).
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/cover_art.dart';
import 'network_cover_image.dart';

/// Иконка предмета по центру обложки. Пустой [icon] (легаси-обложка, загруженная
/// пользователем) не рисует ничего — чужую картинку перекрывать нельзя.
class SubjectIconOverlay extends StatelessWidget {
  final String? icon;

  /// Размер в логических пикселях: один на контекст, одинаковый для всех
  /// предметов внутри него.
  final double size;

  const SubjectIconOverlay({super.key, required this.icon, this.size = 44});

  @override
  Widget build(BuildContext context) {
    if (icon == null || icon!.isEmpty) return const SizedBox.shrink();

    // Толщина линии масштабируется вместе с иконкой, поэтому визуальный вес
    // штриха одинаков и на мелкой плашке, и на крупной шапке.
    final svg = coverIconSvg(icon, strokeWidth: (40 / size).clamp(1.1, 1.8));

    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(children: [
            // Мягкая тень под глифом. Промпт требует оставлять центр кадра
            // пустым, но модель соблюдает это не в 100% случаев — иногда через
            // центр проходит светлая линия или дуга. Тень делает белую иконку
            // читаемой на любом фоне, не полагаясь на послушность модели.
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: size * 0.055, sigmaY: size * 0.055),
              child: SvgPicture.string(
                coverIconSvg(icon,
                    color: Colors.black, strokeWidth: (40 / size).clamp(1.1, 1.8)),
                width: size,
                height: size,
                colorFilter: const ColorFilter.mode(Colors.black54, BlendMode.srcIn),
              ),
            ),
            SvgPicture.string(svg, width: size, height: size),
          ]),
        ),
      ),
    );
  }
}

/// Обложка целиком: заливка цвета + сетевая картинка + иконка. Используется
/// там, где нужен готовый блок и не надо поддерживать легаси-варианты фона —
/// сейчас это превью в пикере оформления.
class SubjectCover extends StatelessWidget {
  /// Готовый URL обложки (уже прогнанный через ApiService.fixUrl).
  final String? url;
  final String? icon;
  final String? color;
  final double iconSize;
  final int? memCacheWidth;

  const SubjectCover({
    super.key,
    required this.url,
    this.icon,
    this.color,
    this.iconSize = 44,
    this.memCacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    final swatch = CoverOptionsCache.current.colorFor(color);
    return Stack(fit: StackFit.expand, children: [
      // Заливка того же тона, что и фон обложки: пока грузится картинка,
      // превью не мигает серым, а при сбое загрузки остаётся осмысленный фон.
      Container(color: swatch.base),
      if (url != null && url!.isNotEmpty)
        NetworkCoverImage(
          url: url!,
          memCacheWidth: memCacheWidth,
          placeholderBuilder: (_) => const SizedBox.shrink(),
          errorBuilder: (_) => const SizedBox.shrink(),
        ),
      SubjectIconOverlay(icon: icon, size: iconSize),
    ]);
  }
}
