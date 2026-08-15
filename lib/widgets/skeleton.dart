import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'inset_group.dart';

class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? C.darkSurface2 : const Color(0xFFE2E9EC);
    final highlight = isDark ? const Color(0xFF1F3540) : Colors.white;

    // Каждый блок мерцает своим контроллером на 60 fps и перекрашивает
    // градиент каждый кадр. Без своей границы перерисовки эта перекраска
    // поднималась до ближайшего слоя выше — то есть весь список скелетонов
    // (а это три карточки по несколько блоков) перерисовывался целиком каждый
    // кадр ровно в те секунды, когда приложение и так занято ответами сервера
    // после логина.
    return RepaintBoundary(
      child: AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final spotX = -2.0 + 4.0 * _ctrl.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(spotX - 0.8, 0),
              end: Alignment(spotX + 0.8, 0),
              colors: [base, highlight, base],
            ),
          ),
        );
      },
      ),
    );
  }
}

class SkeletonClassCard extends StatelessWidget {
  const SkeletonClassCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: cardShadow(isDark),
      ),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          child: SkeletonBox(width: double.infinity, height: 168, borderRadius: 0),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SkeletonBox(width: 190, height: 16, borderRadius: 8),
            SizedBox(height: 10),
            Row(children: [
              SkeletonBox(width: 62, height: 22, borderRadius: 8),
              SizedBox(width: 6),
              SkeletonBox(width: 90, height: 22, borderRadius: 8),
            ]),
            SizedBox(height: 14),
            Row(children: [
              SkeletonBox(width: 86, height: 32, borderRadius: 10),
              Spacer(),
              SkeletonBox(width: 34, height: 34, borderRadius: 10),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Заглушка ОДНОЙ строки списка уведомлений. Экран уведомлений — не стопка
/// карточек, а inset-grouped группа, поэтому и заглушка теперь плоская строка
/// без тени и зазора: с карточным видом список «схлопывался» в сплошную группу
/// в момент подмены заглушек данными.
///
/// Метрики повторяют живую строку (см. `_NotifRowContent`): гуттер 12, колонка
/// значка 26, отступ 12, ТРИ строки — тип, название задания, предмет.
class SkeletonNotifCard extends StatelessWidget {
  const SkeletonNotifCard({super.key, this.pos = GroupPos.middle});

  final GroupPos pos;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: groupRadius(pos),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            const SizedBox(width: 12),
            // Заглушка под сам глиф, а не под плитку: подложки у значка больше
            // нет, и квадрат 38×38 обещал бы то, чего в живой строке не будет.
            const SkeletonBox(width: 22, height: 22, borderRadius: 6),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SkeletonBox(width: 104, height: 10, borderRadius: 5),
              const SizedBox(height: 8),
              SkeletonBox(width: MediaQuery.sizeOf(context).width * 0.5, height: 14, borderRadius: 7),
              const SizedBox(height: 8),
              const SkeletonBox(width: 92, height: 11, borderRadius: 6),
            ])),
          ]),
        ),
        if (pos == GroupPos.first || pos == GroupPos.middle)
          Padding(
            padding: const EdgeInsets.only(left: 64),
            child: Container(height: hairline(context), color: groupSeparator(context)),
          ),
      ]),
    );
  }
}
