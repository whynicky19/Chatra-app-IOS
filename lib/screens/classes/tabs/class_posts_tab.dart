import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/l10n_provider.dart';
import '../../../services/api_service.dart';
import '../../../theme/app_theme.dart';

class ClassPostsTab extends StatelessWidget {
  final List<dynamic> posts;
  final String type;
  final bool isTeacher;
  final Map<String, String> fileTexts;
  final void Function(dynamic post, String type, int num) onShowPost;
  final void Function(dynamic post) onEditPost;
  final void Function(int postId) onDeletePost;

  const ClassPostsTab({
    super.key,
    required this.posts,
    required this.type,
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
    final isLecture = type == 'lecture';
    final accentColor = isLecture ? C.teal : const Color(0xFF6366F1);
    final baseUrl = context.read<ApiService>().baseUrl;

    String fixFileUrl(String url) {
      if (url.isEmpty) return url;
      var fixed = url
          .replaceAll(RegExp(r'https?://localhost:\d+'), baseUrl)
          .replaceAll(RegExp(r'https?://127\.0\.0\.1:\d+'), baseUrl);
      if (!fixed.startsWith('http') && !fixed.startsWith('ws')) {
        fixed = '$baseUrl${fixed.startsWith('/') ? '' : '/'}$fixed';
      }
      return fixed;
    }

    String clean(String t) => t.replaceFirst(RegExp(r'^\[(LECTURE|HW)\]\[\d+\]\s*'), '').trim();

    String preview(dynamic p) {
      try {
        final b = jsonDecode(p['body']);
        return (b['content'] ?? b['description'] ?? '').replaceAll(RegExp(r'https?://\S+'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
      } catch (_) { return ''; }
    }

    String fmtDate(String? d) {
      if (d == null) return '';
      try { final dt = DateTime.parse(d); return '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year}'; } catch (_) { return d; }
    }

    List<String> extractFiles(dynamic p) {
      try {
        final b = jsonDecode(p['body'] ?? '');
        if (b['files'] is List && (b['files'] as List).isNotEmpty) {
          return (b['files'] as List).map((f) => fixFileUrl(f.toString())).toList();
        }
      } catch (_) {}
      final body = p['body'] ?? '';
      final matches = RegExp(r'https?://[^\s"<>]+\.(pdf|doc|docx|txt|png|jpg|jpeg|pptx?|xlsx?)', caseSensitive: false).allMatches(body);
      return matches.map((m) => fixFileUrl(m.group(0)!)).toList();
    }

    Widget iconBtn(IconData ic, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(color: C.teal.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
        child: Icon(ic, size: 17, color: C.text4),
      ),
    );

    if (posts.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80,
        decoration: BoxDecoration(gradient: RadialGradient(colors: [accentColor.withOpacity(0.18), accentColor.withOpacity(0.04)]), shape: BoxShape.circle),
        child: Icon(isLecture ? Icons.menu_book_rounded : Icons.inventory_2_outlined, size: 36, color: accentColor)),
      SizedBox(height: 18),
      Text(isLecture ? l.t('no_lectures') : l.t('no_materials'),
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: adaptiveText1(context))),
      SizedBox(height: 6),
      Text(isTeacher ? 'Добавьте первый материал' : 'Здесь появятся материалы курса',
        style: TextStyle(fontSize: 13, color: C.text4)),
    ]));

    return ListView.builder(padding: EdgeInsets.fromLTRB(14, 14, 14, 90), itemCount: posts.length, itemBuilder: (ctx, i) {
      final p = posts[i];
      final files = extractFiles(p);
      final body = preview(p);
      final num = posts.length - i;

      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: Duration(milliseconds: 260 + i * 55),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: child)),
        child: GestureDetector(
          onTap: () => onShowPost(p, type, num),
          child: Container(
            margin: EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(20), boxShadow: cardShadow(isDark)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: EdgeInsets.fromLTRB(16, 16, 14, 14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 54, height: 54,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accentColor.withOpacity(0.18)),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(isLecture ? Icons.menu_book_rounded : Icons.inventory_2_outlined, color: accentColor, size: 20),
                    SizedBox(height: 2),
                    Text('$num', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: accentColor, height: 1)),
                  ])),
                SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: accentColor.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                    child: Text('${isLecture ? 'ЛЕКЦИЯ' : 'МАТЕРИАЛ'} $num',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: accentColor, letterSpacing: 0.6)),
                  ),
                  SizedBox(height: 6),
                  Text(clean(p['title'] ?? ''),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.25, color: adaptiveText1(context)),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (body.isNotEmpty) Padding(padding: EdgeInsets.only(top: 5),
                    child: Text(body, style: TextStyle(fontSize: 13, color: C.text4, height: 1.45), maxLines: 2, overflow: TextOverflow.ellipsis)),
                ])),
                if (isTeacher) Column(mainAxisSize: MainAxisSize.min, children: [
                  iconBtn(Icons.edit_outlined, () => onEditPost(p)),
                  SizedBox(height: 4),
                  iconBtn(Icons.delete_outline, () => onDeletePost(p['id'] as int)),
                ]),
              ])),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: adaptiveSurface2(context).withOpacity(0.55),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                ),
                child: Row(children: [
                  Icon(Icons.access_time_rounded, size: 12, color: C.text4),
                  SizedBox(width: 4),
                  Text(fmtDate(p['created_at'] ?? ''), style: TextStyle(fontSize: 12, color: C.text4)),
                  if (files.isNotEmpty) ...[
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: accentColor.withOpacity(0.10), borderRadius: BorderRadius.circular(6)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.attach_file_rounded, size: 10, color: accentColor),
                        SizedBox(width: 3),
                        Text('${files.length}', style: TextStyle(fontSize: 11, color: accentColor, fontWeight: FontWeight.w700)),
                      ])),
                  ],
                  Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: accentColor.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(l.t('open'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accentColor)),
                      SizedBox(width: 3),
                      Icon(Icons.arrow_forward_rounded, size: 12, color: accentColor),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      );
    });
  }
}
