import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/image_cache.dart';
import '../../../widgets/network_cover_image.dart';
import '../../../widgets/toast.dart';

class ClassCoverSliver extends StatelessWidget {
  final int classId;
  final String title;
  final String desc;
  final dynamic coverImg;
  final bool isTeacher;
  final String inviteCode;
  final bool isArchived;
  final String archivedLabel;
  final String codeLabel;
  final String codeCopiedLabel;
  final String regenerateLabel;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onRegenerateCode;

  const ClassCoverSliver({
    super.key,
    required this.classId,
    required this.title,
    required this.desc,
    required this.coverImg,
    required this.isTeacher,
    required this.inviteCode,
    required this.isArchived,
    required this.archivedLabel,
    required this.codeLabel,
    required this.codeCopiedLabel,
    required this.regenerateLabel,
    required this.onBack,
    required this.onEdit,
    required this.onRegenerateCode,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isData = coverImg != null && coverImg.toString().startsWith('data:');
    final isNetwork = coverImg != null && !isData;

    Widget cover;
    if (isNetwork) {
      cover = RepaintBoundary(child: NetworkCoverImage(
        url: coverImg.toString(),
        cacheKey: 'class_cover_$classId',
        alignment: Alignment.topCenter,
        memCacheWidth: 800,
      ));
    } else if (isData) {
      final bytes = decodeBase64Image(coverImg.toString());
      cover = bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover, alignment: Alignment.topCenter, gaplessPlayback: true, cacheWidth: 1080)
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
      leading: IconButton(
        padding: EdgeInsets.zero,
        icon: Container(width: 34, height: 34, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(AppRadii.chip)), child: const Icon(CupertinoIcons.chevron_left, color: Colors.white, size: 20)),
        onPressed: onBack,
      ),
      actions: [
        if (isTeacher) IconButton(
          padding: EdgeInsets.zero,
          icon: Container(width: 34, height: 34, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(AppRadii.chip)), child: const Icon(CupertinoIcons.pencil, color: Colors.white70, size: 18)),
          onPressed: onEdit,
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: LayoutBuilder(builder: (context, constraints) {
        final topPad = MediaQuery.of(context).padding.top;
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
          Container(decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            stops: [0.0, 0.4, 1.0],
            colors: [Colors.black38, Colors.transparent, Colors.black54],
          ))),
          if (collapsedTitleOpacity > 0)
            Positioned(top: topPad, left: 56, right: 56, height: kToolbarHeight,
              child: Opacity(opacity: collapsedTitleOpacity, child: Center(
                child: Text(title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
              ))),
          Positioned(bottom: 16, left: 16, right: 16, child: Opacity(opacity: settle, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (isArchived) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(CupertinoIcons.archivebox, size: 13, color: Colors.white70),
                  const SizedBox(width: 5),
                  Text(archivedLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white70, letterSpacing: 0.3)),
                ]),
              ),
              const SizedBox(height: 8),
            ],
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 6)]), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
            if (isTeacher && inviteCode.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                GestureDetector(
                  onTap: () { Clipboard.setData(ClipboardData(text: inviteCode)); showToast(context, '$codeCopiedLabel: $inviteCode'); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: adaptivePrimaryLt(context).withValues(alpha: 0.9), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(CupertinoIcons.doc_on_doc, size: 14, color: primary),
                      const SizedBox(width: 6),
                      Text('$codeLabel: ', style: TextStyle(fontSize: 13, color: primary)),
                      Text(inviteCode, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: primary, letterSpacing: 2)),
                    ]),
                  ),
                ),
                GestureDetector(
                  onTap: onRegenerateCode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(CupertinoIcons.refresh, size: 13, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(regenerateLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                    ]),
                  ),
                ),
              ]),
            ],
          ]))),
        ]),
      );
      }),
    );
  }
}
