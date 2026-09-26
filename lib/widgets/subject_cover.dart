/// Готовая обложка. Для fallback и legacy `ai` клиент дорисовывает чистый
/// SVG-глиф. Новая `ai_hero` уже содержит крупный тематический 3D-объект, поэтому
/// дополнительный глиф на ней скрывается.
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

  final String? color;

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

    final stroke = (40 / size).clamp(1.1, 1.8);

    return IgnorePointer(
      child: RepaintBoundary(
      child: Center(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(children: [
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

class SubjectCover extends StatelessWidget {
  /// Готовый URL обложки (уже прогнанный через ApiService.fixUrl).
  final String? url;
  final String? icon;
  final String? color;
  final String? coverSource;
  final double iconSize;
  final int? memCacheWidth;

  const SubjectCover({
    super.key,
    required this.url,
    this.icon,
    this.color,
    this.coverSource,
    this.iconSize = 44,
    this.memCacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    final swatch = CoverOptionsCache.current.colorFor(color);
    return Stack(fit: StackFit.expand, children: [
      Container(color: swatch.base),
      if (url != null && url!.isNotEmpty)
        NetworkCoverImage(
          url: url!,
          memCacheWidth: memCacheWidth,
          placeholderBuilder: (_) => const SizedBox.shrink(),
          errorBuilder: (_) => const SizedBox.shrink(),
        ),
      if (coverSource != 'ai_hero')
        SubjectIconOverlay(icon: icon, color: color, size: iconSize),
    ]);
  }
}
