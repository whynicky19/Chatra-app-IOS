import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/l10n_provider.dart';
import '../theme/app_theme.dart';

/// Баннер «ИИ читает материалы курса» над полем ввода — показывается вместо
/// возможности писать, пока фоновая загрузка текста файлов лекций не
/// закончится (см. class_detail_screen._loadFileTexts). Без него долгая
/// пауза перед ответом ИИ выглядела как зависание. Визуально — родной брат
/// AiLimitNotice (та же карточка/отступы/радиус), только тёплый жёлтый
/// таймер заменён на вращающийся индикатор основного цвета темы.
class AiReadingNotice extends StatelessWidget {
  final int ready;
  final int total;
  const AiReadingNotice({super.key, required this.ready, required this.total});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: Border.all(color: adaptiveBorder(context).withValues(alpha: 0.6), width: 0.5),
        boxShadow: softShadow(isDark),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 28, height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary.withValues(alpha: isDark ? 0.22 : 0.14),
            shape: BoxShape.circle,
          ),
          child: SizedBox(width: 13, height: 13,
            child: CircularProgressIndicator(strokeWidth: 2, color: primary)),
        ),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.t('ai_reading_materials_title'),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
              color: adaptiveText1(context), height: 1.3)),
          const SizedBox(height: 2),
          Text(_subtitle(l),
            style: const TextStyle(fontSize: 13, color: C.text4, height: 1.4)),
        ])),
      ]),
    );
  }

  String _subtitle(L10n l) {
    if (total <= 0) return l.t('ai_reading_materials_sub');
    return l.t('ai_reading_materials_sub_progress')
        .replaceAll('{ready}', '$ready')
        .replaceAll('{total}', '$total');
  }
}
