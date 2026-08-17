import 'package:flutter/widgets.dart';

/// Маркер выделения текста в стиле iOS: тонкая ножка вдоль строки и небольшой
/// шарик на её конце.
///
/// Важно, что сам виджет — это и зона захвата: просмотрщик вешает pan-жест
/// именно на него. Поэтому видимая часть маленькая (шарик 11 px), а виджет —
/// [touchSize] (60 px, с запасом от 44 по HIG), причём шарик стоит в его
/// центре: палец ложится вокруг видимой точки, и запас нужен со всех сторон.
/// Со стандартными маркерами pdfrx было наоборот: крупные синие треугольники
/// 30×30, которые при этом трудно поймать, потому что тащить их можно было
/// только за саму фигуру.
class SelectionHandle extends StatelessWidget {
  /// Начальный маркер (в начале выделения) или конечный.
  final bool isStart;

  /// Высота строки на экране — ножка повторяет её, а не берётся «на глаз».
  final double lineHeight;

  /// Палец сейчас тащит маркер: шарик подрастает — отклик на само нажатие,
  /// а не по отпусканию.
  final bool dragging;

  final Color color;
  final double touchSize;

  const SelectionHandle({
    super.key,
    required this.isStart,
    required this.lineHeight,
    required this.color,
    this.dragging = false,
    this.touchSize = defaultTouchSize,
  });

  static const ballSize = 11.0;
  static const defaultTouchSize = 60.0;
  static const stemWidth = 2.0;

  @override
  Widget build(BuildContext context) {
    final stem = Container(width: stemWidth, height: lineHeight, color: color);
    final ball = AnimatedScale(
      scale: dragging ? 1.25 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: Container(
        width: ballSize,
        height: ballSize,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: dragging
              ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8)]
              : null,
        ),
      ),
    );

    // Шарик — в ЦЕНТРЕ зоны захвата, а не в её углу: палец ложится вокруг
    // видимой точки, и запас нужен со всех сторон. Ножка уходит от шарика к
    // строке (вниз у начального маркера, вверх у конечного).
    return SizedBox(
      width: touchSize,
      height: touchSize,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: isStart
              ? [ball, SizedBox(height: lineHeight, child: Center(child: stem))]
              : [SizedBox(height: lineHeight, child: Center(child: stem)), ball],
        ),
      ),
    );
  }
}
