import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../models/annotation.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_dialog.dart';

/// Окно заметки к выделению — в общем стиле приложения (как остальные диалоги
/// на `AppDialogCard`), а не системный `CupertinoAlertDialog`: тот выпадал из
/// дизайна и, главное, не показывал, к какому именно фрагменту пишется
/// заметка — а её пишут как раз глядя на текст.
///
/// Возвращает текст заметки, пустую строку — «убрать заметку», null — отмена.
Future<String?> showHighlightNoteDialog(
  BuildContext context, {
  required String quote,
  required String color,
  required String Function(String) t,
  String? initial,
}) {
  final ctrl = TextEditingController(text: initial ?? '');
  final hadNote = (initial ?? '').trim().isNotEmpty;

  return showAppDialog<String>(context, builder: (ctx) {
    final accent = Theme.of(ctx).colorScheme.primary;
    return AppDialogCard(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AppDialogIcon(icon: CupertinoIcons.text_bubble, color: accent),
        const SizedBox(height: 14),
        Text(hadNote ? t('hl_note_edit') : t('hl_note'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
              color: adaptiveText1(ctx),
            )),
        const SizedBox(height: 14),
        _Quote(text: quote, color: color),
        const SizedBox(height: 14),
        TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(hintText: t('hl_note_hint')),
        ),
        const SizedBox(height: 16),
        AppDialogActions(
          cancelText: t('cancel'),
          confirmText: t('save'),
          onCancel: () => Navigator.pop(ctx),
          onConfirm: () => Navigator.pop(ctx, ctrl.text.trim()),
        ),
        // Убрать заметку можно только когда она есть: пустое поле + «Сохранить»
        // сделали бы то же самое, но это неочевидно.
        if (hadNote) ...[
          const SizedBox(height: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(ctx, ''),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(t('hl_note_clear'),
                  style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: C.red,
                  )),
            ),
          ),
        ],
      ]),
    );
  }).whenComplete(() {
    // Контроллер переживает закрытие: анимация выхода ещё рисует поле.
    Future.delayed(const Duration(seconds: 1), ctrl.dispose);
  });
}

/// Сам выделенный фрагмент — цветной кромкой того же цвета, что и пометка.
class _Quote extends StatelessWidget {
  final String text;
  final String color;
  const _Quote({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: adaptiveSurface2(context),
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      clipBehavior: Clip.antiAlias,
      // Кромка тянется на всю высоту цитаты: высоту задаёт текст, а Positioned
      // с top/bottom растягивает полосу по нему (IntrinsicHeight на тексте с
      // межстрочным интервалом считает высоту чуть меньше настоящей — полоса
      // не доходила до низа).
      child: Stack(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: Text(
            text.trim(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14, height: 1.4, letterSpacing: -0.2,
              color: adaptiveText2(context),
            ),
          ),
        ),
        Positioned(
          left: 0, top: 0, bottom: 0, width: 3,
          child: ColoredBox(color: highlightSwatch(color)),
        ),
      ]),
    );
  }
}
