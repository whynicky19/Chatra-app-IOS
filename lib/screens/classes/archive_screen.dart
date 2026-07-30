import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../providers/classes_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_cache.dart';
import '../../widgets/network_cover_image.dart';
import '../../utils/haptics.dart';

class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  static const _grads = [
    [Color(0xFF006475), Color(0xFF009AAF)],
    [Color(0xFF0C4A6E), Color(0xFF0369A1)],
    [Color(0xFF134E4A), Color(0xFF0D9488)],
    [Color(0xFF312E81), Color(0xFF4338CA)],
    [Color(0xFF1E3A5F), Color(0xFF2563EB)],
  ];

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final provider = context.watch<ClassesProvider>();
    final classes = provider.archivedClasses;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
              child: Row(children: [
                IconButton(
                  icon: Icon(CupertinoIcons.back, color: adaptiveText1(context)),
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: adaptiveSurface2(context),
                      borderRadius: BorderRadius.circular(AppRadii.tile),
                    ),
                    child: Icon(CupertinoIcons.archivebox,
                        size: 22, color: adaptiveText1(context).withValues(alpha: 0.7)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.t('archive'),
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700,
                              color: adaptiveText1(context), letterSpacing: -0.4, height: 1.05)),
                      const SizedBox(height: 3),
                      Text(l.t('archive_subtitle'),
                          style: TextStyle(fontSize: 13,
                              color: adaptiveText1(context).withValues(alpha: 0.55), height: 1.35)),
                    ]),
                  ),
                ]),
              ]),
            ),
          ),

          if (classes.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyArchive(l: l),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList.builder(
                itemCount: classes.length,
                itemBuilder: (context, i) {
                  final cls = classes[i];
                  final id = cls['id'] as int;
                  return _ArchiveCard(
                    cls: cls,
                    colors: _grads[id % _grads.length],
                    isDark: isDark,
                    onTap: () {
                      hapticLight();
                      Navigator.pushNamed(context, '/class', arguments: id);
                    },
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }
}

class _EmptyArchive extends StatelessWidget {
  final L10n l;
  const _EmptyArchive({required this.l});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76, height: 76,
              decoration: BoxDecoration(
                color: adaptiveSurface2(context),
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Icon(CupertinoIcons.archivebox,
                  size: 34, color: adaptiveText1(context).withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 16),
            Text(l.t('archive_empty'),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                    color: adaptiveText1(context).withValues(alpha: 0.8))),
            const SizedBox(height: 6),
            SizedBox(
              width: 260,
              child: Text(l.t('archive_empty_sub'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.5,
                      color: adaptiveText1(context).withValues(alpha: 0.5))),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveCard extends StatelessWidget {
  final Map<String, dynamic> cls;
  final List<Color> colors;
  final bool isDark;
  final VoidCallback onTap;

  const _ArchiveCard({
    required this.cls,
    required this.colors,
    required this.isDark,
    required this.onTap,
  });

  static const List<double> _muted = [
    0.685, 0.286, 0.029, 0, 0,
    0.085, 0.886, 0.029, 0, 0,
    0.085, 0.286, 0.629, 0, 0,
    0,     0,     0,     1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final surface = Theme.of(context).colorScheme.surface;
    final coverImg = cardCoverUrl(cls);
    final title = (cls['name'] ?? cls['title'] ?? '').toString();
    final teacher = (cls['teacher'] ?? cls['teacher_name'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            boxShadow: cardShadow(isDark),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: SizedBox(
                height: 120, width: double.infinity,
                child: ColorFiltered(
                  colorFilter: const ColorFilter.matrix(_muted),
                  child: Stack(fit: StackFit.expand, children: [
                    Container(decoration: BoxDecoration(gradient: LinearGradient(
                        colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight))),
                    if (coverImg != null)
                      coverImg.toString().startsWith('data:')
                          ? Builder(builder: (_) {
                              final bytes = decodeBase64Image(coverImg.toString());
                              return bytes != null
                                  ? Image.memory(bytes, fit: BoxFit.cover, width: double.infinity,
                                      gaplessPlayback: true, cacheWidth: 480)
                                  : const SizedBox.shrink();
                            })
                          : NetworkCoverImage(
                              url: context.read<ApiService>().fixUrl(coverImg.toString()),
                              memCacheWidth: 480,
                            ),
                    Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      stops: const [0.45, 1.0],
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.35)],
                    )))),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: adaptiveText1(context).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadii.chip),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(CupertinoIcons.archivebox, size: 10,
                              color: adaptiveText1(context).withValues(alpha: 0.55)),
                          const SizedBox(width: 4),
                          Text(l.t('archived_badge').toUpperCase(),
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                  color: adaptiveText1(context).withValues(alpha: 0.55))),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                            color: adaptiveText1(context), letterSpacing: -0.3)),
                    if (teacher.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(teacher, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13,
                              color: adaptiveText1(context).withValues(alpha: 0.55))),
                    ],
                  ]),
                ),
                Icon(CupertinoIcons.chevron_right, size: 18,
                    color: adaptiveText1(context).withValues(alpha: 0.35)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
