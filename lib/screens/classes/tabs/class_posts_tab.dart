import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/l10n_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_dialog.dart';
import '../class_detail_utils.dart' show fmtDate;

class ClassPostsTab extends StatelessWidget {
  final List<dynamic> posts;
  final bool isTeacher;
  final Map<String, String> fileTexts;
  final void Function(dynamic post, int num) onShowPost;
  final void Function(dynamic post) onEditPost;
  final void Function(int postId) onDeletePost;

  const ClassPostsTab({
    super.key,
    required this.posts,
    required this.isTeacher,
    required this.fileTexts,
    required this.onShowPost,
    required this.onEditPost,
    required this.onDeletePost,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.read<L10n>();
    final surface = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = Theme.of(context).colorScheme.primary;

    String clean(String t) => t.replaceFirst(RegExp(r'^\[LECTURE\]\[\d+\]\s*'), '').trim();

    String preview(dynamic p) {
      try {
        final b = jsonDecode(p['body']);
        return (b['content'] ?? b['description'] ?? '').replaceAll(RegExp(r'https?://\S+'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
      } catch (_) { return ''; }
    }

    void showActions(dynamic p) {
      showAppActionSheet(context,
        actions: [
          AppActionSheetAction(icon: CupertinoIcons.pencil, label: l.t('edit'), onTap: () => onEditPost(p)),
          AppActionSheetAction(icon: CupertinoIcons.trash, label: l.t('delete'), destructive: true, onTap: () => onDeletePost(p['id'] as int)),
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
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 80, height: 80,
              decoration: BoxDecoration(gradient: RadialGradient(colors: [accentColor.withValues(alpha: 0.18), accentColor.withValues(alpha: 0.04)]), shape: BoxShape.circle),
              child: Icon(CupertinoIcons.book, size: 36, color: accentColor)),
            const SizedBox(height: 18),
            Text(l.t('no_lectures'),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: adaptiveText1(context))),
            const SizedBox(height: 6),
            Text(isTeacher ? l.t('add_first_lecture') : l.t('lectures_appear_here'),
              style: const TextStyle(fontSize: 13, color: C.text4)),
          ])),
        ),
      ],
    ));
    }

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: ListView.builder(padding: const EdgeInsets.fromLTRB(14, 14, 14, 90), itemCount: posts.length, itemBuilder: (ctx, i) {
      final p = posts[i];
      final body = preview(p);
      final num = posts.length - i;

      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: Duration(milliseconds: 260 + i * 55),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: child)),
        child: RepaintBoundary(child: GestureDetector(
          onTap: () => onShowPost(p, num),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(AppRadii.card), boxShadow: cardShadow(isDark)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 16, 8, 14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(clean(p['title'] ?? ''),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.25, color: adaptiveText1(context)),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5),
                    child: Text(body, style: const TextStyle(fontSize: 13, color: C.text4, height: 1.45), maxLines: 2, overflow: TextOverflow.ellipsis)),
                ])),
                if (isTeacher) GestureDetector(
                  onTap: () => showActions(p),
                  child: Container(width: 34, height: 34, alignment: Alignment.center,
                    child: const Icon(CupertinoIcons.ellipsis, size: 18, color: C.text4)),
                ),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: adaptiveSurface2(context).withValues(alpha: 0.55),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                ),
                child: Row(children: [
                  const Icon(CupertinoIcons.clock, size: 12, color: C.text4),
                  const SizedBox(width: 4),
                  Text(fmtDate(p['created_at'] ?? ''), style: const TextStyle(fontSize: 12, color: C.text4)),
                  const Spacer(),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(l.t('open'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accentColor)),
                    const SizedBox(width: 3),
                    Icon(CupertinoIcons.chevron_right, size: 12, color: accentColor),
                  ]),
                ]),
              ),
            ]),
          ),
        )),
      );
    }));
  }
}
