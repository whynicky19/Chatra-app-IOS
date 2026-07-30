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
            fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.5,
            color: detailText1(context),
          ),
          navTitleTextStyle: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, color: detailText1(context),
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: bg,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            CupertinoSliverNavigationBar(
              backgroundColor: bg,
              border: null,
              stretch: true,
              largeTitle: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 48),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _MetaRow(dateLabel: dateLabel, fileCount: files.length, l: l),
                  const SizedBox(height: 28),
                  if (content.isNotEmpty)
                    Text(
                      content,
                      textAlign: TextAlign.left,
                      style: TextStyle(fontSize: 17, height: 1.65, letterSpacing: 0.1, color: detailText1(context)),
                    ),
                  if (files.isNotEmpty) ...[
                    SizedBox(height: content.isNotEmpty ? 36 : 0),
                    Text(l.t('attached_files_edit'),
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: detailText1(context))),
                    const SizedBox(height: 12),
                    for (final f in files) ...[
                      FileCard(
                        name: _fileDisplayName(f),
                        onTap: () => onOpenFile(context, f, _fileDisplayName(f)),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                  if (content.isEmpty && files.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(CupertinoIcons.book, size: 34, color: detailText2(context)),
                          const SizedBox(height: 14),
                          Text(l.t('content_empty'),
                              style: TextStyle(fontSize: 15, color: detailText2(context), fontWeight: FontWeight.w500)),
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
    final text2 = detailText2(context);
    return Row(children: [
      Icon(CupertinoIcons.calendar, size: 14, color: text2),
      const SizedBox(width: 5),
      Text(dateLabel, style: TextStyle(fontSize: 15, color: text2, fontWeight: FontWeight.w500)),
      if (fileCount > 0) ...[
        const SizedBox(width: 10),
        Container(width: 3, height: 3, decoration: BoxDecoration(color: text2, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Text('$fileCount ${fileCount == 1 ? l.t('file') : l.t('files')}',
            style: TextStyle(fontSize: 15, color: text2, fontWeight: FontWeight.w500)),
      ],
    ]);
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
