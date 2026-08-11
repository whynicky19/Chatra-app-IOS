import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/tappable.dart';
import '../class_detail_utils.dart' show fileCacheKey;
import 'detail_page_theme.dart';

const _imagePreviewExts = {'jpg', 'jpeg', 'png', 'gif', 'webp'};

class FileTypeVisual {
  final IconData icon;
  final Color color;
  const FileTypeVisual(this.icon, this.color);
}

FileTypeVisual fileTypeVisual(String ext) {
  switch (ext) {
    case 'pdf':
      return const FileTypeVisual(CupertinoIcons.doc_text_fill, Color(0xFFE5484D));
    case 'pptx':
    case 'ppt':
      return const FileTypeVisual(CupertinoIcons.film, Color(0xFFF2A93B));
    case 'doc':
    case 'docx':
      return const FileTypeVisual(CupertinoIcons.doc_text_fill, Color(0xFF3B9FF2));
    case 'xlsx':
    case 'xls':
      return const FileTypeVisual(CupertinoIcons.square_grid_2x2_fill, Color(0xFF3BBF6E));
    case 'txt':
    case 'md':
      return const FileTypeVisual(CupertinoIcons.doc_plaintext, Color(0xFFA681E8));
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
      return const FileTypeVisual(CupertinoIcons.photo_fill, Color(0xFF3BB6F2));
    case 'mp4':
    case 'mov':
    case 'avi':
      return const FileTypeVisual(CupertinoIcons.play_circle_fill, Color(0xFFC46BE0));
    default:
      return const FileTypeVisual(CupertinoIcons.doc_fill, Color(0xFF9A9A9A));
  }
}

/// Карточка вложенного файла в духе Apple Files: своя независимая карточка,
/// крупная иконка типа файла, имя, тип, шеврон открытия, лёгкая press-анимация.
class FileCard extends StatelessWidget {
  final String name;
  final String? sizeLabel;
  final String? previewUrl;
  final VoidCallback onTap;

  const FileCard({super.key, required this.name, this.sizeLabel, this.previewUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final visual = fileTypeVisual(ext);
    final typeLabel = ext.isNotEmpty ? ext.toUpperCase() : '';
    final subtitle = sizeLabel != null && sizeLabel!.isNotEmpty
        ? '$typeLabel • $sizeLabel'
        : typeLabel;

    return Tappable(
      onTap: onTap,
      label: 'Открыть файл $name',
      child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: detailSurface(context),
            borderRadius: BorderRadius.circular(AppRadii.tile),
            border: Border.all(color: detailBorder(context)),
          ),
          child: Row(children: [
            _imagePreviewExts.contains(ext) && previewUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                    child: CachedNetworkImage(
                      imageUrl: previewUrl!,
                      cacheKey: fileCacheKey(previewUrl!),
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (_, __) => Container(
                        width: 44, height: 44,
                        color: visual.color.withValues(alpha: 0.14),
                        child: Icon(visual.icon, size: 20, color: visual.color),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 44, height: 44,
                        color: visual.color.withValues(alpha: 0.14),
                        child: Icon(visual.icon, size: 20, color: visual.color),
                      ),
                    ),
                  )
                : Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: visual.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadii.tile),
                    ),
                    child: Icon(visual.icon, size: 22, color: visual.color),
                  ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: detailText1(context)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: detailText2(context), letterSpacing: 0.2)),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            Icon(CupertinoIcons.chevron_right, size: 17, color: detailText2(context)),
          ]),
      ),
    );
  }
}
