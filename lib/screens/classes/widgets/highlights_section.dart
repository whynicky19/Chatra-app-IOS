import 'package:flutter/cupertino.dart';

import '../../../models/annotation.dart';
import 'detail_page_theme.dart';

/// Раздел «Мои выделения» на странице лекции: цвет, короткий текст, заметка и
/// откуда фрагмент (лекция/страница). Показывает и пометки, сделанные на сайте
/// внутри PDF, — они приходят с сервера с номером страницы.
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
    final border = detailBorder(context);
    final hair = 1 / MediaQuery.devicePixelRatioOf(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!hideHeader) Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Row(children: [
          Text(t('hl_section').toUpperCase(), style: sectionCaptionStyle(context)),
          const SizedBox(width: 6),
          Text('${items.length}',
              style: sectionCaptionStyle(context).copyWith(color: detailText2(context))),
        ]),
      ),
      // Сгруппированный список iOS: одна карточка, строки разделены волосяной
      // линией с отступом под текст.
      Container(
        decoration: BoxDecoration(
          color: detailSurface(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: hair),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Container(height: hair, color: border),
            ),
            _Row(item: items[i], t: t, onTap: onTap, onDelete: onDelete),
          ],
        ]),
      ),
    ]);
  }
}

class _Row extends StatelessWidget {
  final Annotation item;
  final String Function(String) t;
  final ValueChanged<Annotation> onTap;
  final ValueChanged<Annotation> onDelete;
  const _Row({required this.item, required this.t, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (item.lectureTitle != null && item.lectureTitle!.isNotEmpty) item.lectureTitle!,
      if (item.page > 0) '${t('hl_page')} ${item.page}',
    ].join(' · ');

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      // Свайп влево — привычный для iOS способ удалить строку списка.
      background: Container(
        color: CupertinoColors.systemRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white, size: 20),
      ),
      onDismissed: (_) => onDelete(item),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 11, 14, 11),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 3,
              height: 34,
              margin: const EdgeInsets.only(right: 13),
              decoration: BoxDecoration(
                color: highlightSwatch(item.color),
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
              ),
            ),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                item.selectedText.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15, height: 1.35, letterSpacing: -0.2, color: detailText1(context),
                ),
              ),
              if (item.comment != null) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(CupertinoIcons.pencil, size: 11, color: detailText2(context)),
                  const SizedBox(width: 4),
                  Expanded(child: Text(item.comment!,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: detailText2(context)))),
                ]),
              ),
              if (meta.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(meta,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: detailText2(context))),
              ),
            ])),
            Icon(CupertinoIcons.chevron_right, size: 14, color: detailText2(context).withValues(alpha: 0.6)),
          ]),
        ),
      ),
    );
  }
}
