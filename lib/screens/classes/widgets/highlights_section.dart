import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../models/annotation.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/pdf_text_sanitize.dart';
import '../../../widgets/inset_group.dart';
import 'detail_page_theme.dart';

/// Раздел «Мои выделения»: цвет, сам фрагмент, заметка и откуда он (лекция/
/// страница). Показывает и пометки, сделанные на сайте, — они приходят с
/// сервера теми же полями.
///
/// Строка — отдельная карточка, а не ряд сгруппированного iOS-списка: у
/// пометки переменная высота (две строки текста + заметка + подпись), и в
/// сплошном списке с волосяными линиями они сливались в стену текста. Цвет
/// пометки показан отдельным образцом, чтобы список оставался спокойным и
/// хорошо читался в обеих темах.
class HighlightsSection extends StatelessWidget {
  final List<Annotation> items;
  final String Function(String) t;

  /// Тап по строке: у пометок в тексте лекции — прокрутка к фрагменту, у
  /// пометок из файлов — открыть карточку с действиями.
  final ValueChanged<Annotation> onTap;
  final ValueChanged<Annotation> onDelete;

  /// В шторке просмотрщика заголовок уже есть у самой шторки.
  final bool hideHeader;

  const HighlightsSection({
    super.key,
    required this.items,
    required this.t,
    required this.onTap,
    required this.onDelete,
    this.hideHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    // Новые пометки сверху: сортировка только для показа, порядок в хранилище
    // не трогаем. Вторичный ключ — id: сервер может отдать одинаковый updatedAt.
    final sorted = [...items]..sort((a, b) {
        final at = a.updatedAt, bt = b.updatedAt;
        if (at != null && bt != null) {
          final c = bt.compareTo(at);
          if (c != 0) return c;
        } else if (at != null) {
          return -1;
        } else if (bt != null) {
          return 1;
        }
        return b.id.compareTo(a.id);
      });

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!hideHeader)
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Row(children: [
            Text(t('hl_section').toUpperCase(),
                style: sectionCaptionStyle(context)),
            const SizedBox(width: 6),
            Text('${items.length}',
                style: sectionCaptionStyle(context)
                    .copyWith(color: detailText2(context))),
          ]),
        ),
      InsetGroup(
        color: detailSurface(context),
        children: [
          for (var i = 0; i < sorted.length; i++)
            _Row(
                item: sorted[i],
                pos: innerPos(i, sorted.length),
                t: t,
                onTap: onTap,
                onDelete: onDelete),
        ],
      ),
    ]);
  }
}

class _Row extends StatelessWidget {
  final Annotation item;
  final GroupPos pos;
  final String Function(String) t;
  final ValueChanged<Annotation> onTap;
  final ValueChanged<Annotation> onDelete;
  const _Row(
      {required this.item,
      required this.pos,
      required this.t,
      required this.onTap,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final swatch = highlightSwatch(item.color);
    final meta = <String>[
      if (item.lectureTitle != null && item.lectureTitle!.isNotEmpty)
        item.lectureTitle!,
      if (item.page > 0) '${t('hl_page')} ${item.page}',
    ].join(' · ');
    final hasNote = item.comment != null && item.comment!.trim().isNotEmpty;

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      // Свайп влево — привычный для iOS способ удалить строку списка.
      background: Container(
        decoration: BoxDecoration(
          color: C.red,
          borderRadius: groupRadius(pos),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(CupertinoIcons.delete, color: Colors.white, size: 19),
      ),
      onDismissed: (_) => onDelete(item),
      child: GroupRow(
        pos: pos,
        color: Colors.transparent,
        separatorInset: 14,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 13),
        onTap: () => onTap(item),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 24,
              height: 8,
              decoration: BoxDecoration(
                color: swatch,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(width: 9),
              Expanded(
                child: Text(meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                      color: detailText2(context),
                    )),
              ),
            ] else
              const Spacer(),
            Icon(CupertinoIcons.chevron_right,
                size: 13, color: detailText2(context).withValues(alpha: 0.5)),
          ]),
          const SizedBox(height: 10),
          Text(
            // Чистим U+FFFD от PDFium: в старых пометках на месте
            // бюллетеней из Word сохранились «ромбы-вопросы».
            sanitizePdfSymbols(item.selectedText).trim(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              letterSpacing: -0.2,
              fontWeight: FontWeight.w500,
              color: detailText1(context),
            ),
          ),
          if (hasNote) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: adaptiveSurface2(context),
                borderRadius: BorderRadius.circular(AppRadii.tile),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(CupertinoIcons.text_bubble, size: 13, color: swatch),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(item.comment!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: detailText1(context).withValues(alpha: 0.86),
                      )),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
