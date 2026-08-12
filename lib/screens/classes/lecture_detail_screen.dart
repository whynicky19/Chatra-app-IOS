import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import 'widgets/detail_page_theme.dart';
import 'widgets/file_card.dart';

/// Полноэкранная страница лекции (замена модального bottom sheet).
/// Открывается через Navigator.push с нативным iOS push-переходом
/// (обеспечивается CupertinoPageTransitionsBuilder в AppTheme).
class LectureDetailScreen extends StatelessWidget {
  final String title;
  final String dateLabel;
  final String content;
  final List<String> files;
  final void Function(BuildContext context, String url, String name) onOpenFile;

  const LectureDetailScreen({
    super.key,
    required this.title,
    required this.dateLabel,
    required this.content,
    required this.files,
    required this.onOpenFile,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.read<L10n>();
    final bg = detailBg(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = detailAccent(context);

    return CupertinoTheme(
      data: CupertinoThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primaryColor: accent,
        scaffoldBackgroundColor: bg,
        barBackgroundColor: bg,
        textTheme: CupertinoTextThemeData(
          primaryColor: accent,
          navLargeTitleTextStyle: TextStyle(
            // Крупный кегль — отрицательный трекинг и плотный интерлиньяж:
            // заголовок из двух строк иначе «разъезжается».
            fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.8, height: 1.1,
            color: detailText1(context),
          ),
          navTitleTextStyle: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: detailText1(context),
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: bg,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            CupertinoSliverNavigationBar(
              // Полупрозрачный фон бара — CupertinoNavigationBar сам включает
              // под ним блюр, когда цвет не непрозрачный: свёрнутый заголовок
              // «плывёт» над текстом лекции, как в нативных приложениях.
              backgroundColor: bg.withValues(alpha: 0.82),
              border: null,
              stretch: true,
              largeTitle: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 56),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _MetaRow(dateLabel: dateLabel, fileCount: files.length, l: l),
                  if (content.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 8),
                      child: Text(l.t('description').toUpperCase(), style: sectionCaptionStyle(context)),
                    ),
                    // Тело лекции — обычный текст на фоне страницы, как в Apple
                    // Notes: раньше он лежал в серой карточке, которая на
                    // длинном конспекте читалась как бесконечная плашка.
                    Text(content, textAlign: TextAlign.left, style: detailBodyStyle(context)),
                  ],
                  if (files.isNotEmpty) ...[
                    SizedBox(height: content.isNotEmpty ? 30 : 26),
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 8),
                      child: Text(l.t('attached_files_edit').toUpperCase(), style: sectionCaptionStyle(context)),
                    ),
                    FileList(
                      files: [
                        for (final f in files) FileEntry(name: _fileDisplayName(f), url: f, previewUrl: f),
                      ],
                      onOpen: (f) => onOpenFile(context, f.url, f.name),
                    ),
                  ],
                  if (content.isEmpty && files.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 56),
                      child: Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(CupertinoIcons.book, size: 32, color: detailText2(context).withValues(alpha: 0.6)),
                          const SizedBox(height: 14),
                          Text(l.t('content_empty'),
                              style: TextStyle(fontSize: 16, color: detailText2(context), fontWeight: FontWeight.w500, letterSpacing: -0.2)),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String dateLabel;
  final int fileCount;
  final L10n l;
  const _MetaRow({required this.dateLabel, required this.fileCount, required this.l});

  @override
  Widget build(BuildContext context) {
    // Метаданные — капсулы-чипы на заливке, а не серая строка иконок с точкой:
    // так дата и число вложений читаются как два отдельных факта о лекции и не
    // соревнуются по весу с текстом ниже.
    return Wrap(spacing: 8, runSpacing: 8, children: [
      _chip(context, CupertinoIcons.calendar, dateLabel),
      if (fileCount > 0)
        _chip(context, CupertinoIcons.paperclip,
            '$fileCount ${fileCount == 1 ? l.t('file') : l.t('files')}'),
    ]);
  }

  Widget _chip(BuildContext context, IconData icon, String text) {
    final text2 = detailText2(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: detailSurface(context),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: detailBorder(context), width: 1 / MediaQuery.of(context).devicePixelRatio),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: text2),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontSize: 14, color: text2, fontWeight: FontWeight.w500, letterSpacing: -0.2)),
      ]),
    );
  }
}

String _fileDisplayName(String url) {
  try {
    final uri = Uri.parse(url);
    if (uri.fragment.isNotEmpty) return Uri.decodeComponent(uri.fragment);
    return uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => url);
  } catch (_) {
    return url;
  }
}
