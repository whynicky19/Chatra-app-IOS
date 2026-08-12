import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/l10n_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/inset_group.dart';
import '../../../widgets/tappable.dart';
import '../../moderation/report_sheet.dart';
import '../class_detail_utils.dart' show fmtDate, extractFileUrls;

// Список лекций перерисовывается на каждое изменение _posts — regex внутри
// clean()/preview() иначе компилировался бы заново на каждую карточку при
// каждой перестройке (ListView.builder вызывает их для каждого видимого
// элемента).
final _lectureTitleRe = RegExp(r'^\[LECTURE\]\[\d+\]\s*');
final _urlRe = RegExp(r'https?://\S+');
final _wsRe = RegExp(r'\s+');

class ClassPostsTab extends StatelessWidget {
  final List<dynamic> posts;
  final bool isTeacher;
  final void Function(dynamic post, int num) onShowPost;
  final void Function(dynamic post) onEditPost;
  final void Function(int postId) onDeletePost;
  final Future<void> Function() onRefresh;

  const ClassPostsTab({
    super.key,
    required this.posts,
    required this.isTeacher,
    required this.onShowPost,
    required this.onEditPost,
    required this.onDeletePost,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.read<L10n>();
    final accentColor = Theme.of(context).colorScheme.primary;

    String clean(String t) => t.replaceFirst(_lectureTitleRe, '').trim();

    String preview(dynamic p) {
      try {
        final b = jsonDecode(p['body']);
        return (b['content'] ?? b['description'] ?? '').replaceAll(_urlRe, '').replaceAll(_wsRe, ' ').trim();
      } catch (_) { return ''; }
    }

    // Вложения лекции живут либо структурированным списком в body.files, либо
    // просто ссылками в тексте (старые записи) — считаем оба варианта, иначе
    // у половины лекций счётчик файлов молча показывал бы ноль.
    int fileCount(dynamic p) {
      try {
        final b = jsonDecode(p['body']);
        if (b['files'] is List) return (b['files'] as List).length;
      } catch (_) {}
      return extractFileUrls((p['body'] ?? '').toString()).length;
    }

    int? postId(dynamic p) => (p['id'] as num?)?.toInt();

    void showActions(dynamic p) {
      final id = postId(p);
      showAppActionSheet(context,
        actions: [
          if (isTeacher) ...[
            AppActionSheetAction(icon: CupertinoIcons.pencil, label: l.t('edit'), onTap: () => onEditPost(p)),
            AppActionSheetAction(icon: CupertinoIcons.trash, label: l.t('delete'), destructive: true, onTap: () => onDeletePost(id!)),
          ],
          // Жалоба доступна всем — это требование App Store Guideline 1.2
          // для приложений с пользовательским контентом.
          if (id != null)
            AppActionSheetAction(
              icon: CupertinoIcons.flag,
              label: l.t('report'),
              destructive: true,
              onTap: () => openReportSheet(
                context,
                target: ReportTarget.post,
                targetId: id,
              ),
            ),
        ],
        cancelText: l.t('cancel'),
      );
    }

    if (posts.isEmpty) {
      return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: onRefresh),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 40, 60),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 76, height: 76,
              decoration: BoxDecoration(gradient: RadialGradient(colors: [accentColor.withValues(alpha: 0.16), accentColor.withValues(alpha: 0.03)]), shape: BoxShape.circle),
              child: Icon(CupertinoIcons.book, size: 32, color: accentColor)),
            const SizedBox(height: 18),
            Text(l.t('no_lectures'), textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: adaptiveText1(context))),
            const SizedBox(height: 6),
            Text(isTeacher ? l.t('add_first_lecture') : l.t('lectures_appear_here'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.4, color: adaptiveText3(context))),
          ]))),
        ),
      ],
    ));
    }

    // Бэкенд отдаёт лекции по возрастанию position (1, 2, 3...) — это нужно
    // ИИ-репетитору для "объясни 2 лекцию". Для отображения в списке студент
    // и учитель ждут обратного порядка: новые лекции сверху.
    final displayPosts = posts.reversed.toList();

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: onRefresh),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          sliver: SliverToBoxAdapter(
            child: SectionTitle(title: l.t('lectures'), padding: EdgeInsets.zero),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
          sliver: SliverList(delegate: SliverChildBuilderDelegate(
            childCount: displayPosts.length,
            (ctx, i) {
              final p = displayPosts[i];
              final body = preview(p);
              final num = displayPosts.length - i;
              final files = fileCount(p);

              return Entrance(
                index: i,
                child: RepaintBoundary(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    // Отдельная карточка на лекцию: каждая лекция — свой
                    // «объект», а не атрибут одного списка, поэтому у неё
                    // собственные скругления, рамка и мягкая тень.
                    child: GroupRow.card(
                    onTap: () => onShowPost(p, num),
                    onLongPress: () => showActions(p),
                    padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Номер лекции — не декор: именно им студент оперирует
                      // в чате с ИИ («объясни лекцию 3»).
                      Container(
                        width: 34, height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadii.chip),
                        ),
                        child: Text('$num',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: accentColor, letterSpacing: -0.2)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(clean(p['title'] ?? ''),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.25, letterSpacing: -0.3, color: adaptiveText1(context)),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3),
                          child: Text(body,
                            style: TextStyle(fontSize: 14, color: adaptiveText3(context), height: 1.35),
                            maxLines: 2, overflow: TextOverflow.ellipsis)),
                        const SizedBox(height: 6),
                        Row(children: [
                          Text(fmtDate(p['created_at'] ?? ''),
                            style: TextStyle(fontSize: 13, color: adaptiveText4(context))),
                          if (files > 0) ...[
                            const SizedBox(width: 8),
                            Icon(CupertinoIcons.paperclip, size: 11, color: adaptiveText4(context)),
                            const SizedBox(width: 3),
                            Text('$files', style: TextStyle(fontSize: 13, color: adaptiveText4(context))),
                          ],
                        ]),
                      ])),
                      const SizedBox(width: 4),
                      // Меню доступно всем: учителю — правка/удаление, студенту —
                      // жалоба. Раньше оно было только у преподавателя, из-за чего
                      // пожаловаться на контент было невозможно в принципе.
                      Tappable(
                        onTap: () => showActions(p),
                        label: 'Действия с лекцией',
                        child: SizedBox(width: 32, height: 44,
                          child: Icon(CupertinoIcons.ellipsis, size: 17, color: adaptiveText4(context))),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 10, right: 6),
                        child: Icon(CupertinoIcons.chevron_right, size: 14, color: adaptiveText4(context).withValues(alpha: 0.7)),
                      ),
                    ]),
                  ),
                  ),
                ),
              );
            },
          )),
        ),
      ]),
    );
  }
}
