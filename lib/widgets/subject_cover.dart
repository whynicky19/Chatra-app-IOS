/// Предметная иконка поверх обложки — и готовая обложка целиком для превью.
///
/// Иконка НЕ входит в сохранённую картинку: бэкенд генерирует только фон
/// (см. services/cover_art.py). Генеративные модели нестабильно рисуют символы
/// вроде Σ или спирали ДНК, поэтому иконка — чистый SVG на стороне клиента:
/// всегда одинаковая, её можно перекрасить или заменить без перегенерации всех
/// обложек в хранилище.
///
/// Специальной пустой зоны под иконку в композиции больше нет — «чистые полосы»
/// делали обложку похожей на дашборд. Читаемость обеспечивает сам слой: белый
/// глиф с мягкой тенью (см. ICON_ON_ARTWORK).
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

  /// Слаг цвета обложки. Сейчас на цвет глифа не влияет (он белый), но
  /// оставлен: пикер и превью передают его, и он понадобится, если решим
  /// вернуть иконку в тон.
  final String? color;

  /// Размер в логических пикселях: один на контекст, одинаковый для всех
  /// предметов внутри него.
  final double size;

  const SubjectIconOverlay({
    super.key,
    required this.icon,
    this.color,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    if (icon == null || icon!.isEmpty) return const SizedBox.shrink();

    // Толщина линии масштабируется вместе с иконкой, поэтому визуальный вес
    // штриха одинаков и на мелкой плашке, и на крупной шапке.
    final stroke = (40 / size).clamp(1.1, 1.8);

    return IgnorePointer(
      // Своя граница перерисовки: тень глифа — это ImageFilter.blur, то есть
      // saveLayer + размытие на растровом потоке, и делается он заново каждый
      // раз, когда перерисовывается карточка (а список классов перестраивается
      // на каждый notifyListeners провайдера — при загрузке это несколько раз
      // подряд). Со своим слоем размытие считается один раз и дальше просто
      // переиспользуется композитором.
      child: RepaintBoundary(
      child: Center(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(children: [
            // Иконка ложится поверх готовой композиции: специальной пустой зоны
            // под неё бэкенд больше не резервирует (см. ICON_ON_ARTWORK в
            // cover_art.py). Под глифом может оказаться и тёмная, и светлая
            // форма, поэтому он белый и с мягкой тенью — иконка в тон на
            // насыщенной композиции давала контраст 1.5-2.0 и пропадала.
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: size * 0.07, sigmaY: size * 0.07),
              child: SvgPicture.string(
                coverIconSvg(icon, color: Colors.black, strokeWidth: stroke),
                width: size,
                height: size,
                colorFilter: const ColorFilter.mode(Colors.black54, BlendMode.srcIn),
              ),
            ),
            SvgPicture.string(
              coverIconSvg(icon, strokeWidth: stroke),
              width: size,
              height: size,
            ),
          ]),
        ),
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
      SubjectIconOverlay(icon: icon, color: color, size: iconSize),
    ]);
  }
}
