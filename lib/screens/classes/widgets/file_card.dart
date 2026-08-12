import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/inset_group.dart';
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

/// Один файл списка вложений.
class FileEntry {
  final String name;
  final String url;

  /// Ссылка на превью для картинок; null — рисуем иконку типа файла.
  final String? previewUrl;
  final String? sizeLabel;

  const FileEntry({required this.name, required this.url, this.previewUrl, this.sizeLabel});
}

/// Список вложений одной сгруппированной секцией в духе Apple Files: вместо
/// стопки отдельных карточек с зазорами — одна группа, строки внутри разделены
/// волосяной линией, выровненной по началу текста.
///
/// Раньше каждый файл был самостоятельной карточкой с рамкой: при трёх-четырёх
/// вложениях страница превращалась в лестницу рамок, конкурирующих за
/// внимание с самим заданием.
class FileList extends StatelessWidget {
  const FileList({super.key, required this.files, required this.onOpen});

  final List<FileEntry> files;
  final void Function(FileEntry file) onOpen;

  @override
  Widget build(BuildContext context) {
    return InsetGroup(
      color: detailSurface(context),
      children: [
        for (var i = 0; i < files.length; i++)
          GroupRow(
            // Скругление даёт контейнер группы, строке остаются только
            // разделитель и подсветка нажатия.
            pos: innerPos(i, files.length),
            color: Colors.transparent,
            separatorInset: 64,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            label: 'Открыть файл ${files[i].name}',
            onTap: () => onOpen(files[i]),
            child: _FileRowContent(file: files[i]),
          ),
      ],
    );
  }
}

class _FileRowContent extends StatelessWidget {
  const _FileRowContent({required this.file});

  final FileEntry file;

  @override
  Widget build(BuildContext context) {
    final name = file.name;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final visual = fileTypeVisual(ext);
    final typeLabel = ext.isNotEmpty ? ext.toUpperCase() : '';
    final subtitle = file.sizeLabel != null && file.sizeLabel!.isNotEmpty
        ? '$typeLabel • ${file.sizeLabel}'
        : typeLabel;
    // Без memCacheWidth/Height CachedNetworkImage декодирует превью в
    // исходном разрешении файла ради плитки 40×40 — в списке вложений с
    // несколькими фото это лишняя память и CPU на decode на каждую строку.
    final previewPx = (40 * MediaQuery.of(context).devicePixelRatio).round();
    final hasPreview = _imagePreviewExts.contains(ext) && file.previewUrl != null;

    Widget fallback() => Container(
      width: 40, height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: visual.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Icon(visual.icon, size: 20, color: visual.color),
    );

    return Row(children: [
      hasPreview
          ? ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.chip),
              child: CachedNetworkImage(
                imageUrl: file.previewUrl!,
                cacheKey: fileCacheKey(file.previewUrl!),
                memCacheWidth: previewPx, memCacheHeight: previewPx,
                width: 40, height: 40, fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (_, __) => fallback(),
                errorWidget: (_, __, ___) => fallback(),
              ),
            )
          : fallback(),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: detailText1(context)),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(subtitle, style: TextStyle(fontSize: 13, color: detailText2(context))),
          ],
        ]),
      ),
      const SizedBox(width: 8),
      Icon(CupertinoIcons.chevron_right, size: 14, color: detailText2(context).withValues(alpha: 0.8)),
    ]);
  }
}
