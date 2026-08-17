import 'package:flutter/widgets.dart';

/// Маркер выделения текста в стиле iOS: тонкая ножка вдоль строки и небольшой
/// шарик на её конце.
///
/// Важно, что сам виджет — это и зона захвата: просмотрщик вешает pan-жест
/// именно на него. Поэтому видимая часть маленькая (шарик 11 px), а виджет —
/// [touchSize] (68 px, с большим запасом от 44 по HIG). Со стандартными
/// маркерами pdfrx было наоборот: крупные синие треугольники 30×30, которые при
/// этом трудно поймать, потому что тащить их можно было только за саму фигуру.
///
/// Шарик стоит в зоне захвата не по центру, а смещён внутрь выделения: запас
/// уходит наружу — вверх-влево у начального маркера и вниз-вправо у конечного.
/// Так палец ловит маркер с той стороны, с которой к нему тянется, а зоны двух
/// маркеров не наползают друг на друга, когда выделено одно короткое слово.
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
  static const defaultTouchSize = 68.0;
  static const stemWidth = 2.0;

  /// Доля зоны захвата, приходящаяся на «внутреннюю» сторону маркера.
  static const _inner = 0.64;

  /// Центр шарика внутри зоны захвата. По нему просмотрщику считается сдвиг
  /// виджета (см. calcSelectionHandleOffset), иначе шарик встанет не на край
  /// выделения, а куда придётся.
  static Offset ballCenter(bool isStart, {double touchSize = defaultTouchSize}) {
    final k = isStart ? _inner : 1 - _inner;
    return Offset(touchSize * k, touchSize * k);
  }

  @override
  Widget build(BuildContext context) {
    final center = ballCenter(isStart, touchSize: touchSize);

    return SizedBox(
      width: touchSize,
      height: touchSize,
      child: Stack(clipBehavior: Clip.none, children: [
        // Ножка уходит от шарика к строке: вниз у начального маркера, вверх у
        // конечного.
        Positioned(
          left: center.dx - stemWidth / 2,
          top: isStart ? center.dy : center.dy - lineHeight,
          width: stemWidth,
          height: lineHeight,
          child: Container(color: color),
        ),
        Positioned(
          left: center.dx - ballSize / 2,
          top: center.dy - ballSize / 2,
          child: AnimatedScale(
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
                    ? [
                        BoxShadow(
                            color: color.withValues(alpha: 0.35), blurRadius: 8)
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
