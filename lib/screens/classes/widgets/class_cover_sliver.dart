import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/image_cache.dart';
import '../../../widgets/network_cover_image.dart';
import '../../../widgets/subject_cover.dart';
import '../../../widgets/tappable.dart';

class ClassCoverSliver extends StatelessWidget {
  final String title;
  final String desc;
  final dynamic coverImg;

  /// Слаг предметной иконки; null — легаси-обложка, оверлей не рисуем.
  final String? coverIcon;

  /// Слаг цвета обложки — из него берётся тон иконки.
  final String? coverColor;

  final bool isTeacher;
  final bool isArchived;
  final String archivedLabel;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onSettings;

  const ClassCoverSliver({
    super.key,
    required this.title,
    required this.desc,
    required this.coverImg,
    this.coverIcon,
    this.coverColor,
    required this.isTeacher,
    required this.isArchived,
    required this.archivedLabel,
    required this.onBack,
    required this.onEdit,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isData = coverImg != null && coverImg.toString().startsWith('data:');
    final isNetwork = coverImg != null && !isData;
    // Полноэкранная обложка — кэш-растр по ширине экрана × DPR, иначе на
    // retina обложка декодируется мельче виджета и размывается при растяжке.
    final coverCacheWidth = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round();

    Widget cover;
    if (isNetwork) {
      cover = RepaintBoundary(child: NetworkCoverImage(
        url: coverImg.toString(),
        alignment: Alignment.topCenter,
        memCacheWidth: coverCacheWidth,
      ));
    } else if (isData) {
      final bytes = decodeBase64Image(coverImg.toString());
      cover = bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover, alignment: Alignment.topCenter, gaplessPlayback: true, cacheWidth: coverCacheWidth)
          : const SizedBox.shrink();
    } else {
      cover = const SizedBox.shrink();
    }

    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      forceMaterialTransparency: true,
      leading: Tappable(
        onTap: onBack,
        label: 'Назад',
        child: Container(width: 34, height: 34, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(AppRadii.chip)), child: const Icon(CupertinoIcons.chevron_left, color: Colors.white, size: 20)),
      ),
      flexibleSpace: LayoutBuilder(builder: (context, constraints) {
        final topPad = MediaQuery.paddingOf(context).top;
        final settle = ((constraints.maxHeight - kToolbarHeight - topPad) /
                (220 - kToolbarHeight))
            .clamp(0.0, 1.0);
        final collapsedTitleOpacity = ((0.3 - settle) / 0.3).clamp(0.0, 1.0);
        return FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        titlePadding: EdgeInsets.zero,
        background: Stack(fit: StackFit.expand, children: [
          Container(decoration: BoxDecoration(gradient: LinearGradient(
            colors: [const Color(0xFF006475), primary],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ))),
          cover,
          SubjectIconOverlay(icon: coverIcon, color: coverColor, size: 74),
          // Затемняем только низ, где лежат название и описание. Раньше сверху
          // тоже стояла плёнка ради контраста кнопок — но у них свои тёмные
          // кружки, а светлую пастельную обложку эта плёнка гасила в серое.
          Container(decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            stops: [0.45, 1.0],
            colors: [Colors.transparent, Colors.black54],
          ))),
          if (collapsedTitleOpacity > 0)
            Positioned(top: topPad, left: 56, right: 56, height: kToolbarHeight,
              child: Opacity(opacity: collapsedTitleOpacity, child: Center(
                child: Text(title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
              ))),
          // Настройки/редактирование скрыты в панели инструментов намеренно: они должны
          // уходить вместе с обложкой при скролле, а не оставаться закреплёнными как back-кнопка.
          if (isTeacher && settle > 0)
            Positioned(top: topPad, right: 8, height: kToolbarHeight,
              child: Opacity(opacity: settle, child: IgnorePointer(ignoring: settle < 0.3, child: Row(children: [
                Tappable(
                  onTap: onSettings,
                  label: 'Настройки класса',
                  child: Container(width: 34, height: 34, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(AppRadii.chip)), child: const Icon(CupertinoIcons.gear_alt_fill, color: Colors.white70, size: 17)),
                ),
                const SizedBox(width: 6),
                Tappable(
                  onTap: onEdit,
                  label: 'Редактировать класс',
                  child: Container(width: 34, height: 34, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(AppRadii.chip)), child: const Icon(CupertinoIcons.pencil, color: Colors.white70, size: 18)),
                ),
                const SizedBox(width: 8),
              ])))),
          Positioned(bottom: 16, left: 16, right: 16, child: Opacity(opacity: settle, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (isArchived) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(CupertinoIcons.archivebox, size: 13, color: Colors.white70),
                  const SizedBox(width: 5),
                  Text(archivedLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70, letterSpacing: 0.3)),
                ]),
              ),
              const SizedBox(height: 8),
            ],
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 6)]), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ]))),
        ]),
      );
      }),
    );
  }
}
